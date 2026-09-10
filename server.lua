local playerRewards = {}

local function notifyPlayer(source, description, notifyType)
    if source ~= 0 then
        TriggerClientEvent('rewards:notify', source, description, notifyType or 'inform')
    end
end

local function hasAdminPermission(source, commandName)
    if source == 0 then return true end
    if IsPlayerAceAllowed(source, Config.AdminAce) or IsPlayerAceAllowed(source, 'command.' .. commandName) then
        return true
    end

    if Config.Qbox and GetResourceState('qbx_core') == 'started' and Config.AdminGroups then
        local success, hasGroup = pcall(function()
            return exports.qbx_core:HasGroup(source, Config.AdminGroups)
        end)
        if success and hasGroup then return true end
    end

    return false
end

local function isFrameworkConfigured()
    if Config.Qbox == Config.Standalone then
        print('^1[Rewards] Enable exactly one of Config.Qbox or Config.Standalone.^7')
        return false
    end

    if Config.Qbox and GetResourceState('qbx_core') ~= 'started' then
        print('^1[Rewards] Config.Qbox is enabled but qbx_core is not started.^7')
        return false
    end

    if Config.Qbox and GetResourceState('ox_inventory') ~= 'started' then
        print('^1[Rewards] ox_inventory must be started when Config.Qbox is enabled.^7')
        return false
    end

    return true
end

local function giveRewardItem(source, rewardIndex)
    local tier = Config.RewardTiers[rewardIndex]
    if not tier or not tier.item then return true, nil, 0 end
    if Config.Standalone then return true, nil, 0 end

    if not isFrameworkConfigured() then return false end

    local amount = math.max(1, math.floor(tonumber(tier.amount) or 1))
    local success, added, response = pcall(function()
        return exports.ox_inventory:AddItem(source, tier.item, amount, tier.metadata)
    end)

    if not success or added ~= true then
        print(("^1[Rewards] Failed to give %s x%d to player %s: %s^7"):format(tier.item, amount, source, tostring(response)))
        return false
    end

    return true, tier.item, amount
end

local function refreshRewardDefinitions(playerData)
    if not playerData.rewards then playerData.rewards = {} end

    for i, tier in ipairs(Config.RewardTiers) do
        local reward = playerData.rewards[i]
        if not reward then
            playerData.rewards[i] = {
                name = tier.name,
                time = tier.time,
                description = tier.description,
                claimed = false,
                claimedAt = nil
            }
        else
            reward.name = tier.name
            reward.time = tier.time
            reward.description = tier.description
        end
    end
end

local function savePlayerData(playerKey)
    local playerData = playerRewards[playerKey]
    if not playerData then return end

    local rewards = json.encode(playerData.rewards or {})
    exports.oxmysql:update_async([[
        INSERT INTO btd_rewards_players
            (player_key, steam_id, discord_id, player_name, active_time, rewards, first_seen, last_seen)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            steam_id = VALUES(steam_id),
            discord_id = VALUES(discord_id),
            player_name = VALUES(player_name),
            active_time = VALUES(active_time),
            rewards = VALUES(rewards),
            last_seen = VALUES(last_seen)
    ]], {
        playerKey,
        playerData.steamId,
        playerData.discordId,
        playerData.playerName,
        playerData.activeTime or 0,
        rewards,
        playerData.firstSeen or os.time(),
        playerData.lastSeen or os.time()
    })
end

local function saveAllPlayerData()
    for playerKey in pairs(playerRewards) do
        savePlayerData(playerKey)
    end
end

local function clearAllPlayerData()
    playerRewards = {}
    exports.oxmysql:update_async('DELETE FROM btd_rewards_players')
    exports.oxmysql:update_async('DELETE FROM btd_rewards_codes')
end

