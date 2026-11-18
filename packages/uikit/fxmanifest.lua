fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_uikit'
author 'AETERNA'
description 'Server-owned UI panels, client prompts (confirm, input, progress, skill check, key hints), and shared menu for the AETERNA Starter Kit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/uikit.lua',
}

client_scripts {
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
