fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_radial'
author 'AETERNA'
description 'Radial action menu with nested rings, condition filters, and keyboard/gamepad navigation for the AETERNA Starter Kit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
    'aeterna_uikit',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'config.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/radial.lua',
}

client_scripts {
    'client/input.lua',
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/theme.css',
    'html/style.css',
    'html/icons.js',
    'html/app.js',
}
