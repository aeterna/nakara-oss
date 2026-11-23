fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeterna_core'
author 'AETERNA'
description 'Shared foundation for the AETERNA Starter Kit: logging, event bus, Thai-aware text, locales, time, schema validation, rate limiting, ACE checks, versioned KVP, key mappings, NUI focus lock, theme path and self-tests.'
version '0.1.0'
repository 'https://github.com/aeterna/nakara-oss'

shared_scripts {
    'locales/en.lua',
    'locales/th.lua',
    'shared/logic/text.lua',
    'shared/logic/validate.lua',
    'shared/logic/ratelimit.lua',
    'shared/logic/time.lua',
    'shared/logic/locale.lua',
    'shared/logic/focus.lua',
    'shared/logic/selftest.lua',
    'shared/logic/kvp.lua',
    'import.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'import.lua',
}
