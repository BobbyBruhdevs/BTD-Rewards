Config = {}

Config.OpenCommand = 'rewards'
Config.DefaultKey = 'F6'
Config.PlaytimeCommand = 'setplaytime'
Config.CodePrefix = 'BTD'
Config.CodeLength = 12
Config.CodeExpiry = 86400

Config.ActivityCheckInterval = 1
Config.SaveInterval = 60
Config.AFKTimeout = 300
Config.MovementThreshold = 0.15

-- Enable exactly one framework mode. Only Qbox mode uses ox_inventory item rewards.
Config.Qbox = true
Config.Standalone = false

-- Main UI color. Use a CSS color name (red, blue, green, cyan) or a hex value.
Config.UIColor = 'cyan'

Config.RewardTiers = {
    -- Standalone mode should use item = false because it has no inventory provider.
    { name = 'Civ Car Pack 1', time = 100, description = 'Basic civilian vehicle pack', item = false },
    { name = 'Civ Car Pack 2', time = 450, description = 'Advanced civilian vehicle pack', item = false },
    { name = 'Cash', time = 700, description = 'Cash reward', item = 'money', amount = 1000 },
}
