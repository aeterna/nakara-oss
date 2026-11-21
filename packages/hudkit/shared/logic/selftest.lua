-- shared/logic/selftest.lua -- natives-free rules of the aeterna_hudkit 0.2 self-tests
-- (docs/specs/aeterna_hudkit.md § Self-tests (0.2)). Each judge returns state, detail, extra for
-- exports.aeterna_core:reportSelftest; the wrappers in server/selftest.lua and client/selftest.lua stay thin.

HudSelftest = HudSelftest or {}

local PREFIX = 'aeterna_hudkit.'

-- The voice rows wait this long for the presser to act, then report what they saw before core's timeout.
HudSelftest.VOICE_WATCH_MS = 25000
-- seatbelt_event waits this long for the presser to sit in a vehicle before it skips.
HudSelftest.SEATBELT_WAIT_MS = 20000

local ROWS = {
    { name = 'values_mapping', kind = 'headless' },
    { name = 'compass_math', kind = 'headless' },
    { name = 'bar_style', kind = 'eye', expect = true },
    { name = 'compass_tape', kind = 'ped', expect = true, timeout = 10000 },
    { name = 'voice_indicator', kind = 'ped', expect = true, timeout = 30000, needsVoice = true },
    { name = 'voice_radio', kind = 'ped', expect = true, timeout = 30000, needsVoice = true },
    { name = 'seatbelt_event', kind = 'mock', side = 'client', expect = true, timeout = 30000 },
    { name = 'minimap_follows', kind = 'ped', expect = true },
}

local KNOWN = {}
for _, row in ipairs(ROWS) do KNOWN[row.name] = true end

--- The spec rows in spec order: { { name, meta }, … }. `t(key)` translates the expect strings.
function HudSelftest.definitions(t)
    t = t or function(key) return key end
    local out = {}
    for i, row in ipairs(ROWS) do
        local meta = { kind = row.kind, players = 1, destructive = false }
        if row.side then meta.side = row.side end
        if row.expect then meta.expect = t('hudkit.selftest.' .. row.name .. '.expect') end
        if row.timeout then meta.timeout = row.timeout end
        if row.needsVoice then meta.skipWhen = { resources = { 'pma-voice' } } end
        out[i] = { name = row.name, meta = meta }
    end
    return out
end

