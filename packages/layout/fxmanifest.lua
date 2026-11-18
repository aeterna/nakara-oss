fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_layout'
author 'AETERNA'
description 'Coordinate-based HUD layout editor and client persistence for the AETERNA Starter Kit.'
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
    'shared/logic/layout.lua',
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
    'html/fonts/*.woff2',
    'html/fonts/OFL.txt',
    'html/style.css',
    'html/icons.js',
    'html/app.js',
}
