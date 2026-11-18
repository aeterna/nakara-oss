fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_invkit'
author 'AETERNA'
description 'Personal stashes and item-use progress registry around ox_inventory for the AETERNA Starter Kit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
    'aeterna_uikit',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'locales/en.lua',
    'locales/th.lua',
    'config.lua',
    'shared/logic/invkit.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/ox_adapter.lua',
    'server/main.lua',
}
