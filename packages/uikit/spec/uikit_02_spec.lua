-- uikit_02_spec.lua -- aeterna_uikit 0.2 additions (docs/specs/aeterna_uikit.md § Tests (0.2, busted)).
-- Case 2 (slider) lives in uikit_spec.lua § 7.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function loadLogic()
    natives.reset()
    return assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
end

local function spec(blocks, extra)
    local s = { title = 'Test', size = 'md', blocks = blocks }
    for k, v in pairs(extra or {}) do
        s[k] = v
    end
    return s
end

local function tabsBlock(n, extra)
    local items = {}
    for i = 1, n do
        items[i] = { id = 'tab_' .. i, label = 'Tab ' .. i }
    end
    local b = { id = 'tabs', type = 'tabs', items = items }
    for k, v in pairs(extra or {}) do
        b[k] = v
    end
    return b
end

local function openPanel(L, s)
    local pm = L.createPanelManager()
    local panelId, err = pm:open(1, 'owner_res', s)
    assert.is_nil(err)
    return pm, panelId
end

describe('aeterna_uikit 0.2', function()
    describe('1. tabs', function()
        local L
        before_each(function() L = loadLogic() end)

        it('fails with two tabs blocks', function()
            local b2 = tabsBlock(2)
            b2.id = 'tabs2'
            b2.items = { { id = 'x1', label = 'X1' }, { id = 'x2', label = 'X2' } }
            local ok, err = L.validateSpec(spec({ tabsBlock(2), b2 }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[2%]%.type:'))
        end)

        it('fails with one tab or seven tabs', function()
            local ok1, err1 = L.validateSpec(spec({ tabsBlock(1) }))
            assert.is_false(ok1)
            assert.is_truthy(err1 and err1:match('^blocks%[1%]%.items:'))
            local ok7, err7 = L.validateSpec(spec({ tabsBlock(7) }))
            assert.is_false(ok7)
            assert.is_truthy(err7 and err7:match('^blocks%[1%]%.items:'))
            assert.is_true((L.validateSpec(spec({ tabsBlock(6) }))))
        end)

        it('fails when a block names an unknown tab, or carries tab without a tabs block', function()
            local ok, err = L.validateSpec(spec({
                tabsBlock(2),
                { id = 'q', type = 'text', label = 'Hello', tab = 'nope' },
            }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[2%]%.tab:'))

            local okNoTabs, errNoTabs = L.validateSpec(spec({
                { id = 'q', type = 'text', label = 'Hello', tab = 'tab_1' },
            }))
            assert.is_false(okNoTabs)
            assert.is_truthy(errNoTabs and errNoTabs:match('^blocks%[1%]%.tab:'))

            local okSelf, errSelf = L.validateSpec(spec({ tabsBlock(2, { tab = 'tab_1' }) }))
            assert.is_false(okSelf)
            assert.is_truthy(errSelf and errSelf:match('^blocks%[1%]%.tab:'))
        end)

        it('fails when a tab id collides with another id in the spec', function()
            local ok, err = L.validateSpec(spec({
                { id = 'tab_1', type = 'divider' },
                tabsBlock(2),
            }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[2%]%.items%[1%]%.id:'))
        end)

        it('defaults value to the first tab and keeps tab on blocks', function()
            local ok, _, clean = L.validateSpec(spec({
                tabsBlock(3),
                { id = 'q', type = 'field', label = 'Search parts', tab = 'tab_2' },
            }))
            assert.is_true(ok)
            assert.are.equal('tab_1', clean.blocks[1].value)
            assert.is_false(clean.blocks[1].report)
            assert.are.equal('tab_2', clean.blocks[2].tab)

            local okBad, errBad = L.validateSpec(spec({ tabsBlock(2, { value = 'nope' }) }))
            assert.is_false(okBad)
            assert.is_truthy(errBad and errBad:match('^blocks%[1%]%.value:'))
        end)

        it('returns the active tab in values', function()
            local _, _, clean = L.validateSpec(spec({ tabsBlock(3) }))
            local ok, _, values = L.validateValues(clean, { tabs = 'tab_3' })
            assert.is_true(ok)
            assert.are.equal('tab_3', values.tabs)
            assert.is_false((L.validateValues(clean, { tabs = 'tab_9' })))
        end)

        it('allows a tab id as an action only with report = true', function()
            local pm, pid = openPanel(L, spec({ tabsBlock(2) }))
            assert.is_false((pm:handleAction(1, { panelId = pid, action = 'tab_2', values = {} })))

            local pmR, pidR = openPanel(L, spec({ tabsBlock(2, { report = true }) }))
            local ok, _, res = pmR:handleAction(1, { panelId = pidR, action = 'tab_2', values = { tabs = 'tab_2' } })
            assert.is_true(ok)
            assert.are.equal('tab_2', res.action)
            assert.are.equal('tab_2', res.values.tabs)
        end)
    end)

    describe('3. table', function()
        local L
        before_each(function() L = loadLogic() end)

        local function tableBlock(extra)
            local b = {
                id = 'log', type = 'table',
                columns = { { id = 'when', label = 'When' }, { id = 'what', label = 'What', align = 'end' } },
                rows = { { id = 'r1', cells = { when = '21:47', what = 'Login' } }, { id = 'r2', cells = { when = '21:50' } } },
            }
            for k, v in pairs(extra or {}) do
                b[k] = v
            end
            return b
        end

        it('passes a valid table with defaults', function()
            local ok, err, clean = L.validateSpec(spec({ tableBlock() }))
            assert.is_true(ok, err)
            local b = clean.blocks[1]
            assert.are.equal('start', b.columns[1].align)
            assert.are.equal('end', b.columns[2].align)
            assert.are.equal(2, #b.rows)
            assert.is_false(b.selectable)
            assert.is_false(b.rows[1].disabled)
        end)

        it('fails with seven columns', function()
            local cols = {}
            for i = 1, 7 do cols[i] = { id = 'c' .. i, label = 'C' .. i } end
            local ok, err = L.validateSpec(spec({ tableBlock({ columns = cols, rows = {} }) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.columns:'))
        end)

        it('fails with 51 rows', function()
            local rows = {}
            for i = 1, 51 do rows[i] = { id = 'r' .. i, cells = { when = 'x' } } end
            local ok, err = L.validateSpec(spec({ tableBlock({ rows = rows }) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.rows:'))
        end)

        it('fails with a cell key that is not a column', function()
            local ok, err = L.validateSpec(spec({ tableBlock({ rows = { { id = 'r1', cells = { who = 'x' } } } }) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.rows%[1%]%.cells%.who:'))
        end)

        it('fails with a duplicate row id', function()
            local ok, err = L.validateSpec(spec({ tableBlock({ rows = { { id = 'r1', cells = {} }, { id = 'r1', cells = {} } } }) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.rows%[2%]%.id:'))
        end)

        it('allows a row id as an action only when selectable = true', function()
            local pm, pid = openPanel(L, spec({ tableBlock() }))
            assert.is_false((pm:handleAction(1, { panelId = pid, action = 'r1', values = {} })))

            local pmS, pidS = openPanel(L, spec({ tableBlock({ selectable = true }) }))
            local ok, _, res = pmS:handleAction(1, { panelId = pidS, action = 'r1', values = {} })
            assert.is_true(ok)
            assert.are.equal('r1', res.action)
        end)

        it('accepts an empty option on a table', function()
            local ok, _, clean = L.validateSpec(spec({ tableBlock({ rows = {}, empty = { icon = 'clock', label = 'Nothing yet' } }) }))
            assert.is_true(ok)
            assert.are.equal('Nothing yet', clean.blocks[1].empty.label)
            assert.are.equal('clock', clean.blocks[1].empty.icon)
        end)
    end)

    describe('4. list.search', function()
        local L
        before_each(function() L = loadLogic() end)

        local function listBlock(n, search)
            local items = {}
            for i = 1, n do items[i] = { id = 'i' .. i, label = 'Item ' .. i } end
            return { id = 'pick', type = 'list', items = items, search = search }
        end

        it('passes 200 items with search on and fails 201', function()
            local ok, err, clean = L.validateSpec(spec({ listBlock(200, true) }))
            assert.is_true(ok, err)
            assert.are.same({}, clean.blocks[1].search)
            assert.is_true((L.validateSpec(spec({ listBlock(200, { placeholder = 'Find a part' }) }))))
            local okOver, errOver = L.validateSpec(spec({ listBlock(201, true) }))
            assert.is_false(okOver)
            assert.is_truthy(errOver and errOver:match('^blocks%[1%]%.items:'))
        end)

        it('fails 51 items with search off', function()
            local ok, err = L.validateSpec(spec({ listBlock(51, nil) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.items:'))
            local okFalse = L.validateSpec(spec({ listBlock(51, false) }))
            assert.is_false(okFalse)
        end)

        it('fails a placeholder over 40 characters', function()
            local ok, err = L.validateSpec(spec({ listBlock(2, { placeholder = string.rep('a', 41) }) }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.search%.placeholder:'))
        end)

        it('accepts an empty option on a list', function()
            local ok, _, clean = L.validateSpec(spec({ { id = 'pick', type = 'list', items = {}, empty = { label = 'No parts', body = 'Add one first' } } }))
            assert.is_true(ok)
            assert.are.equal('No parts', clean.blocks[1].empty.label)
            assert.are.equal('Add one first', clean.blocks[1].empty.body)
            local okNoLabel, errNoLabel = L.validateSpec(spec({ { id = 'pick', type = 'list', items = {}, empty = { body = 'x' } } }))
            assert.is_false(okNoLabel)
            assert.is_truthy(errNoLabel and errNoLabel:match('^blocks%[1%]%.empty%.label:'))
        end)
    end)

    describe('5. empty block', function()
        local L
        before_each(function() L = loadLogic() end)

        it('fails without label', function()
            local ok, err = L.validateSpec(spec({ { id = 'none', type = 'empty', icon = 'box' } }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.label:'))
        end)

        it('fails an unknown icon or an action without label', function()
            local okIcon, errIcon = L.validateSpec(spec({ { id = 'none', type = 'empty', icon = 'nope', label = 'Empty' } }))
            assert.is_false(okIcon)
            assert.is_truthy(errIcon and errIcon:match('^blocks%[1%]%.icon:'))
            local okAct, errAct = L.validateSpec(spec({ { id = 'none', type = 'empty', label = 'Empty', action = { id = 'add' } } }))
            assert.is_false(okAct)
            assert.is_truthy(errAct and errAct:match('^blocks%[1%]%.action%.label:'))
        end)

        it('makes its action.id an allowed action', function()
            local pm, pid = openPanel(L, spec({
                { id = 'none', type = 'empty', icon = 'box', label = 'No items', body = 'Add one', action = { id = 'add', label = 'Add' } },
            }))
            local ok, _, res = pm:handleAction(1, { panelId = pid, action = 'add', values = {} })
            assert.is_true(ok)
            assert.are.equal('add', res.action)
            assert.is_false((pm:handleAction(1, { panelId = pid, action = 'none', values = {} })))
        end)
    end)

    describe('6. detailOf', function()
        local L
        before_each(function() L = loadLogic() end)

        it('fails a bad id', function()
            local ok, err = L.validateSpec(spec({}, { detailOf = 'bad id!', detailItem = 'c42' }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^detailOf:'))
            local ok2, err2 = L.validateSpec(spec({}, { detailOf = 'contacts', detailItem = string.rep('a', 33) }))
            assert.is_false(ok2)
            assert.is_truthy(err2 and err2:match('^detailItem:'))
        end)

        it('fails detailItem without detailOf', function()
            local ok, err = L.validateSpec(spec({}, { detailItem = 'c42' }))
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^detailItem:'))
        end)

        it('passes both through to the cleaned spec', function()
            local ok, _, clean = L.validateSpec(spec({}, { detailOf = 'contacts', detailItem = 'c42' }))
            assert.is_true(ok)
            assert.are.equal('contacts', clean.detailOf)
            assert.are.equal('c42', clean.detailItem)
            local okOnly, _, cleanOnly = L.validateSpec(spec({}, { detailOf = 'contacts' }))
            assert.is_true(okOnly)
            assert.are.equal('contacts', cleanOnly.detailOf)
            assert.is_nil(cleanOnly.detailItem)
        end)
    end)

    describe('7. update (changed in 0.2)', function()
        local L, pm, pid
        before_each(function()
            L = loadLogic()
            pm, pid = openPanel(L, spec({
                tabsBlock(3),
                { id = 'vol', type = 'slider', label = 'Volume', min = 0, max = 100, step = 5, value = 50 },
                {
                    id = 'log', type = 'table',
                    columns = { { id = 'when', label = 'When' } },
                    rows = { { id = 'r1', cells = { when = '21:47' } } },
                },
                { id = 'pick', type = 'list', items = { { id = 'a', label = 'A' } } },
                { id = 'act', type = 'buttons', items = { { id = 'ok', label = 'OK' } } },
            }))
        end)

        it('patches table rows, tab value and slider value', function()
            local ok, err, clean = pm:update(1, pid, {
                blocks = {
                    log = { rows = { { id = 'r1', cells = { when = '22:00' } }, { id = 'r2', cells = { when = '22:05' } } } },
                    tabs = { value = 'tab_2' },
                    vol = { value = 75 },
                },
            })
            assert.is_true(ok, err)
            assert.are.equal(2, #clean.blocks.log.rows)
            assert.are.equal('tab_2', clean.blocks.tabs.value)
            assert.are.equal(75, clean.blocks.vol.value)
            -- the stored spec follows the patch, so the values re-check uses it
            local okVal, _, values = L.validateValues(pm:getOpen(1).spec, { tabs = 'tab_2', vol = 75 })
            assert.is_true(okVal)
            assert.are.equal(75, values.vol)
        end)

        it('patches the empty option of a list or table', function()
            local ok, err, clean = pm:update(1, pid, { blocks = { pick = { empty = { label = 'Nothing here' } } } })
            assert.is_true(ok, err)
            assert.are.equal('Nothing here', clean.blocks.pick.empty.label)
            assert.is_false((pm:update(1, pid, { blocks = { vol = { empty = { label = 'x' } } } })))
        end)

        it('refuses a slider value out of range or off the step grid', function()
            assert.is_false((pm:update(1, pid, { blocks = { vol = { value = 105 } } })))
            assert.is_false((pm:update(1, pid, { blocks = { vol = { value = -5 } } })))
            assert.is_false((pm:update(1, pid, { blocks = { vol = { value = 52 } } })))
        end)

        it('refuses an unknown tab value, bad rows, and row ids that collide', function()
            assert.is_false((pm:update(1, pid, { blocks = { tabs = { value = 'nope' } } })))
            assert.is_false((pm:update(1, pid, { blocks = { log = { rows = { { id = 'r1', cells = { who = 'x' } } } } } })))
            assert.is_false((pm:update(1, pid, { blocks = { log = { rows = { { id = 'ok', cells = {} } } } } })))
            assert.is_false((pm:update(1, pid, { blocks = { pick = { rows = {} } } })))
        end)
    end)

    describe('8. a 0.1 spec is unchanged', function()
        local L
        before_each(function() L = loadLogic() end)

        it('validates every 0.1 block type to the same cleaned spec as in 0.1', function()
            local ok, err, clean = L.validateSpec({
                title = 'Vehicle Shop',
                subtitle = 'Choose a configuration',
                size = 'md',
                blocks = {
                    { id = 'intro', type = 'text', label = 'Welcome to the shop' },
                    { id = 'pick', type = 'list', items = {
                        { id = 'sedan', label = 'Sedan', meta = '4 doors', icon = 'car', disabled = false },
                        { id = 'truck', label = 'Truck', meta = 'Heavy', icon = 'wrench', disabled = true },
                    } },
                    { id = 'qty', type = 'field', label = 'Quantity', input = 'number', value = 1, min = 1, max = 100 },
                    { id = 'note', type = 'field', label = 'Note', input = 'text', value = '', maxLen = 10, placeholder = 'Optional note' },
                    { id = 'on', type = 'toggle', label = 'Insurance', value = false },
                    { id = 'mode', type = 'select', label = 'Payment', options = { { id = 'cash', label = 'Cash' }, { id = 'bank', label = 'Bank' } }, value = 'cash' },
                    { id = 'load', type = 'progress', label = 'Stock level', value = 0.4 },
                    { id = 'sep', type = 'divider' },
                    { id = 'act', type = 'buttons', items = {
                        { id = 'ok', label = 'Buy', variant = 'primary' },
                        { id = 'cancel_btn', label = 'Back' },
                    } },
                },
            })
            assert.is_true(ok, err)
            assert.are.same({
                title = 'Vehicle Shop',
                subtitle = 'Choose a configuration',
                size = 'md',
                blocks = {
                    { id = 'intro', type = 'text', label = 'Welcome to the shop' },
                    { id = 'pick', type = 'list', items = {
                        { id = 'sedan', label = 'Sedan', meta = '4 doors', icon = 'car', disabled = false },
                        { id = 'truck', label = 'Truck', meta = 'Heavy', icon = 'wrench', disabled = true },
                    } },
                    { id = 'qty', type = 'field', label = 'Quantity', input = 'number', value = 1, min = 1, max = 100, maxLen = 60, disabled = false },
                    { id = 'note', type = 'field', label = 'Note', input = 'text', value = '', maxLen = 10, placeholder = 'Optional note', disabled = false },
                    { id = 'on', type = 'toggle', label = 'Insurance', value = false, disabled = false },
                    { id = 'mode', type = 'select', label = 'Payment', options = { { id = 'cash', label = 'Cash' }, { id = 'bank', label = 'Bank' } }, value = 'cash', disabled = false },
                    { id = 'load', type = 'progress', label = 'Stock level', value = 0.4 },
                    { id = 'sep', type = 'divider' },
                    { id = 'act', type = 'buttons', items = {
                        { id = 'ok', label = 'Buy', variant = 'primary', disabled = false },
                        { id = 'cancel_btn', label = 'Back', variant = 'secondary', disabled = false },
                    } },
                },
            }, clean)
        end)
    end)

    describe('9. paused by a focus overlay (client)', function()
        local nuiCallbacks, nuiMessages, api

        local function lastAction()
            return natives.last_emitted('server', 'aeterna_uikit:sv:action')
        end

        local function countActions()
            return #natives.emitted('server', 'aeterna_uikit:sv:action')
        end

        before_each(function()
            natives.reset({ resource = 'aeterna_uikit', side = 'client' })
            nuiCallbacks = {}
            nuiMessages = natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback', function(name, fn) nuiCallbacks[name] = fn end)
            natives.spy('RegisterCommand')
            natives.spy('GetHashKey', function() return 1 end)
            natives.spy('GetControlInstructionalButton', function() return 'b_-1' end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return k end,
                lang = function() return 'en' end,
                key = function() end,
                requestFocus = function() return 'tok_1' end,
                releaseFocus = function() return true end,
            })
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
            api = resource.load_resource(DIR, 'client').exports
            natives.fire_net('aeterna_uikit:cl:open', 1, { panelId = 'p1', title = 'Test', size = 'md', blocks = {} })
        end)

        it('drops a panelAction while paused and passes it after resume', function()
            natives.fire('aeterna_core:focusPaused', 'aeterna_uikit', 'tok_1')
            local before = countActions()
            nuiCallbacks.panelAction({ panelId = 'p1', action = 'ok', values = {} }, function() end)
            nuiCallbacks.escape({}, function() end)
            assert.are.equal(before, countActions())

            natives.fire('aeterna_core:focusResumed', 'aeterna_uikit', 'tok_1')
            nuiCallbacks.panelAction({ panelId = 'p1', action = 'ok', values = {} }, function() end)
            assert.are.equal(before + 1, countActions())
            assert.are.equal('ok', lastAction().args[1].action)
        end)

        it('ignores a pause for another resource', function()
            natives.fire('aeterna_core:focusPaused', 'other_res', 'tok_9')
            local before = countActions()
            nuiCallbacks.panelAction({ panelId = 'p1', action = 'ok', values = {} }, function() end)
            assert.are.equal(before + 1, countActions())
        end)

        it('drops a promptResult while paused and passes it after resume', function()
            local answer = 'pending'
            CreateThread(function()
                answer = api.confirm({ title = 'Sure?' })
            end)
            natives.advance(0)
            natives.fire('aeterna_core:focusPaused', 'aeterna_uikit', 'tok_1')
            nuiCallbacks.promptResult({ kind = 'confirm', value = true }, function() end)
            natives.advance(20)
            assert.are.equal('pending', answer)

            natives.fire('aeterna_core:focusResumed', 'aeterna_uikit', 'tok_1')
            nuiCallbacks.promptResult({ kind = 'confirm', value = true }, function() end)
            natives.advance(20)
            assert.is_true(answer)
        end)

        it('still fires __close on a real focus loss, also while paused', function()
            natives.fire('aeterna_core:focusPaused', 'aeterna_uikit', 'tok_1')
            natives.fire('aeterna_core:focusLost', 'aeterna_uikit', 'tok_1', 'preempted')
            local ev = lastAction()
            assert.is_truthy(ev)
            assert.are.equal('p1', ev.args[1].panelId)
            assert.are.equal('__close', ev.args[1].action)
            local closeMsg = nuiMessages[#nuiMessages][1]
            assert.are.equal('panel:close', closeMsg.type)
        end)
    end)
end)
