fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nakara_rongroi'
author 'Nakara City dev team'
description 'Rongroi Server Kit (lane 2b, part 2): answers policy reads and report uploads over HTTP.'
version '0.0.0'
repository 'https://github.com/aeterna/nakara-oss'

-- main.js wires the HTTP handler and the panel, and loads every other module with require().
client_scripts {
    'client/main.lua',
}

ui_page 'web/ui/index.html'

files {
    'web/ui/**',
}

server_scripts {
    'server/js/selftest.js',
    'server/js/main.js',
}
