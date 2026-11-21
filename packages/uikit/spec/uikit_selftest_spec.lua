-- uikit_selftest_spec.lua -- aeterna_uikit self-tests (docs/specs/aeterna_uikit.md § Self-tests (0.2)): the rows it
-- registers with aeterna_core, the pure checks in shared/logic/selftests.lua, and the thin wrappers.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE = HERE .. '/../../core'

-- Fires one of core's local events as aeterna_core (the handlers drop the same event from anyone else).
local function fireCore(name, ...)
    local prev = rawget(_G, 'GetInvokingResource')
    rawset(_G, 'GetInvokingResource', function() return 'aeterna_core' end)
    natives.fire(name, ...)
    rawset(_G, 'GetInvokingResource', prev)
end

-- The same event fired by another resource.
local function fireAs(who, name, ...)
    local prev = rawget(_G, 'GetInvokingResource')
    rawset(_G, 'GetInvokingResource', function() return who end)
    natives.fire(name, ...)
    rawset(_G, 'GetInvokingResource', prev)
end

local function loadModules()
    natives.reset()
    rawset(_G, 'Locales', nil)
    assert(loadfile(DIR .. '/locales/en.lua'))()
    assert(loadfile(DIR .. '/locales/th.lua'))()
    local L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
    assert(loadfile(DIR .. '/shared/logic/selftests.lua'))()
    return L, UikitSelftests
end

-- Core's own meta check, so a row that core would refuse fails here too.
local function coreNormalize()
    rawset(_G, 'AeternaCoreLogic', nil)
    assert(loadfile(CORE .. '/shared/logic/selftest.lua'))()
    return AeternaCoreLogic.selftest.normalize
end

local function translator(lang)
    return function(key, vars)
        local s = Locales[lang][key] or key
        return (s:gsub('{([%w_]+)}', function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or '{' .. k .. '}' end))
    end
end

-- A copy of L with one function replaced, to prove a check fails when the rule it checks is broken.
local function broken(L, name, fn)
    return setmetatable({ [name] = fn }, { __index = L })
end

-- The rows of the spec table: name, kind, and whether Expect is filled in.
local SPEC_ROWS = {
    { 'spec_limits', 'headless', false },
    { 'values_recheck', 'headless', false },
    { 'forged_action', 'headless', false },
    { 'panel_every_block', 'eye', true },
    { 'tabs_switch', 'ped', true },
    { 'slider_keyboard', 'ped', true },
    { 'motion_reduced', 'eye', true },
    { 'focus_lost_closes', 'ped', true },
    { 'overlay_pauses', 'eye', true },
}