--- 'aeterna_hudkit.<name>' -> '<name>' for this package's own rows, else nil.
function HudSelftest.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #PREFIX) ~= PREFIX then return nil end
    local short = fullName:sub(#PREFIX + 1)
    return KNOWN[short] and short or nil
end

--- The only reasons a row may report SKIP (the spec's "Skip when" column). env.voiceStarted = pma-voice started.
function HudSelftest.skipReason(name, cfg, env)
    cfg = type(cfg) == 'table' and cfg or {}
    env = type(env) == 'table' and env or {}
    local function off(key)
        return type(cfg[key]) == 'table' and cfg[key].enabled == false
    end
    if name == 'compass_tape' and off('compass') then
        return 'Config.compass.enabled = false'
    elseif name == 'voice_indicator' or name == 'voice_radio' then
        if env.voiceStarted == false then return 'needs pma-voice' end
        if off('voice') then return 'Config.voice.enabled = false' end
    elseif name == 'seatbelt_event' and off('seatbelt') then
        return 'Config.seatbelt.enabled = false'
    end
    return nil
end

-- Runs { label, got, want } checks in order; the first mismatch fails with its label.
local function firstMismatch(checks)
    for _, c in ipairs(checks) do
        if c[2] ~= c[3] then
            return ('%s = %s, expected %s'):format(c[1], tostring(c[2]), tostring(c[3]))
        end
    end
    return nil
end

local function near(a, b, eps)
    return type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= (eps or 1e-6)
end

--- values_mapping: health, speed, gear and heading mapping, and change detection, on known values.
function HudSelftest.valuesMapping(H)
    local changed = H.diffValues({ status = { health = 50 } }, { status = { health = 50 } })
    local bad = firstMismatch({
        { 'mapHealth(100)', H.mapHealth(100), 0 },
        { 'mapHealth(150)', H.mapHealth(150), 50 },
        { 'mapHealth(200)', H.mapHealth(200), 100 },
        { 'mapHealth(250)', H.mapHealth(250), 100 },
        { 'mapHealth(90)', H.mapHealth(90), 0 },
        { 'speedToKmh(10)', H.speedToKmh(10), 36 },
        { 'speedToMph(10)', H.speedToMph(10), 22 },
        { 'gearText(0)', H.gearText(0, false), 'N' },
        { 'gearText(3)', H.gearText(3, false), '3' },
        { 'gearText(-1)', H.gearText(-1, false), 'R' },
        { 'gearText(2, reverse)', H.gearText(2, true), 'R' },
        { 'headingSector(359)', (H.headingSector(359)), 'N' },
        { 'headingSector(90)', (H.headingSector(90)), 'E' },
        { 'headingSector(225)', (H.headingSector(225)), 'SW' },
        { 'diffValues(same)', changed, false },
    })
    if bad then return 'fail', bad end
    return 'pass', 'health, speed, gear, heading and change detection map as specified'
end

--- compass_math: tape offset with the wrap, normalising, span clamp and labels.
function HudSelftest.compassMath(C)
    local ticks = C.visibleTicks(0, 120)
    local northTick = nil
    for _, tick in ipairs(ticks) do
        if tick.deg == 0 then northTick = tick end
    end
    local bad = firstMismatch({
        { 'offset(0, 0)', near(C.offset(0, 0, 120), 0), true },
        { 'offset(0, 359)', near(C.offset(0, 359, 120), 1 / 120), true },
        { 'offset(350, 10)', near(C.offset(350, 10, 120), -20 / 120), true },
        { 'offset(10, 350)', near(C.offset(10, 350, 120), 20 / 120), true },
        { 'normalize(360)', C.normalize(360), 0 },
        { 'normalize(-90)', C.normalize(-90), 270 },
        { 'fromCamRot(90)', C.fromCamRot(90), 270 },
        { 'clampSpan(30)', C.clampSpan(30), 60 },
        { 'clampSpan(200)', C.clampSpan(200), 180 },
        { 'clampSpan(nil)', C.clampSpan(nil), 120 },
        { 'label(45)', C.label(45), 'NE' },
        { 'label(10)', C.label(10), nil },
        { 'visibleTicks(0) N on the centre', northTick ~= nil and near(northTick.offset, 0), true },
    })
    if bad then return 'fail', bad end
    return 'pass', 'offsets, wrap, span clamp and labels are right'
end

--- Camera headings (GetGameplayCamRot z) for one full turn, starting and ending facing north.
function HudSelftest.compassHeadings()
    local list = {}
    for z = 0, 360, 30 do list[#list + 1] = z end
    return list
end

local function angleGap(a, b)
    return math.abs(((a - b) + 540) % 360 - 180)
end

--- compass_tape: samples = { { camZ, sent } } where `sent` is the degree hudkit last sent to its page.
--- Every sample must follow the camera within 2 degrees, and facing north must put N on the centre mark.
function HudSelftest.compassSamples(C, samples, span)
    local north = false
    for i, s in ipairs(samples or {}) do
        local want = C.fromCamRot(s.camZ)
        if type(s.sent) ~= 'number' then
            return 'fail', ('step %d: the tape got no heading (is the compass hidden?)'):format(i),
                { step = i, expected = ('heading %d'):format(want) }
        end
        if angleGap(s.sent, want) > 2 then
            return 'fail', ('step %d: the tape shows %d, the camera faces %d'):format(i, s.sent, want),
                { step = i, expected = ('heading %d'):format(want) }
        end
        if angleGap(want, 0) <= 2 then
            if math.abs(C.offset(0, s.sent, span) * C.clampSpan(span)) > 2 then
                return 'fail', ('step %d: facing north, N is off the centre mark'):format(i),
                    { step = i, expected = 'N at the centre mark' }
            end
            north = true
        end
    end
    if not north then
        return 'fail', 'no sample faced north', { expected = 'a sample facing north' }
    end
    return 'pass', ('the tape followed the camera through %d headings'):format(#samples)
end

--- voice_indicator / voice_radio: feed every hud:voice message hudkit sent; observe() returns true once the
--- row has seen what it needs. verdict() gives the result.
function HudSelftest.newVoiceWatch(name)
    local seen = { available = false, talking = false, modes = {}, modeCount = 0, radio = false, radioActive = false }
    local w = {}

    local function done()
        if not seen.available then return false end
        if name == 'voice_radio' then return seen.radio and seen.radioActive end
        return seen.talking and seen.modeCount >= 2
    end

    function w.observe(msg)
        if type(msg) == 'table' and msg.available == true then
            seen.available = true
            if msg.talking == true then seen.talking = true end
            if type(msg.mode) == 'string' and msg.mode ~= '' and not seen.modes[msg.mode] then
                seen.modes[msg.mode] = true
                seen.modeCount = seen.modeCount + 1
            end
            if msg.radio == true then seen.radio = true end
            if msg.radio == true and msg.radioActive == true then seen.radioActive = true end
        end
        return done()
    end

    function w.verdict()
        if not seen.available then
            return 'fail', 'the voice indicator was not shown while pma-voice is started'
        end
        if done() then
            if name == 'voice_radio' then return 'pass', 'radio icon showed and lit while transmitting' end
            return 'pass', ('microphone lit while talking; %d mode labels seen'):format(seen.modeCount)
        end
        local missing = {}
        if name == 'voice_radio' then
            if not seen.radio then missing[#missing + 1] = 'no radio channel joined' end
            if not seen.radioActive then missing[#missing + 1] = 'no transmit seen' end
        else
            if not seen.talking then missing[#missing + 1] = 'no talking seen' end
            if seen.modeCount < 2 then missing[#missing + 1] = 'mode label did not change' end
        end
        return 'fail', table.concat(missing, '; ')
    end

    return w
end

--- seatbelt_event: the payloads fired, in order, and the icon state each must leave in a vehicle.
function HudSelftest.seatbeltSteps()
    return {
        { payload = { on = true }, expect = true },
        { payload = { on = false }, expect = false },
        { payload = nil, expect = nil },
    }
end

--- observed[i] = icon state hudkit's own handler sent after step i; restored = the state before the test is
--- back; inVehicle = false: the presser never sat in a vehicle within SEATBELT_WAIT_MS, so nothing was fired.
function HudSelftest.seatbeltVerdict(observed, restored, inVehicle)
    if inVehicle == false then
        return 'skip', 'presser is not in a vehicle'
    end
    local extra = { restored = restored == true }
    for i, step in ipairs(HudSelftest.seatbeltSteps()) do
        local got = observed and observed[i]
        if got ~= step.expect then
            extra.step = i
            extra.expected = tostring(step.expect)
            return 'fail', ('step %d: icon state %s, expected %s'):format(i, tostring(got), tostring(step.expect)), extra
        end
    end
    if not extra.restored then
        return 'fail', 'seatbelt state was not put back', extra
    end
    return 'mock', 'true, false and nil each set the icon; the previous state is back', extra
end

--- minimap_follows: the top-right place, then the place the radar had before the test.
function HudSelftest.minimapPlaces(original)
    return {
        { x = 0.98, y = 0.02, ax = 1.0, ay = 0.0, scale = 1.0 },
        original,
    }
end

--- `applied` = positions hudkit last sent to SetMinimapComponentPosition. The radar's bottom-left corner must
--- be the stand-in's bottom-left corner for `place`, its size the default size times the scale, and the
--- mask and blur must keep their offsets from the radar.
function HudSelftest.minimapCheck(M, metrics, place, applied)
    if type(applied) ~= 'table' or type(applied.minimap) ~= 'table' then
        return 'fail', 'no radar position was applied'
    end
    local scale = M.clampScale(place.scale)
    local leftPx = place.x * metrics.screenW - place.ax * metrics.pxW * scale
    local bottomPx = place.y * metrics.screenH - place.ay * metrics.pxH * scale + metrics.pxH * scale
    local sx, sy = M.offsetToScreen(applied.minimap.x, applied.minimap.y, metrics.p0, metrics.p1)
    local wantX, wantY = leftPx / metrics.screenW, bottomPx / metrics.screenH
    if math.abs(sx - wantX) > 0.001 or math.abs(sy - wantY) > 0.001 then
        return 'fail', ('radar corner at %.3f, %.3f; stand-in corner at %.3f, %.3f'):format(sx, sy, wantX, wantY)
    end
    local defs = M.DEFAULT_COMPONENTS
    for name, def in pairs(defs) do
        local pos = applied[name]
        if type(pos) ~= 'table' then
            return 'fail', name .. ' was not moved'
        end
        local relX = (def.x - defs.minimap.x) * scale
        local relY = (def.y - defs.minimap.y) * scale
        if math.abs((pos.x - applied.minimap.x) - relX) > 1e-4 or math.abs((pos.y - applied.minimap.y) - relY) > 1e-4
            or math.abs(pos.w - def.w * scale) > 1e-4 or math.abs(pos.h - def.h * scale) > 1e-4 then
            return 'fail', name .. ' no longer lines up with the radar'
        end
    end
    return 'pass', 'the radar sits under its stand-in'
end

return HudSelftest
