fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_invkit'
author 'AETERNA'
description 'Personal stashes and item-use progress registry around ox_inventory for the AETERNA Starter Kit.'
version '0.2.0'
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
    'shared/logic/phone.lua',
    'shared/logic/selftest.lua',
}

client_scripts {
    'client/main.lua',
    'client/selftest.lua',
}

server_scripts {
    'server/ox_adapter.lua',
    'server/main.lua',
    'server/phone.lua',
    'server/selftest.lua',
}
