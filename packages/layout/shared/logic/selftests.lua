-- Pure self-test logic for aeterna_layout 0.2 (docs/specs/aeterna_layout.md § Self-tests (0.2)): the rows registered
-- with aeterna_core, the two server checks, the test elements and the pass rules of the client tests.
-- Natives-free; loads after shared/logic/layout.lua and share.lua.

LayoutSelftests = {}
local M = LayoutSelftests

M.PREFIX = 'aeterna_layout.'

-- Exactly the spec table. `expect` = the row has an Expect text (locale key layout.selftest.<name>); `timeout` in ms
-- where the default of 5000 is too short for the page drives.
M.ROWS = {
    { name = 'placement_math', kind = 'headless' },
    { name = 'import_validate', kind = 'headless' },
    { name = 'clamp_on_grow', kind = 'mock', side = 'client' },
    { name = 'preset_apply', kind = 'eye', expect = true },
    { name = 'grid_drag', kind = 'ped', expect = true, timeout = 10000 },
    { name = 'export_import', kind = 'ped', expect = true },
    { name = 'export_copy', kind = 'ped', expect = true, timeout = 10000 },
    { name = 'reset_from_menu', kind = 'ped', destructive = true, expect = true },
}

local BY_NAME = {}
for i = 1, #M.ROWS do
    BY_NAME[M.ROWS[i].name] = M.ROWS[i]
end

local EPS = 1e-6

function M.register(add, t)
    local count = 0
    for i = 1, #M.ROWS do
        local row = M.ROWS[i]
        local meta = { kind = row.kind }
        if row.side then
            meta.side = row.side
        end
        if row.destructive then
            meta.destructive = true
        end
        if row.expect then
            meta.expect = t('layout.selftest.' .. row.name)
        end
        if row.timeout then
            meta.timeout = row.timeout
        end
        if add(M.PREFIX .. row.name, meta) ~= nil then
            count = count + 1
        end
    end
    return count
end