local function storeRewardCode(code, playerKey, rewardIndex, reward)
    local tier = Config.RewardTiers[rewardIndex]
    local success, result = pcall(function()
        return exports.oxmysql:insert_async([[
            INSERT INTO btd_rewards_codes
                (code, player_key, reward_index, reward_name, item_name, item_amount, expires_at, used, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
        ]], {
            code,
            playerKey,
            rewardIndex,
            reward.name,
            tier and tier.item or nil,
            tier and tier.amount or nil,
            os.time() + math.max(60, tonumber(Config.CodeExpiry) or 86400),
            os.time()
        })
    end)

    return success and result ~= nil
end

local function loadAllPlayerData()
    playerRewards = {}
    local rows = exports.oxmysql:query_async('SELECT * FROM btd_rewards_players') or {}

    for _, row in ipairs(rows) do
        local success, rewards = pcall(json.decode, row.rewards or '{}')
        playerRewards[row.player_key] = {
            steamId = row.steam_id,
            discordId = row.discord_id,
            playerName = row.player_name,
            activeTime = tonumber(row.active_time) or 0,
            rewards = success and rewards or {},
            firstSeen = tonumber(row.first_seen) or os.time(),
            lastSeen = tonumber(row.last_seen) or os.time()
        }
        refreshRewardDefinitions(playerRewards[row.player_key])
    end

    if #rows == 0 then
        local legacyData = LoadResourceFile(GetCurrentResourceName(), 'data.json')
        local success, decoded = legacyData and pcall(json.decode, legacyData)
        if success and decoded then
            playerRewards = decoded
            for _, playerData in pairs(playerRewards) do
                refreshRewardDefinitions(playerData)
            end
            saveAllPlayerData()
            print('^2[Rewards] Migrated legacy data.json records into oxmysql.^7')
        end
    end
end

local function getPlayerIdentifiers(source)
    local identifiers = GetPlayerIdentifiers(source)
    local steamId = nil
    local discordId = nil
    
    for _, id in ipairs(identifiers) do
        if string.find(id, "steam:") then
            steamId = id
        elseif string.find(id, "discord:") then
            discordId = id
        end
    end
    
    return steamId, discordId
end

local function createPlayerKey(source, steamId, discordId)
    if steamId then
        return steamId
    elseif discordId then
        return discordId
    else
        local identifiers = GetPlayerIdentifiers(source)
        for _, id in ipairs(identifiers) do
            if string.find(id, "license:") then
                return id
            end
        end
    end
    return "unknown"
end

local function generateRedemptionCode()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local code = Config.CodePrefix .. "-"
    
    local segments = {}
    local segmentLength = 4
    local numSegments = math.ceil(Config.CodeLength / segmentLength)
    
    for i = 1, numSegments do
        local segment = ""
        for j = 1, segmentLength do
            local randomIndex = math.random(1, #chars)
            segment = segment .. chars:sub(randomIndex, randomIndex)
        end
        table.insert(segments, segment)
    end
    
    local timestamp = os.time()
    local hashChars = ""
    for i = 1, 6 do
        local hashIndex = ((timestamp * i) % #chars) + 1
        hashChars = hashChars .. chars:sub(hashIndex, hashIndex)
    end
    table.insert(segments, hashChars)
    
    code = code .. table.concat(segments, "-")
    
    return code
end

local function isValidScreenshot(screenshot)
    if not screenshot or type(screenshot) ~= "string" then
        return false
    end
    
    if not string.match(screenshot, "^data:image/[a-z]+;base64,") then
        return false
    end
    
    if #screenshot < 50000 then
        return false
    end
    
    return true
end

local function sendDiscordWebhook(playerName, playerIdentifier, rewardName, code, screenshot, itemName, itemAmount, serverId)
    if not Config.WebhookURL or Config.WebhookURL == '' then
        return
    end

    local embed = {
        {
            ["title"] = "Reward Redeemed",
            ["color"] = 3066993,
            ["fields"] = {
                {
                    ["name"] = "Player",
                    ["value"] = playerName,
                    ["inline"] = true
                },
                {
                    ["name"] = "Identifier",
                    ["value"] = playerIdentifier,
                    ["inline"] = true
                },
                {
                    ["name"] = "Server ID",
                    ["value"] = tostring(serverId or "unknown"),
                    ["inline"] = true
                },
                {
                    ["name"] = "Mode",
                    ["value"] = Config.Qbox and "Qbox" or "Standalone",
                    ["inline"] = true
                },
                {
                    ["name"] = "Reward",
                    ["value"] = rewardName,
                    ["inline"] = false
                },
                {
                    ["name"] = "Item granted",
                    ["value"] = itemName and (itemName .. " x" .. tostring(itemAmount)) or "Code only",
                    ["inline"] = true
                },
                {
                    ["name"] = "Code",
                    ["value"] = "`" .. code .. "`",
                    ["inline"] = false
                }
            },
            ["footer"] = {
                ["text"] = "Rewards System"
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%S")
        }
    }
    
    if screenshot then
        embed[1]["image"] = {
            ["url"] = screenshot
        }
    end
    
    PerformHttpRequest(Config.WebhookURL, function(err, text, headers)
        if err ~= 200 then
            print("^1[Rewards] Discord webhook error: " .. tostring(err) .. "^7")
        end
    end, 'POST', json.encode({
        username = "Rewards System",
        embeds = embed
    }), {
        ['Content-Type'] = 'application/json'
    })
end

local function sendAuditWebhook(action, actorSource, targetSource, details)
    if not Config.WebhookURL or Config.WebhookURL == '' then return end

    local actorName = actorSource == 0 and 'Console' or (GetPlayerName(actorSource) or 'Unknown')
    local targetName = targetSource and (GetPlayerName(targetSource) or 'Offline') or 'All players'
    local fields = {
        { ["name"] = "Action", ["value"] = action, ["inline"] = false },
        { ["name"] = "Actor", ["value"] = ("%s (ID %s)"):format(actorName, actorSource), ["inline"] = true },
        { ["name"] = "Target", ["value"] = targetName .. (targetSource and (" (ID " .. targetSource .. ")") or ''), ["inline"] = true },
        { ["name"] = "Mode", ["value"] = Config.Qbox and "Qbox" or "Standalone", ["inline"] = true }
    }

    for name, value in pairs(details or {}) do
        fields[#fields + 1] = { ["name"] = name, ["value"] = tostring(value), ["inline"] = true }
    end

    PerformHttpRequest(Config.WebhookURL, function(err)
        if err ~= 200 then
            print("^1[Rewards] Discord audit webhook error: " .. tostring(err) .. "^7")
        end
    end, 'POST', json.encode({
        username = 'Rewards Audit',
        embeds = {{
            title = 'Rewards Administration Log',
            color = 16753920,
            fields = fields,
            footer = { text = 'BTD Rewards' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%S')
        }}
    }), { ['Content-Type'] = 'application/json' })
end

local function initializePlayer(source)
    local steamId, discordId = getPlayerIdentifiers(source)
    local playerKey = createPlayerKey(source, steamId, discordId)
    local shouldSave = false
    
    if not playerRewards[playerKey] then
        playerRewards[playerKey] = {
            steamId = steamId,
            discordId = discordId,
            playerName = GetPlayerName(source),
            activeTime = 0,
            rewards = {},
            firstSeen = os.time(),
            lastSeen = os.time()
        }
        
        for i, tier in ipairs(Config.RewardTiers) do
            playerRewards[playerKey].rewards[i] = {
                name = tier.name,
                time = tier.time,
                description = tier.description,
                claimed = false,
                claimedAt = nil
            }
        end
        shouldSave = true
        
    else
        playerRewards[playerKey].lastSeen = os.time()
        playerRewards[playerKey].playerName = GetPlayerName(source)
        
        local rewardsUpdated = false
        for i, tier in ipairs(Config.RewardTiers) do
            if not playerRewards[playerKey].rewards[i] then
                playerRewards[playerKey].rewards[i] = {
                    name = tier.name,
                    time = tier.time,
                    description = tier.description,
                    claimed = false,
                    claimedAt = nil
                }
                rewardsUpdated = true
            elseif playerRewards[playerKey].rewards[i].name ~= tier.name then
                playerRewards[playerKey].rewards[i].name = tier.name
                playerRewards[playerKey].rewards[i].time = tier.time
                playerRewards[playerKey].rewards[i].description = tier.description
                rewardsUpdated = true
            end
        end
        
        if rewardsUpdated then
            shouldSave = true
        end
    end

    if shouldSave then savePlayerData(playerKey) end
end

RegisterNetEvent('rewards:requestStats')
AddEventHandler('rewards:requestStats', function()
    local source = source
    local steamId, discordId = getPlayerIdentifiers(source)
    local playerKey = createPlayerKey(source, steamId, discordId)
    
    initializePlayer(source)
    
    local stats = {
        activeTime = playerRewards[playerKey].activeTime,
        rewards = playerRewards[playerKey].rewards
    }
    
    TriggerClientEvent('rewards:receiveStats', source, stats)
end)

RegisterNetEvent('rewards:updateActiveTime')
AddEventHandler('rewards:updateActiveTime', function(time)
    local source = source
    local steamId, discordId = getPlayerIdentifiers(source)
    local playerKey = createPlayerKey(source, steamId, discordId)
    
    initializePlayer(source)
    playerRewards[playerKey].activeTime = time
    playerRewards[playerKey].lastSeen = os.time()
    
    saveAllPlayerData()
end)

RegisterNetEvent('rewards:claimReward')
AddEventHandler('rewards:claimReward', function(rewardIndex)
    local source = source
    
    local steamId, discordId = getPlayerIdentifiers(source)
    local playerKey = createPlayerKey(source, steamId, discordId)
    local playerName = GetPlayerName(source)
    
    initializePlayer(source)
    
    local reward = playerRewards[playerKey].rewards[rewardIndex]
    
    if not reward then
        notifyPlayer(source, 'Invalid reward.', 'error')
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Rewards", "Invalid reward!"}
        })
        return
    end
    
    if reward.claimed then
        notifyPlayer(source, "You've already claimed this reward.", 'warning')
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 165, 0},
            multiline = true,
            args = {"Rewards", "You've already claimed this reward!"}
        })
        return
    end
    
    local activeMinutes = playerRewards[playerKey].activeTime / 60
    
    if activeMinutes < reward.time then
        local remainingTime = math.ceil(reward.time - activeMinutes)
        notifyPlayer(source, 'You need ' .. remainingTime .. ' more minutes of active playtime.', 'warning')
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 165, 0},
            multiline = true,
            args = {"Rewards", "You need " .. remainingTime .. " more minutes of active playtime!"}
        })
        return
    end

    local itemName = nil
    local itemAmount = nil
    if Config.Standalone then
        local itemGranted
        itemGranted, itemName, itemAmount = giveRewardItem(source, rewardIndex)
        if Config.RewardTiers[rewardIndex].item then
            notifyPlayer(source, 'Standalone mode does not provide inventory items. Set this reward item to false.', 'warning')
        end
        if not itemGranted then
            notifyPlayer(source, 'The reward item could not be given. Make space in your inventory.', 'error')
            TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                multiline = true,
                args = {"Rewards", "The reward item could not be given. Check the server console and make space in your inventory."}
            })
            return
        end
    end

    local code

    if Config.Qbox then
        code = generateRedemptionCode()
        if not storeRewardCode(code, playerKey, rewardIndex, reward) then
            notifyPlayer(source, 'Could not create the reward key. Try again.', 'error')
            return
        end
    end
    
    playerRewards[playerKey].rewards[rewardIndex].claimed = true
    playerRewards[playerKey].rewards[rewardIndex].claimedAt = os.time()
    
    saveAllPlayerData()
    
    if Config.Qbox then
        TriggerClientEvent('rewards:receiveCode', source, code, reward.name, 0)
        notifyPlayer(source, 'Reward key created. Use /redeemreward to redeem it.', 'success')
        print(("^2[Rewards] Created reward key for %s: %s^7"):format(playerName, code))
        sendDiscordWebhook(playerName, playerKey, reward.name, code, nil, itemName, itemAmount, source)
    else
        notifyPlayer(source, 'Reward delivered successfully: ' .. reward.name, 'success')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 255, 0},
            multiline = true,
            args = {"Rewards", "Reward delivered successfully: " .. reward.name}
        })
        print(("^2[Rewards] Granted %s to %s: %s%s^7"):format(reward.name, playerName, itemName or 'code only', itemName and (" x" .. tostring(itemAmount)) or ''))
        sendDiscordWebhook(playerName, playerKey, reward.name, 'Standalone', nil, itemName, itemAmount, source)
    end
