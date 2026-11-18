fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_phonekit'
author 'AETERNA'
description 'Phone shell with built-in calculator, notes, contacts, settings, and an app API for other resources.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
    'aeterna_uikit',
    'aeterna_notify',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'config.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/calc.lua',
    'shared/logic/phone.lua',
}

client_scripts {
    'client/anim.lua',
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