describe('aeterna_uikit self-tests: rows', function()
    it('registers exactly the spec rows, in order, with core-valid meta', function()
        local _, S = loadModules()
        local normalize = coreNormalize()
        local added = {}
        S.register(function(name, meta) added[#added + 1] = { name = name, meta = meta } return name end, translator('en'))
        assert.are.equal(#SPEC_ROWS, #added)
        for i, row in ipairs(SPEC_ROWS) do
            local got = added[i]
            assert.are.equal('aeterna_uikit.' .. row[1], got.name)
            local fields, err = normalize(got.meta)
            assert.is_nil(err, row[1])
            assert.are.equal(row[2], fields.kind, row[1])
            assert.are.equal(row[2] == 'headless' and 'server' or 'client', fields.side, row[1])
            assert.are.equal(1, fields.players, row[1])
            assert.is_false(fields.destructive, row[1])
            assert.are.equal(5000, fields.timeout, row[1])
            assert.is_nil(fields.ask, row[1])
            assert.is_nil(fields.skipWhen, row[1])
            if row[3] then
                assert.is_true(type(fields.expect) == 'string' and fields.expect ~= '', row[1])
            else
                assert.is_nil(fields.expect, row[1])
            end
        end
    end)

    it('takes every expect from the locale, in th and en', function()
        local _, S = loadModules()
        for _, lang in ipairs({ 'en', 'th' }) do
            local metas = {}
            S.register(function(name, meta) metas[name] = meta return name end, translator(lang))
            for _, row in ipairs(SPEC_ROWS) do
                if row[3] then
                    local key = 'uikit.selftest.' .. row[1]
                    assert.is_string(Locales[lang][key], lang .. ' ' .. key)
                    assert.are.equal(Locales[lang][key], metas['aeterna_uikit.' .. row[1]].expect)
                    assert.is_true(utf8.len(Locales[lang][key]) <= 240, key)
                end
            end
        end
    end)

    it('maps a full name back to its row only for this resource', function()
        local _, S = loadModules()
        assert.are.equal('spec_limits', S.shortName('aeterna_uikit.spec_limits'))
        assert.is_nil(S.shortName('aeterna_uikit.nope'))
        assert.is_nil(S.shortName('aeterna_notify.spec_limits'))
        assert.is_nil(S.shortName(nil))
    end)
end)

describe('aeterna_uikit self-tests: headless checks', function()
    it('spec_limits passes on the real validator', function()
        local L, S = loadModules()
        local ok, detail = S.run('spec_limits', L)
        assert.is_true(ok, detail)
    end)

    it('spec_limits fails and names the case when the validator lets an over-limit spec through', function()
        local L, S = loadModules()
        local ok, detail = S.run('spec_limits', broken(L, 'validateSpec', function(spec) return true, nil, spec end))
        assert.is_false(ok)
        assert.matches('41 blocks', detail, 1, true)
    end)

    it('values_recheck passes on the real validator', function()
        local L, S = loadModules()
        local ok, detail = S.run('values_recheck', L)
        assert.is_true(ok, detail)
    end)

    it('values_recheck fails when values are not re-checked', function()
        local L, S = loadModules()
        local ok, detail = S.run('values_recheck', broken(L, 'validateAction', function(panel, payload)
            return true, nil, { owner = panel.owner, panelId = panel.panelId, action = payload.action, values = payload.values }
        end))
        assert.is_false(ok)
        assert.matches('slider off the step grid', detail, 1, true)
    end)

    it('forged_action passes on the real validator', function()
        local L, S = loadModules()
        local ok, detail = S.run('forged_action', L)
        assert.is_true(ok, detail)
    end)

    it('forged_action fails when an action outside the spec is accepted', function()
        local L, S = loadModules()
        local ok, detail = S.run('forged_action', broken(L, 'validateAction', function(panel, payload)
            if type(panel) ~= 'table' then return false, 'panel: closed' end
            return true, nil, { owner = panel.owner, panelId = panel.panelId, action = payload.action, values = {} }
        end))
        assert.is_false(ok)
        assert.matches('action not in the spec', detail, 1, true)
    end)

    it('run refuses a name that is not a server check', function()
        local L, S = loadModules()
        assert.is_nil(S.run('tabs_switch', L))
    end)
end)

describe('aeterna_uikit self-tests: client test panels and judges', function()
    it('every client test panel passes the spec validator', function()
        local L, S = loadModules()
        for _, name in ipairs({ 'panel_every_block', 'tabs_switch', 'slider_keyboard', 'motion_reduced',
            'focus_lost_closes', 'overlay_pauses' }) do
            for _, lang in ipairs({ 'en', 'th' }) do
                local ok, err = L.validateSpec(S.panelSpec(name, translator(lang)))
                assert.is_true(ok, name .. ' ' .. lang .. ': ' .. tostring(err))
            end
        end
    end)

    it('panel_every_block is an md panel with tabs, a searchable list, a slider, a table and an empty state, all shown', function()
        local _, S = loadModules()
        local spec = S.panelSpec('panel_every_block', translator('en'))
        assert.are.equal('md', spec.size)
        local types, onTab = {}, {}
        for _, b in ipairs(spec.blocks) do
            types[b.type] = b
            if b.tab then onTab[b.type] = true end
        end
        assert.is_table(types.tabs)
        assert.is_truthy(types.list and types.list.search)
        assert.is_table(types.slider)
        assert.is_table(types.table)
        assert.is_table(types.empty)
        -- the eye card pauses the panel, so nothing the person must see may hide behind a tab
        assert.is_nil(onTab.list)
        assert.is_nil(onTab.slider)
        assert.is_nil(onTab.table)
        assert.is_nil(onTab.empty)
    end)

    it('judgeTabs passes when the owner gets the tab id and the right blocks show', function()
        local L, S = loadModules()
        local spec = S.panelSpec('tabs_switch', translator('en'))
        local ok, err, clean = L.validateSpec(spec)
        assert.is_true(ok, err)
        local visible = S.visibleFor(clean, S.TAB_TARGET)
        local result = { action = S.TAB_TARGET, values = { tabs = S.TAB_TARGET } }
        local pass, detail = S.judgeTabs(clean, result, { visible = visible })
        assert.is_true(pass, detail)

        assert.is_false((S.judgeTabs(clean, nil, { visible = visible })))
        assert.is_false((S.judgeTabs(clean, { action = 'tab_a', values = { tabs = 'tab_a' } }, { visible = visible })))
        assert.is_false((S.judgeTabs(clean, { action = S.TAB_TARGET, values = { tabs = 'tab_a' } }, { visible = visible })))
        assert.is_false((S.judgeTabs(clean, result, { visible = S.visibleFor(clean, 'tab_a') })))
        assert.is_false((S.judgeTabs(clean, result, nil)))
    end)

    it('visibleFor lists blocks without a tab and blocks on that tab, in order', function()
        local L, S = loadModules()
        local _, _, clean = L.validateSpec(S.panelSpec('tabs_switch', translator('en')))
        local a = table.concat(S.visibleFor(clean, 'tab_a'), ',')
        local b = table.concat(S.visibleFor(clean, 'tab_b'), ',')
        assert.are_not.equal(a, b)
        assert.matches('tabs', a, 1, true)
        assert.matches('tabs', b, 1, true)
    end)

    it('judgeSlider passes when one arrow step reaches the owner and the page shows the same number', function()
        local _, S = loadModules()
        local want = S.SLIDER.value + S.SLIDER.step
        local good = { action = 'ok', values = { vol = want } }
        local pass, detail = S.judgeSlider(good, { shown = tostring(want) })
        assert.is_true(pass, detail)
        assert.is_false((S.judgeSlider(nil, { shown = tostring(want) })))
        assert.is_false((S.judgeSlider({ action = 'ok', values = { vol = S.SLIDER.value } }, { shown = tostring(S.SLIDER.value) })))
        assert.is_false((S.judgeSlider(good, { shown = tostring(S.SLIDER.value) })))
        assert.is_false((S.judgeSlider(good, nil)))
    end)

    it('judgeResume passes only when the panel works again and is still open', function()
        local _, S = loadModules()
        assert.is_true((S.judgeResume({ paused = false, panelOpen = true })))
        assert.is_false((S.judgeResume({ paused = true, panelOpen = true })))
        assert.is_false((S.judgeResume({ paused = false, panelOpen = false })))
    end)

    it('the overlay_pauses hint says clicks do nothing while the card is up', function()
        loadModules()
        assert.matches('do nothing', Locales.en['uikit.selftest.paused_hint'], 1, true)
        assert.matches('card', Locales.en['uikit.selftest.paused_hint'], 1, true)
        assert.matches('การ์ด', Locales.th['uikit.selftest.paused_hint'], 1, true)
    end)

    it('judgeFocusLost passes only when the panel closed and the owner got __close', function()
        local _, S = loadModules()
        assert.is_true((S.judgeFocusLost({ panelOpen = false, close = { action = '__close' } })))
        assert.is_false((S.judgeFocusLost({ panelOpen = true, close = { action = '__close' } })))
        assert.is_false((S.judgeFocusLost({ panelOpen = false, close = nil })))
        assert.is_false((S.judgeFocusLost({ panelOpen = false, close = { action = 'ok' } })))
    end)
end)

describe('aeterna_uikit self-tests: wrappers', function()
    local reports

    local function coreExports()
        reports = {}
        return {
            addSelftest = function(name, meta) return name end,
            reportSelftest = function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
                return true
            end,
        }
    end

    it('the server registers all nine rows on start and answers its headless tests', function()
        local core = coreExports()
        local added = {}
        local add = core.addSelftest
        core.addSelftest = function(name, meta) added[#added + 1] = name return add(name, meta) end
        natives.reset({ side = 'server', resource = 'aeterna_uikit', exports = { aeterna_core = core } })
        rawset(_G, 'Locales', nil)
        resource.load_resource(DIR, 'server')
        assert.are.equal(9, #added)

        fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.forged_action', { kind = 'headless', side = 'server' })
        fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.toast_opts', { kind = 'headless', side = 'server' })
        assert.are.equal(1, #reports)
        assert.are.equal('aeterna_uikit.forged_action', reports[1].name)
        assert.is_true(reports[1].ok, reports[1].detail)
    end)

    it('the server drops a selftest event that does not come from aeterna_core', function()
        reports = {}
        fireAs('evil_res', 'aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.forged_action', { kind = 'headless', side = 'server' })
        assert.are.equal(0, #reports)
    end)

    describe('client', function()
        local callbacks, ui

        local function loadClient()
            local core = coreExports()
            natives.reset({ side = 'client', resource = 'aeterna_uikit', exports = { aeterna_core = core } })
            rawset(_G, 'Locales', nil)
            callbacks, ui = {}, {}
            natives.spy('RegisterNUICallback', function(name, fn) callbacks[name] = fn end)
            natives.spy('SendNUIMessage', function(msg) ui[#ui + 1] = msg end)
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterCommand')
            resource.load_resource(DIR, 'client')
        end

        local function lastUi(kind)
            for i = #ui, 1, -1 do
                if ui[i].type == kind then return ui[i] end
            end
            return nil
        end

        it('focus_lost_closes: a real focus loss closes the test panel and the owner gets __close', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.focus_lost_closes', { kind = 'ped', side = 'client' })
            natives.advance(2000)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.is_truthy(lastUi('panel:close'))
            -- nothing of the test panel reaches the server
            assert.are.equal(0, #natives.emitted('server', 'aeterna_uikit:sv:action'))
        end)

        it('tabs_switch: the page click reaches the owner with the tab id', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.tabs_switch', { kind = 'ped', side = 'client' })
            natives.advance(500)
            local drive = lastUi('selftest:drive')
            assert.is_truthy(drive)
            assert.are.equal('tab', drive.op)
            local panel = lastUi('panel:open').panel
            -- what the page would post after clicking the tab
            callbacks.panelAction({ panelId = panel.panelId, action = drive.target, values = { tabs = drive.target } }, function() end)
            local _, _, clean = UikitLogic.validateSpec({ title = 'x', blocks = panel.blocks })
            callbacks.selftestProbe({ op = 'tab', visible = UikitSelftests.visibleFor(clean, drive.target) }, function() end)
            natives.advance(500)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.are.equal(0, #natives.emitted('server', 'aeterna_uikit:sv:action'))
        end)

        it('tabs_switch fails when the page never answers', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.tabs_switch', { kind = 'ped', side = 'client' })
            natives.advance(5000)
            assert.are.equal(1, #reports)
            assert.are.equal('fail', reports[1].ok)
        end)

        it('panel_every_block opens the panel and reports ready; selftestEnd closes it', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.panel_every_block', { kind = 'eye', side = 'client' })
            natives.advance(500)
            assert.are.equal('ready', reports[1].ok)
            assert.is_truthy(lastUi('panel:open'))
            fireCore('aeterna_core:selftestEnd', 'r1-abcd', 'aeterna_uikit.panel_every_block')
            assert.is_truthy(lastUi('panel:close'))
        end)

        it('overlay_pauses logs whether the panel works again when focus resumes', function()
            loadClient()
            local infos = {}
            natives.stub('AeternaCore', {
                log = { info = function(msg, fields) infos[#infos + 1] = { msg = msg, fields = fields } end,
                    warn = function() end, debug = function() end },
                requestFocus = function() return 'tok_1' end,
                releaseFocus = function() return true end,
            })
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.overlay_pauses', { kind = 'eye', side = 'client' })
            natives.advance(100)
            fireCore('aeterna_core:focusPaused', 'aeterna_uikit', 'tok_1')
            fireCore('aeterna_core:focusResumed', 'aeterna_uikit', 'tok_1')
            assert.are.equal(1, #infos)
            assert.matches('resum', infos[1].msg)
            assert.are.equal('pass', infos[1].fields.result)
        end)

        it('drops core events that do not come from aeterna_core', function()
            loadClient()
            fireAs('evil_res', 'aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.panel_every_block', { kind = 'eye' })
            natives.advance(500)
            assert.are.equal(0, #reports)
            assert.is_nil(lastUi('panel:open'))

            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.panel_every_block', { kind = 'eye', side = 'client' })
            natives.advance(500)
            fireAs('evil_res', 'aeterna_core:selftestEnd', 'r1-abcd', 'aeterna_uikit.panel_every_block')
            fireAs('evil_res', 'aeterna_core:focusLost', 'aeterna_uikit', nil, 'preempted')
            assert.is_nil(lastUi('panel:close'))
        end)

        it('closes its test panel when aeterna_core stops', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.panel_every_block', { kind = 'eye', side = 'client' })
            natives.advance(500)
            natives.fire('onResourceStop', 'aeterna_core')
            assert.is_truthy(lastUi('panel:close'))
        end)

        it('ignores tests of other resources', function()
            loadClient()
            fireCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.toast_types', { kind = 'eye', side = 'client' })
            natives.advance(2000)
            assert.are.equal(0, #reports)
            assert.is_nil(lastUi('panel:open'))
        end)
    end)
end)
