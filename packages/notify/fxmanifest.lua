fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_notify'
author 'AETERNA'
description 'Toast notifications with actions, server-wide announcement and countdown banners, notification history, and message of the day (MOTD) for the AETERNA Starter Kit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'config.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/notify.lua',
    'shared/logic/actions.lua',
    'shared/logic/countdown.lua',
    'shared/logic/history.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'config/motd.json',
    'html/index.html',
    'html/theme.css',
    'html/fonts/*.woff2',
    'html/fonts/OFL.txt',
    'html/style.css',
    'html/icons.js',
    'html/app.js',
}
