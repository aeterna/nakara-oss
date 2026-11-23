fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_phonekit'
author 'AETERNA'
description 'Phone shell with built-in calculator, notes, contacts, settings, and an app API for other resources.'
version '0.2.0'
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
    'shared/logic/device.lua',
    'shared/logic/battery.lua',
    'shared/logic/exitkeys.lua',
    'shared/logic/shell.lua',
    'shared/logic/hooks.lua',
    'shared/logic/selftest.lua',
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
    'html/fonts/*.woff2',
    'html/fonts/OFL.txt',
    'html/style.css',
    'html/icons.js',
    'html/devicelayout.js',
    'html/app.js',
}
