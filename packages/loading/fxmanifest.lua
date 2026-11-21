fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_loading'
author 'AETERNA'
description 'Loading screen that shows the real loading stages (map, scripts, character) for the AETERNA Starter Kit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

loadscreen 'html/index.html'
loadscreen_manual_shutdown 'yes'
loadscreen_cursor 'yes'

shared_script 'shared/logic/loading.lua'

client_script 'client/main.lua'

server_scripts {
    'locales/en.lua',
    'locales/th.lua',
    'server/main.lua',
}

files {
    'html/**',
}
