-- Pure self-test logic for aeterna_uikit 0.2 (docs/specs/aeterna_uikit.md § Self-tests (0.2)): the rows registered
-- with aeterna_core, the three server checks, the client test panels and the pass rules of the client tests.
-- Natives-free; loads after shared/logic/uikit.lua.

UikitSelftests = {}
local M = UikitSelftests

M.PREFIX = 'aeterna_uikit.'

-- Exactly the spec table. `expect` = the row has an Expect text (locale key uikit.selftest.<name>).
M.ROWS = {
    { name = 'spec_limits', kind = 'headless' },
    { name = 'values_recheck', kind = 'headless' },
    { name = 'forged_action', kind = 'headless' },
    { name = 'panel_every_block', kind = 'eye', expect = true },
    { name = 'tabs_switch', kind = 'ped', expect = true },
    { name = 'slider_keyboard', kind = 'ped', expect = true },
    { name = 'motion_reduced', kind = 'eye', expect = true },
    { name = 'focus_lost_closes', kind = 'ped', expect = true },
    { name = 'overlay_pauses', kind = 'eye', expect = true },
}

local BY_NAME = {}
for i = 1, #M.ROWS do
    BY_NAME[M.ROWS[i].name] = M.ROWS[i]
end

M.TAB_TARGET = 'tab_b'
M.SLIDER = { id = 'vol', min = 0, max = 100, step = 5, value = 50 }

-- Registers every row through add(fullName, meta); t(key) translates. Returns how many core accepted.
function M.register(add, t)
    local count = 0
    for i = 1, #M.ROWS do
        local row = M.ROWS[i]
        local meta = { kind = row.kind }
        if row.expect then
            meta.expect = t('uikit.selftest.' .. row.name)
        end
        if add(M.PREFIX .. row.name, meta) ~= nil then
            count = count + 1
        end
    end
    return count
end