end)






local function redeemCode(source, code, screenshot)
    if Config.Standalone then
        TriggerClientEvent('rewards:redemptionResult', source, false, "Code redemption is disabled in standalone mode.")
        return
    end

    code = tostring(code or ''):upper()
    local steamId, discordId = getPlayerIdentifiers(source)
    local playerKey = createPlayerKey(source, steamId, discordId)

    local rows = exports.oxmysql:query_async([[
        SELECT code, player_key, reward_index, reward_name, item_name, item_amount, expires_at, used
        FROM btd_rewards_codes
        WHERE code = ?
        LIMIT 1
    ]], { code }) or {}

    local codeData = rows[1]
    if not codeData then
        notifyPlayer(source, 'Invalid or expired code.', 'error')
        return
    end

    if codeData.player_key ~= playerKey then
        notifyPlayer(source, "This code doesn't belong to you.", 'error')
        return
    end

    if os.time() > tonumber(codeData.expires_at) then
        notifyPlayer(source, 'This code has expired.', 'error')
        return
    end

    if tonumber(codeData.used) ~= 0 then
        notifyPlayer(source, 'This code has already been used.', 'error')
        return
    end

    local reserved = exports.oxmysql:update_async([[
        UPDATE btd_rewards_codes
        SET used = 2
        WHERE code = ? AND player_key = ? AND used = 0
    ]], { code, playerKey })
    if tonumber(reserved) ~= 1 then
        notifyPlayer(source, 'This code is already being redeemed or has been used.', 'error')
        return
    end

    local rewardIndex = tonumber(codeData.reward_index)
    if not rewardIndex or not Config.RewardTiers[rewardIndex] then
        exports.oxmysql:update_async('UPDATE btd_rewards_codes SET used = 0 WHERE code = ?', { code })
        notifyPlayer(source, 'This reward is no longer configured.', 'error')
        return
    end

    local itemGranted, itemName, itemAmount = giveRewardItem(source, rewardIndex)
    if not itemGranted then
        exports.oxmysql:update_async('UPDATE btd_rewards_codes SET used = 0 WHERE code = ?', { code })
        notifyPlayer(source, 'Your inventory cannot hold this reward. Make space and try again.', 'error')
        return
    end

    exports.oxmysql:update_async([[
        UPDATE btd_rewards_codes
        SET used = 1, redeemed_at = ?
        WHERE code = ? AND player_key = ?
    ]], { os.time(), code, playerKey })

    if playerRewards[playerKey] and playerRewards[playerKey].rewards[rewardIndex] then
        playerRewards[playerKey].rewards[rewardIndex].claimed = true
        playerRewards[playerKey].rewards[rewardIndex].claimedAt = os.time()
    end
    saveAllPlayerData()

    print(("^2[Rewards] Redeemed %s for %s: %s%s^7"):format(codeData.reward_name, GetPlayerName(source), itemName or 'code only', itemName and (" x" .. tostring(itemAmount)) or ''))
    sendDiscordWebhook(GetPlayerName(source), playerKey, codeData.reward_name, code, screenshot, itemName, itemAmount, source)
    notifyPlayer(source, 'Reward redeemed successfully.', 'success')