function M.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #M.PREFIX) ~= M.PREFIX then
        return nil
    end
    local short = fullName:sub(#M.PREFIX + 1)
    return BY_NAME[short] and short or nil
end

-- Top-left corner of a place's box in px.
function M.leftTop(place, w, h, sw, sh)
    local s = place.scale or 1
    return place.x * sw - place.ax * w * s, place.y * sh - place.ay * h * s
end

function M.boxOnScreen(place, w, h, sw, sh)
    local s = place.scale or 1
    local left, top = M.leftTop(place, w, h, sw, sh)
    if left < -EPS or top < -EPS or left + w * s > sw + EPS or top + h * s > sh + EPS then
        return false, ('box at %d,%d size %dx%d is off a %dx%d screen'):format(
            math.floor(left), math.floor(top), math.floor(w * s), math.floor(h * s), sw, sh)
    end
    return true, 'box on screen'
end

-- A test element whose box starts at the left anchor and ends flush with the right edge of a `sw` wide screen.
function M.growDef(w, sw, label)
    return { id = 'st_grow', label = label, w = w, h = 60, x = (sw - w) / sw, y = 0.5, ax = 0, ay = 0.5 }
end

-- A test element in the middle of the screen.
function M.centerDef(id, label)
    return { id = id, label = label, w = 200, h = 60, x = 0.5, y = 0.5, ax = 0.5, ay = 0.5 }
end

-- The step grid_drag drags on: the player's pick, or the first offered step when snap is off.
function M.gridStep(playerStep, steps)
    if type(playerStep) == 'number' and playerStep > 0 then
        return playerStep
    end
    return type(steps) == 'table' and steps[1] or 8
end

local function runChecks(checks)
    for i = 1, #checks do
        local why = checks[i].fn()
        if why then
            return false, checks[i].label .. ': ' .. why
        end
    end
    return true, #checks .. ' cases held'
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function placeOf(def)
    return { x = def.x, y = def.y, ax = def.ax, ay = def.ay, scale = 1, hidden = false }
end

local function placesEqual(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for _, f in ipairs({ 'x', 'y', 'ax', 'ay', 'scale' }) do
        if type(a[f]) ~= 'number' or type(b[f]) ~= 'number' or math.abs(a[f] - b[f]) > 1e-9 then
            return false
        end
    end
    return (a.hidden == true) == (b.hidden == true)
end

-- placement_math: the clamp on size, scale and resolution changes, and that it never touches the saved place.
local function placementMath(L, cfg)
    local SW, SH = 1920, 1080
    local small = M.growDef(320, SW, 'Box')
    local big = copy(small)
    big.w = 780
    local reg = L.createRegistry({ config = cfg })
    reg:setScreen(SW, SH)
    local owner = 'aeterna_selftest'
    return runChecks({
        { label = 'an element at the right edge grows from 320 to 780', fn = function()
            local out = L.clampPlace(placeOf(small), 780, small.h, SW, SH)
            local left = M.leftTop(out, 780, small.h, SW, SH)
            return math.abs(left + 780 - SW) > EPS and ('box ends at ' .. math.floor(left + 780)) or nil
        end },
        { label = 'a box larger than the screen goes to 0, 0', fn = function()
            local out = L.clampPlace(placeOf(small), 2000, small.h, SW, SH)
            return (out.x ~= 0 or out.ax ~= 0) and 'x ' .. tostring(out.x) or nil
        end },
        { label = 'scale 2.0 at the bottom edge', fn = function()
            local p = { x = 0.5, y = (SH - 60) / SH, ax = 0.5, ay = 0, scale = 2, hidden = false }
            local ok, why = M.boxOnScreen(L.clampPlace(p, 320, 60, SW, SH), 320, 60, SW, SH)
            return not ok and why or nil
        end },
        { label = '3440 to 1280 px wide', fn = function()
            local p = { x = 3000 / 3440, y = 0.5, ax = 0, ay = 0.5, scale = 1, hidden = false }
            local ok, why = M.boxOnScreen(L.clampPlace(p, 320, 60, 1280, 720), 320, 60, 1280, 720)
            return not ok and why or nil
        end },
        { label = 're-add with a new width clamps and keeps the saved place', fn = function()
            reg:add(owner, small)
            local ok, err, eff = reg:add(owner, big)
            if not ok then return 'refused (' .. tostring(err) .. ')' end
            local on, why = M.boxOnScreen(eff, big.w, big.h, SW, SH)
            if not on then return why end
            if not placesEqual(reg:get(owner, small.id).place, placeOf(small)) then return 'chosen place changed' end
            return next(reg:getSavedPlaces()) ~= nil and 'something was saved' or nil
        end },
        { label = 'shrinking back returns the place exactly', fn = function()
            local ok, err, eff = reg:add(owner, small)
            if not ok then return 'refused (' .. tostring(err) .. ')' end
            return not placesEqual(eff, placeOf(small)) and 'came back at x ' .. tostring(eff.x) or nil
        end },
    })
end

local PLACE_JSON = '{"x":0.5,"y":0.5,"ax":0,"ay":0,"scale":1,"hidden":false}'

local function importText(body)
    return 'aeterna-layout:1:' .. body
end

-- import_validate: every malformed text is refused whole with a path; a good export round-trips.
local function importValidate(L, cfg)
    local function refused(label, text, fragment, kind)
        return { label = label, fn = function()
            local ok, err, _, gotKind = L.decodeImport(text, cfg)
            if ok then return 'accepted' end
            if fragment and not tostring(err):find(fragment, 1, true) then return 'error ' .. tostring(err) end
            if kind and gotKind ~= kind then return 'kind ' .. tostring(gotKind) end
            return nil
        end }
    end
    local many = {}
    for i = 1, 65 do
        many[i] = ('"res/e%d":%s'):format(i, PLACE_JSON)
    end
    local places = { ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 0.85, hidden = false } }
    return runChecks({
        refused('8193 bytes', importText(('x'):rep(8193 - #'aeterna-layout:1:')), 'text: max 8192'),
        refused('wrong prefix', 'aeterna-layout:2:{"v":1,"places":{}}', 'text: prefix'),
        refused('v = 2', importText('{"v":2,"places":{}}'), nil, 'version'),
        refused('65 entries', importText('{"v":1,"places":{' .. table.concat(many, ',') .. '}}'), 'places: max'),
        refused('a bad key', importText('{"v":1,"places":{"bad key":' .. PLACE_JSON .. '}}'), 'key'),
        refused('a scale out of range',
            importText('{"v":1,"places":{"res/e":{"x":0.5,"y":0.5,"ax":0,"ay":0,"scale":9,"hidden":false}}}'), '.scale'),
        refused('an extra field in a place',
            importText('{"v":1,"places":{"res/e":{"x":0.5,"y":0.5,"ax":0,"ay":0,"scale":1,"hidden":false,"z":1}}}')),
        refused('an extra top-level field', importText('{"v":1,"places":{},"x":1}'), 'x: not allowed'),
        { label = 'an export round-trips', fn = function()
            local text = L.encodeExport(places, { 'aeterna_hudkit/status' }, cfg)
            if not text then return 'export refused' end
            local ok, err, back = L.decodeImport(text, cfg)
            if not ok then return 'import refused (' .. tostring(err) .. ')' end
            return not placesEqual(back['aeterna_hudkit/status'], places['aeterna_hudkit/status']) and 'place changed' or nil
        end },
    })
end

local SERVER_CHECKS = {
    placement_math = placementMath,
    import_validate = importValidate,
}

function M.run(short, L, cfg)
    local fn = SERVER_CHECKS[short]
    if not fn then
        return nil
    end
    return fn(L, cfg)
end

-- Client judges -------------------------------------------------------------------------------------------------

local function onGrid(v, step)
    local r = v / step
    return math.abs(r - math.floor(r + 0.5)) < 1e-3
end

-- grid_drag: snapped / free = { grid = shown while dragging, left, top = where the element landed, px }.
function M.judgeGrid(snapped, free, step)
    if type(snapped) ~= 'table' or type(free) ~= 'table' then
        return false, 'a drag did not finish'
    end
    if not snapped.grid then
        return false, 'no grid while dragging'
    end
    if not (onGrid(snapped.left, step) and onGrid(snapped.top, step)) then
        return false, ('landed at %.1f,%.1f, off the %d px grid'):format(snapped.left, snapped.top, step)
    end
    if free.grid then
        return false, 'grid shown with Shift held'
    end
    if onGrid(free.left, step) and onGrid(free.top, step) then
        return false, 'the Shift drag snapped to the grid'
    end
    return true, ('grid at %d px while dragging; Shift drag did not snap'):format(step)
end

-- export_import: facts = { text = export, pageText = what the export box held, importOk, before, after }.
function M.judgeExportImport(f)
    if type(f.text) ~= 'string' then
        return false, 'export refused'
    end
    if f.text:find('[\r\n]') then
        return false, 'export is more than one line'
    end
    if f.text:sub(1, #'aeterna-layout:1:') ~= 'aeterna-layout:1:' then
        return false, 'export has no prefix'
    end
    if f.pageText ~= f.text then
        return false, 'the export box did not show the export'
    end
    if not f.importOk then
        return false, 'import refused the export'
    end
    if not placesEqual(f.before, f.after) then
        return false, 'import did not put the moved element back'
    end
    return true, 'one line; import put the moved element back'
end

-- export_copy: probe = { copied } from the page (the copy command's result); importOk = the import callback's result
-- for the export text the page put into the import box.
function M.judgeCopy(probe, importOk)
    if type(probe) ~= 'table' then
        return false, 'the page did not report'
    end
    if not probe.copied then
        return false, 'copy from the export box did not run'
    end
    if importOk ~= true then
        return false, 'import refused the export text'
    end
    return true, 'copy ran; the export text imported'
end

-- reset_from_menu: saved = the saved places after the reset; elements = { { key, place, default } };
-- hadSaved = there was a saved layout before it.
function M.judgeReset(saved, elements, hadSaved)
    if type(saved) ~= 'table' or next(saved) ~= nil then
        return false, 'the saved layout was not cleared'
    end
    for _, el in ipairs(elements) do
        if not placesEqual(el.place, el.default) then
            return false, el.key .. ' is not at its default'
        end
    end
    local what = hadSaved and 'saved layout cleared' or 'nothing to clear (no saved layout)'
    return true, ('client half of Reset all: %d elements at their default; %s'):format(#elements, what)
end

return LayoutSelftests
