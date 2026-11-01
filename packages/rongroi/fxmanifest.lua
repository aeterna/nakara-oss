fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nakara_rongroi'
author 'Nakara City dev team'
description 'Rongroi Server Kit (lane 2b, part 1): envelope crypto and a start-up self-test against the shared test vectors. No HTTP surface yet.'
version '0.0.0'
repository 'https://github.com/aeterna/nakara-oss'

-- Server-only. The self-test runs once when the resource starts and prints one line.
server_scripts {
    'server/js/envelope.js',
    'server/js/selftest.js',
}