end

RegisterNetEvent('rewards:redeemCode')
AddEventHandler('rewards:redeemCode', function(code, screenshot)
    local source = source
    redeemCode(source, code, screenshot)
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(300000)
        saveAllPlayerData()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        saveAllPlayerData()
    end
end)

loadAllPlayerData()

RegisterCommand('resetdata', function(source)
    if hasAdminPermission(source, 'resetdata') then
        clearAllPlayerData()
        print(("^3[Rewards] Data reset by %s (ID %s).^7"):format(source == 0 and 'Console' or (GetPlayerName(source) or 'Unknown'), source))
        sendAuditWebhook('Reset all reward data', source, nil, { Records = 'All player records' })
        if source == 0 then return end
        notifyPlayer(source, 'All reward data has been reset.', 'success')
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Rewards", "All player data has been reset!"}
        })
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            multiline = true,
            args = {"Rewards", "You don't have permission to use this command!"}
        })
    end
end, false)

RegisterNetEvent('rewards:setPlaytime', function(target, minutes)
    local source = source
    if not hasAdminPermission(source, Config.PlaytimeCommand) then
        print(("^1[Rewards] Unauthorized playtime attempt by %s (ID %s).^7"):format(GetPlayerName(source) or 'Unknown', source))
        sendAuditWebhook('Denied playtime attempt', source, tonumber(target))
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"Rewards", "You don't have permission to use this command."}
        })
        return
    end

    target = tonumber(target)
    minutes = tonumber(minutes)

    if not target or target < 1 or target % 1 ~= 0 or not minutes or minutes < 0 or minutes % 1 ~= 0 or minutes > 1000000 then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 165, 0},
            args = {"Rewards", "Enter a valid player ID and whole number of minutes (0-1000000)."}
        })
        return
    end

    if not GetPlayerName(target) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {"Rewards", "That player is not online."}
        })
        return
    end

    local steamId, discordId = getPlayerIdentifiers(target)
    local playerKey = createPlayerKey(target, steamId, discordId)
    initializePlayer(target)

    local activeTime = minutes * 60
    playerRewards[playerKey].activeTime = activeTime
    playerRewards[playerKey].lastSeen = os.time()
    saveAllPlayerData()
    TriggerClientEvent('rewards:setActiveTime', target, activeTime)

    local message = ("Set %s's active playtime to %d minutes."):format(GetPlayerName(target), minutes)
    print("^2[Rewards] " .. message .. "^7")
    sendAuditWebhook('Set player playtime', source, target, {
        Minutes = minutes,
        ActiveTime = activeTime
    })
    if source ~= 0 then
        notifyPlayer(source, message, 'success')
        TriggerClientEvent('chat:addMessage', source, {
            color = {0, 255, 0},
            args = {"Rewards", message}
        })
    end
end)
























































































