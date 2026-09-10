<div align="center">

# BTD Rewards

**A configurable playtime reward system for FiveM servers.**

Reward active players with items, money, reward keys, and custom server-side actions through a clean and responsive interface.

[Discord Support](https://discord.gg/myGSA5tJks)

</div>

![BTD Rewards Interface](images/rewards-ui.png)

## About

BTD Rewards tracks each player's active playtime and allows them to unlock configurable rewards. It supports both Qbox and standalone servers, with persistent data storage, administrative tools, and server-side protections.

## Features

### Reward System

* Configurable playtime reward tiers
* One-time reward claiming
* Money and custom item rewards
* Custom code-based rewards
* Qbox reward keys
* Configurable reward-key expiration
* Player-locked reward keys

### Framework Support

* Qbox support
* Standalone support
* `ox_inventory` integration
* `ox_lib` dialogs and utilities
* Persistent storage through `oxmysql`

### Administration

* `/setplaytime` admin command
* `/resetdata` administrative command
* ACE permission support
* Qbox group permission support
* Discord webhook audit logs

### Interface

* Clean and responsive NUI
* Configurable interface colors
* Font Awesome icons
* Live playtime and reward progress
* Available and claimed reward states

### Security

* Server-side reward validation
* Duplicate-claim protection
* Inventory failure protection
* Expired key validation
* Player ownership verification
* Administrative action logging

## Requirements

* [ox_lib](https://github.com/overextended/ox_lib)
* [oxmysql](https://github.com/overextended/oxmysql)
* [ox_inventory](https://github.com/overextended/ox_inventory)
* `qbx_core` when using Qbox mode

## Installation

1. Download or clone the repository.
2. Place `btd_rewards` inside your server's `resources` directory.
3. Import `btd_rewards.sql` into your database.
4. Configure the shared settings inside `config.lua`.
5. Configure the protected server settings inside `server_config.lua`.
6. Add the resource to your `server.cfg`.
7. Restart the server.

### Resource Order

Add the following lines to your `server.cfg`:

```cfg
ensure ox_lib
ensure oxmysql
ensure ox_inventory
ensure btd_rewards
```

When using Qbox, ensure `qbx_core` starts before BTD Rewards:

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core
ensure ox_inventory
ensure btd_rewards
```

## Configuration

### Framework Mode

Enable Qbox mode:

```lua
Config.Qbox = true
Config.Standalone = false
```

Enable standalone mode:

```lua
Config.Qbox = false
Config.Standalone = true
```

> Only one framework mode should be enabled at a time.

### Interface Color

```lua
Config.UIColor = 'cyan'
```

### Item Reward Example

```lua
{
    name = 'Cash',
    time = 700,
    description = 'Receive a cash reward.',
    item = 'money',
    amount = 1000
}
```

| Property      | Description                                      |
| ------------- | ------------------------------------------------ |
| `name`        | Display name shown in the reward interface       |
| `time`        | Required playtime before the reward is available |
| `description` | Description displayed beneath the reward         |
| `item`        | Registered `ox_inventory` item name              |
| `amount`      | Number of items given to the player              |

Set `item` to `false` when the reward is handled through custom server-side code instead of `ox_inventory`.

## Commands

| Command         | Description                                      | Permission |
| --------------- | ------------------------------------------------ | ---------- |
| `/redeemreward` | Opens an input dialog for redeeming a reward key | Player     |
| `/setplaytime`  | Changes a player's recorded playtime             | Admin      |
| `/resetdata`    | Resets a player's reward data                    | Admin      |

## Discord Logging

BTD Rewards can send webhook logs for:

* Successful reward claims
* Reward-key redemptions
* Playtime changes
* Player-data resets
* Failed or rejected reward attempts
* Other administrative actions

Configure your webhook settings inside `server_config.lua`.

> Do not place private webhook URLs or other sensitive settings inside client-accessible files.

## Support

Need help, found a bug, or have a suggestion?

[Join the BTD Development Discord](https://discord.gg/myGSA5tJks)

When reporting an issue, please include:

* A clear description of the problem
* Steps to reproduce it
* Relevant client or server console errors
* Your selected framework mode
* Versions of the required dependencies

## Important

Always review and configure `config.lua` and `server_config.lua` before starting the resource. Make sure every configured reward item exists inside `ox_inventory`.
