-- config.lua -- configuration for aeterna_hudkit.

Config = Config or {}

-- Milliseconds between reads of player and vehicle values.
-- NUI receives a message only when a value actually changes.
Config.tick = 200

-- A bar at or below this percentage turns to the --bad colour.
Config.low = 20

-- Player state bag keys to read as 0-100 need bars (e.g. qbx_core / custom frameworks).
Config.needs = { 'hunger', 'thirst', 'stress' }

-- Default speed unit for players who have not selected one in settings ('kmh' or 'mph').
Config.speedUnit = 'kmh'

-- Minimap display settings.
Config.minimap = {
    -- Default mode: 'always', 'vehicle' (shown only in a vehicle), or 'never'.
    mode = 'always',
}

-- Hides the base game health and armour bars under the minimap via scaleform SETUP_HEALTH_ARMOUR.
Config.hideBaseBars = true
