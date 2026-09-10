local activeTime = 0
local uiOpen = false
local openOnReceive = false
local lastPosition = nil
local lastActivityAt = GetGameTimer()

local activityControls = {
    1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 44, 71, 72, 75, 76
}

local function setUiFocus(enabled)
    uiOpen = enabled
    SetNuiFocus(enabled, enabled)
    SetNuiFocusKeepInput(false)
end

local function requestStats(openUi)
    if openUi then openOnReceive = true end
    TriggerServerEvent('rewards:requestStats')
end

local function hasPlayerActivity(ped)
    local position = GetEntityCoords(ped)
    local moved = false

    if lastPosition then
        moved = #(position - lastPosition) >= Config.MovementThreshold
    end
    lastPosition = position

    if moved or GetEntitySpeed(ped) > Config.MovementThreshold then
        return true
    end

    for i = 1, #activityControls do
        if IsControlPressed(0, activityControls[i]) then
            return true
        end
    end

    return false
end

RegisterCommand(Config.OpenCommand, function()
    requestStats(true)
end, false)

RegisterKeyMapping(Config.OpenCommand, 'Open BTD Rewards', 'keyboard', Config.DefaultKey)

if not Config.Standalone then
    RegisterCommand('redeemreward', function()
        local input = lib.inputDialog('Redeem reward', {
            { type = 'input', label = 'Reward key', description = 'Paste the key you received', required = true, min = 5, max = 64 }
        })

        if input and input[1] then
            TriggerServerEvent('rewards:redeemCode', input[1])
        end
    end, false)
end

RegisterCommand(Config.PlaytimeCommand, function()
    local input = lib.inputDialog('Set playtime', {
        { type = 'number', label = 'Player ID', description = 'Server ID of the player', required = true, min = 1, precision = 0 },
        { type = 'number', label = 'Minutes', description = 'New active playtime in minutes', required = true, min = 0, precision = 0 }
    })

    if input and input[1] and input[2] then
        TriggerServerEvent('rewards:setPlaytime', input[1], input[2])
    end
end, false)

RegisterNetEvent('rewards:receiveStats', function(stats)
    if type(stats) ~= 'table' then return end

    activeTime = tonumber(stats.activeTime) or activeTime
    if openOnReceive or uiOpen then
        SendNUIMessage({
            action = 'open',
            data = {
                activeTime = activeTime,
                rewards = stats.rewards or {},
                uiColor = Config.UIColor
            }
        })
        setUiFocus(true)
    end
    openOnReceive = false
end)

RegisterNetEvent('rewards:receiveCode', function(code, rewardName)
    SendNUIMessage({
        action = 'showCode',
        data = {
            code = tostring(code or ''),
            rewardName = tostring(rewardName or ''),
            uiColor = Config.UIColor
        }
    })
    setUiFocus(true)
end)

RegisterNetEvent('rewards:redemptionResult', function(success, message)
    lib.notify({
        title = 'BTD Rewards',
        description = tostring(message or ''),
        type = success == true and 'success' or 'error'
    })
    SendNUIMessage({
        action = 'redemptionResult',
        data = {
            success = success == true,
            message = tostring(message or '')
        }
    })
end)

RegisterNetEvent('rewards:setActiveTime', function(time)
    activeTime = math.max(0, tonumber(time) or activeTime)
    if uiOpen then requestStats(false) end
end)

RegisterNUICallback('close', function(_, cb)
    setUiFocus(false)
    SendNUIMessage({ action = 'close' })
    cb({ ok = true })
end)

RegisterNUICallback('requestStats', function(_, cb)
    requestStats(false)
    cb({ ok = true })
end)

RegisterNUICallback('claimReward', function(data, cb)
    local rewardIndex = tonumber(data and data.index)
    if rewardIndex and rewardIndex >= 1 and rewardIndex % 1 == 0 then
        TriggerServerEvent('rewards:claimReward', rewardIndex)
        cb({ ok = true })
        return
    end

    cb({ ok = false, error = 'Invalid reward index' })
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    requestStats(false)

    while true do
        Wait(math.max(1, Config.ActivityCheckInterval) * 1000)

        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsPauseMenuActive() then
            if hasPlayerActivity(ped) then
                lastActivityAt = GetGameTimer()
            end

            if GetGameTimer() - lastActivityAt <= Config.AFKTimeout * 1000 then
                activeTime = activeTime + math.max(1, Config.ActivityCheckInterval)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(10, Config.SaveInterval) * 1000)
        TriggerServerEvent('rewards:updateActiveTime', activeTime)
    end
end)

AddEventHandler('playerSpawned', function()
    lastPosition = GetEntityCoords(PlayerPedId())
    lastActivityAt = GetGameTimer()
    requestStats()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        setUiFocus(false)
    end
end)
