-- nakara_cargen_fix configuration. The defaults are the values the resource shipped with.
Config = {}

-- Box (x1, y1, z1, x2, y2, z2) in which vehicle generators are disabled. The default covers the whole
-- GTA V map (roughly +/-8000 on X/Y, -1000..2000 on Z) with a wide margin. Invalid values fall back to
-- the default.
Config.Area = { -20000.0, -20000.0, -2000.0, 20000.0, 20000.0, 5000.0 }

-- How often (ms) the disable is re-applied. The engine re-enables generators on zone changes and
-- respawns, so it has to be re-asserted. Because the call is local-only it does not consume any pool
-- slot, so the interval is not what causes "Pool Full". Values below 1000 fall back to the default.
Config.ReassertMs = 5000
