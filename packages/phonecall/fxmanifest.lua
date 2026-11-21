fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_phonecall'
author 'AETERNA'
description 'Phone numbers, text messages and voice calls as Phone and Messages apps inside aeterna_phonekit.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

dependencies {
    'aeterna_core',
    'aeterna_uikit',
    'aeterna_phonekit',
}

shared_scripts {
    '@aeterna_core/import.lua',
    'config.lua',
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/number.lua',
    'shared/logic/config.lua',
    'shared/logic/store.lua',
    'shared/logic/limits.lua',
    'shared/logic/names.lua',
    'shared/logic/calls.lua',
    'shared/logic/voice.lua',
    'shared/logic/selftest.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
