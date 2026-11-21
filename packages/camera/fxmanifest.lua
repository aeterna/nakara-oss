fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_camera'
author 'AETERNA'
description 'Camera and Gallery apps for the AETERNA Starter Kit phone: photos saved on the server disk and served by this resource.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

-- screenshot-basic is optional and detected at run time; it is never a dependency.
dependencies {
    'aeterna_core',
    'aeterna_uikit',
    'aeterna_phonekit',
    'aeterna_notify',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'config.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/settings.lua',
    'shared/logic/ids.lua',
    'shared/logic/selftests.lua',
}

client_scripts {
    'client/viewfinder.lua',
    'client/main.lua',
}

server_scripts {
    'shared/logic/codec.lua',
    'shared/logic/tickets.lua',
    'shared/logic/store.lua',
    'shared/logic/service.lua',
    'shared/logic/router.lua',
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
