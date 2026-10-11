fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nakara_cargen_fix'
author 'Nakara City dev team'
description 'Guards against "CNetworkCarGenWorldStateData Pool Full, Size == 100" by disabling vehicle generators locally (never networked). Client-only.'
version '1.0.0'
repository 'https://github.com/aeterna/nakara-oss'

-- Client-only. There is deliberately no gameconfig data_file here: `data_file 'GAMECONFIG_FILE'` is not
-- a valid data-file type and is ignored by FiveM (see README.md).
client_scripts {
    'config.lua',
    'client/logic.lua',
    'client/main.lua',
}
