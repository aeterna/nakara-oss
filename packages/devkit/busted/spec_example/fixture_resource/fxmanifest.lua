-- Fixture resource used by spec_example/harness_spec.lua. Not a real resource.
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fixture_counter'
description 'Counts pings per player and reports them -- exercises the busted harness'
version '0.0.1'

--[[ block comment with a fake entry that must be ignored:
client_script 'client/ignored.lua'
]]
shared_scripts {
    'shared/config.lua',
    'shared/logic.lua',
}
server_script 'server/main.lua'
client_script 'client/main.lua' -- line comment
