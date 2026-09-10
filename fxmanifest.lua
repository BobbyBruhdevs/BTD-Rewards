fx_version 'cerulean'
game 'gta5'

dependencies {
    'ox_lib',
    'oxmysql'
}

author 'Bobby the daddy'
description 'Activity-based rewards system with anti-AFK and redemption codes'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server_config.lua',
    'server.lua'
}

files {
    'html/index.html',
    'html/theme.css',
    'html/dist/app.js',
    'html/dist/config.js',
    'btd_rewards.sql'
}