-- 'aeterna_uikit.spec_limits' -> 'spec_limits'; nil for another resource's test or an unknown name.
function M.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #M.PREFIX) ~= M.PREFIX then
        return nil
    end
    local short = fullName:sub(#M.PREFIX + 1)
    return BY_NAME[short] and short or nil
end

-- Runs each case through check(case) -> accepted:boolean, err, result. A case passes when `accepted`
-- equals case.ok and case.verify (if any) approves the result. Returns ok, detail.
local function runCases(cases, check)
    for i = 1, #cases do
        local c = cases[i]
        local accepted, err, result = check(c)
        if accepted and not c.ok then
            return false, c.label .. ': accepted'
        end
        if not accepted and c.ok then
            return false, c.label .. ': refused (' .. tostring(err) .. ')'
        end
        if accepted and c.verify then
            local why = c.verify(result)
            if why then
                return false, c.label .. ': ' .. why
            end
        end
    end
    return true, #cases .. ' cases held'
end

local function textBlocks(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = 't' .. i, type = 'text', label = 'x' }
    end
    return out
end

local function listItems(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = 'i' .. i, label = 'Item' }
    end
    return out
end

local function tabItems(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = 'tab_' .. i, label = 'Tab' }
    end
    return out
end

local function columns(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = 'c' .. i, label = 'Col' }
    end
    return out
end

local function rows(n)
    local out = {}
    for i = 1, n do
        out[i] = { id = 'r' .. i, cells = { c1 = 'x' } }
    end
    return out
end

local function one(block)
    return { title = 'Limits', blocks = { block } }
end

-- spec_limits: open() refuses every spec over a 0.1 or 0.2 limit and accepts the largest one inside it.
local function specLimits(L)
    local cases = {
        { label = '41 blocks', ok = false, spec = { title = 'Limits', blocks = textBlocks(41) } },
        { label = '40 blocks', ok = true, spec = { title = 'Limits', blocks = textBlocks(40) } },
        { label = 'two tabs blocks', ok = false, spec = { title = 'Limits', blocks = {
            { id = 'ta', type = 'tabs', items = tabItems(2) },
            { id = 'tb', type = 'tabs', items = { { id = 'x1', label = 'X' }, { id = 'x2', label = 'Y' } } },
        } } },
        { label = 'one tab', ok = false, spec = one({ id = 'ta', type = 'tabs', items = tabItems(1) }) },
        { label = 'seven tabs', ok = false, spec = one({ id = 'ta', type = 'tabs', items = tabItems(7) }) },
        { label = 'seven table columns', ok = false, spec = one({ id = 'tbl', type = 'table', columns = columns(7), rows = {} }) },
        { label = '51 table rows', ok = false, spec = one({ id = 'tbl', type = 'table', columns = columns(1), rows = rows(51) }) },
        { label = '1001 slider steps', ok = false,
            spec = one({ id = 's', type = 'slider', label = 'S', min = 0, max = 1001, step = 1 }) },
        { label = '51 list items without search', ok = false, spec = one({ id = 'l', type = 'list', items = listItems(51) }) },
        { label = '200 list items with search', ok = true,
            spec = one({ id = 'l', type = 'list', search = true, items = listItems(200) }) },
        { label = '201 list items with search', ok = false,
            spec = one({ id = 'l', type = 'list', search = true, items = listItems(201) }) },
        { label = '61-character Thai title', ok = false, spec = { title = ('ก'):rep(61), blocks = textBlocks(1) } },
        { label = '60-character Thai title', ok = true, spec = { title = ('ก'):rep(60), blocks = textBlocks(1) } },
    }
    return runCases(cases, function(c)
        return L.validateSpec(c.spec)
    end)
end

-- A panel as the server keeps it, validated by the real validator.
local function openPanel(L, spec)
    local ok, err, clean = L.validateSpec(spec)
    if not ok then
        return nil, err
    end
    return { panelId = 'p1', owner = 'aeterna_uikit', spec = clean }
end

local RECHECK_SPEC = { title = 'Recheck', blocks = {
    { id = 'tabs', type = 'tabs', items = { { id = 'tab_a', label = 'A' }, { id = 'tab_b', label = 'B' } } },
    { id = 'note', type = 'field', label = 'Note', tab = 'tab_b' },
    { id = 'vol', type = 'slider', label = 'V', min = 0, max = 100, step = 5, value = 50 },
    { id = 'act', type = 'buttons', items = { { id = 'ok', label = 'OK' } } },
} }

-- values_recheck: values coming back with an action are checked again on the server.
local function valuesRecheck(L)
    local panel, err = openPanel(L, RECHECK_SPEC)
    if not panel then
        return false, 'test spec refused: ' .. tostring(err)
    end
    local cases = {
        { label = 'slider off the step grid', ok = false, values = { vol = 52 } },
        { label = 'slider out of range', ok = false, values = { vol = 105 } },
        { label = 'slider as a string', ok = false, values = { vol = '55' } },
        { label = 'tab not in the list', ok = false, values = { tabs = 'tab_z' } },
        { label = 'value for no block', ok = false, values = { extra = 'x' } },
        { label = 'good values', ok = true, values = { vol = 55, tabs = 'tab_a', note = 'hi' },
            verify = function(res)
                local v = res.values or {}
                if type(v.vol) ~= 'number' or v.vol ~= 55 then return 'slider did not come back as the number 55' end
                if v.tabs ~= 'tab_a' then return 'active tab did not come back' end
                if v.note ~= 'hi' then return 'field on a hidden tab did not come back' end
                return nil
            end },
    }
    return runCases(cases, function(c)
        return L.validateAction(panel, { panelId = 'p1', action = 'ok', values = c.values })
    end)
end

local FORGED_SPEC = { title = 'Forged', blocks = {
    { id = 'tabs', type = 'tabs', items = { { id = 'tab_a', label = 'A' }, { id = 'tab_b', label = 'B' } } },
    { id = 'log', type = 'table', columns = { { id = 'c1', label = 'C' } }, rows = { { id = 'r1', cells = { c1 = 'x' } } } },
    { id = 'act', type = 'buttons', items = { { id = 'ok', label = 'OK' }, { id = 'off', label = 'Off', disabled = true } } },
} }

-- forged_action: an action the open spec does not offer is dropped.
local function forgedAction(L)
    local panel, err = openPanel(L, FORGED_SPEC)
    if not panel then
        return false, 'test spec refused: ' .. tostring(err)
    end
    local cases = {
        { label = 'action not in the spec', ok = false, action = 'nope' },
        { label = 'tab id while report is off', ok = false, action = 'tab_b' },
        { label = 'row id of a table that is not selectable', ok = false, action = 'r1' },
        { label = 'disabled button', ok = false, action = 'off' },
        { label = 'over-long action', ok = false, action = ('a'):rep(33) },
        { label = 'wrong panelId', ok = false, action = 'ok', panelId = 'p2' },
        { label = 'no panel open', ok = false, action = 'ok', closed = true },
        { label = 'button press', ok = true, action = 'ok',
            verify = function(res)
                return res.owner ~= 'aeterna_uikit' and 'owner was ' .. tostring(res.owner) or nil
            end },
        { label = '__close', ok = true, action = '__close' },
    }
    return runCases(cases, function(c)
        return L.validateAction(not c.closed and panel or nil,
            { panelId = c.panelId or 'p1', action = c.action, values = {} })
    end)
end

local SERVER_CHECKS = {
    spec_limits = specLimits,
    values_recheck = valuesRecheck,
    forged_action = forgedAction,
}

-- Runs a server check: ok, detail. nil when `short` is not one.
function M.run(short, L)
    local fn = SERVER_CHECKS[short]
    if not fn then
        return nil
    end
    return fn(L)
end

-- Client test panels ---------------------------------------------------------------------------------------------

local function tabsBlock(t, report)
    return { id = 'tabs', type = 'tabs', value = 'tab_a', report = report, items = {
        { id = 'tab_a', label = t('uikit.selftest.tab_a') },
        { id = 'tab_b', label = t('uikit.selftest.tab_b') },
    } }
end

local function sliderBlock(t)
    local s = M.SLIDER
    return { id = s.id, type = 'slider', label = t('uikit.selftest.slider'), min = s.min, max = s.max, step = s.step,
        value = s.value }
end

local function info(t, key)
    return { id = 'info', type = 'text', label = t(key) }
end

local function everyBlock(t)
    local items = {}
    for i = 1, 6 do
        items[i] = { id = 'item_' .. i, label = t('uikit.selftest.item', { n = i }) }
    end
    local tableRows = {}
    for i = 1, 3 do
        tableRows[i] = { id = 'row_' .. i, cells = { time = ('21:4%d'):format(i), event = t('uikit.selftest.row', { n = i }) } }
    end
    return {
        tabsBlock(t, false),
        { id = 'on_a', type = 'text', label = t('uikit.selftest.on_tab_a'), tab = 'tab_a' },
        { id = 'on_b', type = 'text', label = t('uikit.selftest.on_tab_b'), tab = 'tab_b' },
        { id = 'list', type = 'list', search = true, items = items },
        sliderBlock(t),
        { id = 'log', type = 'table', columns = {
            { id = 'time', label = t('uikit.selftest.col_time') },
            { id = 'event', label = t('uikit.selftest.col_event') },
        }, rows = tableRows },
        { id = 'none', type = 'empty', icon = 'box', label = t('uikit.selftest.empty'), body = t('uikit.selftest.empty_body') },
    }
end

local PANELS = {
    panel_every_block = function(t) return 'md', everyBlock(t) end,
    tabs_switch = function(t)
        return 'sm', {
            tabsBlock(t, true),
            { id = 'on_a', type = 'text', label = t('uikit.selftest.on_tab_a'), tab = 'tab_a' },
            { id = 'on_b', type = 'text', label = t('uikit.selftest.on_tab_b'), tab = 'tab_b' },
        }
    end,
    slider_keyboard = function(t)
        return 'sm', { sliderBlock(t), { id = 'act', type = 'buttons', items = { { id = 'ok', label = t('uikit.selftest.ok') } } } }
    end,
    motion_reduced = function(t) return 'sm', { info(t, 'uikit.selftest.motion_hint') } end,
    focus_lost_closes = function(t) return 'sm', { info(t, 'uikit.selftest.focus_hint') } end,
    overlay_pauses = function(t)
        return 'sm', {
            info(t, 'uikit.selftest.paused_hint'),
            { id = 'act', type = 'buttons', items = { { id = 'press', label = t('uikit.selftest.press'), variant = 'primary' } } },
        }
    end,
}

-- The panel spec a client test opens; nil for a name with no panel.
function M.panelSpec(short, t)
    local build = PANELS[short]
    if not build then
        return nil
    end
    local size, blocks = build(t)
    return { title = t('uikit.selftest.title'), size = size, blocks = blocks }
end

-- Ids of the blocks shown while `tab` is active: blocks without a tab and blocks on that tab, in spec order.
function M.visibleFor(spec, tab)
    local out = {}
    for _, b in ipairs(spec.blocks or {}) do
        if b.tab == nil or b.tab == tab then
            out[#out + 1] = b.id
        end
    end
    return out
end

local function joinIds(list)
    local parts = {}
    for i = 1, #list do
        parts[i] = tostring(list[i])
    end
    return table.concat(parts, ',')
end

-- tabs_switch: result = what the owner received for the page's tab click; probe = { visible = { blockId, … } }.
function M.judgeTabs(spec, result, probe)
    if type(result) ~= 'table' then
        return false, 'the tab switch did not reach the owner'
    end
    if result.action ~= M.TAB_TARGET then
        return false, 'the owner got action ' .. tostring(result.action)
    end
    if type(result.values) ~= 'table' or result.values.tabs ~= M.TAB_TARGET then
        return false, 'values.tabs was ' .. tostring(type(result.values) == 'table' and result.values.tabs or nil)
    end
    if type(probe) ~= 'table' or type(probe.visible) ~= 'table' then
        return false, 'the page did not report its blocks'
    end
    local want, got = joinIds(M.visibleFor(spec, M.TAB_TARGET)), joinIds(probe.visible)
    if want ~= got then
        return false, 'shown blocks ' .. got .. ', expected ' .. want
    end
    return true, 'the owner got ' .. M.TAB_TARGET .. ' and its blocks showed'
end

-- slider_keyboard: one ArrowRight on the slider, then OK. result = what the owner received; probe = { shown }.
function M.judgeSlider(result, probe)
    local want = M.SLIDER.value + M.SLIDER.step
    if type(result) ~= 'table' or result.action ~= 'ok' then
        return false, 'the OK press did not reach the owner'
    end
    local got = type(result.values) == 'table' and result.values[M.SLIDER.id] or nil
    if got ~= want then
        return false, 'the owner got ' .. tostring(got) .. ', expected ' .. want
    end
    if type(probe) ~= 'table' or tonumber(probe.shown) ~= want then
        return false, 'the page showed ' .. tostring(type(probe) == 'table' and probe.shown or nil) .. ', expected ' .. want
    end
    return true, 'one arrow step: shown ' .. want .. ', owner got ' .. want
end

-- overlay_pauses, after the eye card closes: facts = { paused = boolean, panelOpen = boolean }.
function M.judgeResume(facts)
    if facts.paused then
        return false, 'the panel is still paused after focus came back'
    end
    if not facts.panelOpen then
        return false, 'the panel closed while the card was up'
    end
    return true, 'the panel is open and takes input again'
end

-- focus_lost_closes: facts = { panelOpen = boolean, close = what the owner received or nil }.
function M.judgeFocusLost(facts)
    if facts.panelOpen then
        return false, 'the panel stayed open after the focus loss'
    end
    if type(facts.close) ~= 'table' or facts.close.action ~= '__close' then
        return false, 'the owner did not get __close'
    end
    return true, 'the panel closed and the owner got __close'
end

return UikitSelftests
