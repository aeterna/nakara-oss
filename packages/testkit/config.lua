-- aeterna_testkit configuration. Every key has a row in README.md "Config".
Config = Config or {}

-- Seconds an invite to player B waits for an answer (10-120).
Config.inviteSeconds = 30

-- Adds an entry to the aeterna_uikit menu (ACE aeterna.testkit.run) besides the key mapping.
Config.menuEntry = true

-- What a menu run prints to the server console when it ends: 'md' · 'json' · 'none'.
Config.printReport = 'md'

return Config
