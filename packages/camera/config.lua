-- aeterna_camera configuration. Values are checked at start; a bad value falls back to its default with one warn.
Config = {}

Config.perCharacter = 60    -- photos per character, 1-500; at the cap the shutter refuses (camera.full)
Config.maxBytes = 900000    -- largest accepted photo after decoding, 100000-3000000 bytes
Config.maxTotalMB = 1024    -- all photos together; at the cap every shutter refuses (camera.disk_full)
Config.quality = 0.8        -- JPEG quality passed to screenshot-basic, 0.5-0.95
Config.cooldownMs = 3000    -- minimum time between two shots of one player
