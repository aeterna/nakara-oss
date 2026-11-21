-- notify_selftest_spec.lua -- aeterna_notify self-tests (docs/specs/aeterna_notify.md § Self-tests (0.2)): the rows
-- it registers with aeterna_core, the pure checks in shared/logic/selftests.lua, and the thin wrappers.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE = HERE .. '/../../core'

local LOGIC_FILES = {
    'shared/logic/notify.lua',
    'shared/logic/actions.lua',
    'shared/logic/countdown.lua',
    'shared/logic/history.lua',
    'shared/logic/selftests.lua',
}

local function loadModules()
    natives.reset()
    rawset(_G, 'Locales', nil)
    rawset(_G, 'NotifyLogic', nil)
    assert(loadfile(DIR .. '/locales/en.lua'))()
    assert(loadfile(DIR .. '/locales/th.lua'))()
    for i = 1, #LOGIC_FILES do
        assert(loadfile(DIR .. '/' .. LOGIC_FILES[i]))()
    end
    return NotifyLogic, NotifySelftests
end

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

local function broken(L, name, fn)
    return setmetatable({ [name] = fn }, { __index = L })
end

-- name, kind, side, has Expect
local SPEC_ROWS = {
    { 'toast_opts', 'headless', 'server', false },
    { 'merge_key', 'headless', 'server', false },
    { 'action_forged', 'headless', 'server', false },
    { 'countdown_clock', 'headless', 'server', false },
    { 'toast_types', 'eye', 'client', true },
    { 'stack_merge', 'eye', 'client', true },
    { 'action_press', 'ped', 'client', true },
    { 'sound_plays', 'eye', 'client', true },
    { 'countdown_banner', 'eye', 'client', true },
    { 'history_pull', 'headless', 'client', false },
    { 'motion_reduced', 'eye', 'client', true },
}

describe('aeterna_notify self-tests: rows', function()
    it('registers exactly the spec rows, in order, with core-valid meta', function()
        local _, S = loadModules()
        local normalize = coreNormalize()
        local added = {}
        S.register(function(name, meta) added[#added + 1] = { name = name, meta = meta } return name end, translator('en'))
        assert.are.equal(#SPEC_ROWS, #added)
        for i, row in ipairs(SPEC_ROWS) do
            assert.are.equal('aeterna_notify.' .. row[1], added[i].name)
            local fields, err = normalize(added[i].meta)
            assert.is_nil(err, row[1])
            assert.are.equal(row[2], fields.kind, row[1])
            assert.are.equal(row[3], fields.side, row[1])
            assert.are.equal(1, fields.players, row[1])
            assert.is_false(fields.destructive, row[1])
            assert.are.equal(5000, fields.timeout, row[1])
            assert.is_nil(fields.ask, row[1])
            assert.is_nil(fields.skipWhen, row[1])
            if row[4] then
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
                if row[4] then
                    local key = 'notify.selftest.' .. row[1]
                    assert.is_string(Locales[lang][key], lang .. ' ' .. key)
                    assert.are.equal(Locales[lang][key], metas['aeterna_notify.' .. row[1]].expect)
                    assert.is_true(utf8.len(Locales[lang][key]) <= 240, key)
                end
            end
        end
    end)

    it('skips only for the reasons the spec lists', function()
        local _, S = loadModules()
        assert.are.equal('Config.sound.enabled = false', S.skipReason('sound_plays', { sound = { enabled = false } }))
        assert.is_nil(S.skipReason('sound_plays', { sound = { enabled = true } }))
        assert.are.equal('Config.history.max = 0', S.skipReason('history_pull', { history = { max = 0 } }))
        assert.is_nil(S.skipReason('history_pull', { history = { max = 50 } }))
        for _, row in ipairs(SPEC_ROWS) do
            if row[1] ~= 'sound_plays' and row[1] ~= 'history_pull' then
                assert.is_nil(S.skipReason(row[1], { sound = { enabled = false }, history = { max = 0 } }), row[1])
            end
        end
    end)

    it('maps a full name back to its row only for this resource', function()
        local _, S = loadModules()
        assert.are.equal('merge_key', S.shortName('aeterna_notify.merge_key'))
        assert.is_nil(S.shortName('aeterna_uikit.merge_key'))
        assert.is_nil(S.shortName('aeterna_notify.nope'))
    end)
end)

describe('aeterna_notify self-tests: headless checks', function()
    for _, name in ipairs({ 'toast_opts', 'merge_key', 'action_forged', 'countdown_clock' }) do
        it(name .. ' passes on the real logic', function()
            local L, S = loadModules()
            local ok, detail = S.run(name, L)
            assert.is_true(ok, detail)
        end)
    end

    it('toast_opts fails when a third action is kept', function()
        local L, S = loadModules()
        local ok, detail = S.run('toast_opts', broken(L, 'validateToastOpts', function(opts, cfg, warn)
            local okT, errT, clean = L.validateToastOpts(opts, cfg, warn)
            if okT and opts.actions and not clean.actions then
                clean.actions = opts.actions
            end
            return okT, errT, clean
        end))
        assert.is_false(ok)
        assert.matches('three actions', detail, 1, true)
    end)

    it('merge_key fails when identical toasts stack', function()
        local L, S = loadModules()
        local ok, detail = S.run('merge_key', broken(L, 'createToastQueue', function(cfg)
            local c = {}
            for k, v in pairs(cfg) do c[k] = v end
            c.merge = false
            return L.createToastQueue(c)
        end))
        assert.is_false(ok)
        assert.matches('same toast twice', detail, 1, true)
    end)

    it('action_forged fails when a press for an unknown toast is accepted', function()
        local L, S = loadModules()
        local ok, detail = S.run('action_forged', broken(L, 'createActionTracker', function(opts)
            local tr = L.createActionTracker(opts)
            tr.press = function(_, _, toastId, action) return true, { owner = 'x', toastId = toastId, action = action } end
            return tr
        end))
        assert.is_false(ok)
        assert.matches('unknown toastId', detail, 1, true)
    end)

    it('countdown_clock fails when a 9-second countdown starts', function()
        local L, S = loadModules()
        local ok, detail = S.run('countdown_clock', broken(L, 'createCountdown', function(deps)
            local cd = L.createCountdown(deps)
            local start = cd.start
            cd.start = function(self, opts, now, owner)
                if type(opts) == 'table' and opts.seconds == 9 then return 'c9' end
                return start(self, opts, now, owner)
            end
            return cd
        end))
        assert.is_false(ok)
        assert.matches('9 seconds', detail, 1, true)
    end)

    it('run returns nil for a client test', function()
        local L, S = loadModules()
        assert.is_nil(S.run('toast_types', L))
    end)
end)

describe('aeterna_notify self-tests: client plans and judges', function()
    it('soundPlan plays each type once with the player setting on, then once each with it off', function()
        local _, S = loadModules()
        local plan = S.soundPlan()
        assert.are.equal(8, #plan)
        local seen = {}
        for i, step in ipairs(plan) do
            assert.are.equal(i <= 4, step.playerOn)
            seen[step.type .. tostring(step.playerOn)] = true
            assert.is_true(step.delayMs >= 1000, 'steps are apart so each sound is heard')
        end
        for _, ty in ipairs({ 'info', 'success', 'warning', 'error' }) do
            assert.is_true(seen[ty .. 'true'])
            assert.is_true(seen[ty .. 'false'])
        end
    end)

    it('countdownPlan shows at the start, again at each mark, and ends at zero', function()
        local L, S = loadModules()
        local plan = S.countdownPlan(L, 30, { 600, 300, 60, 30, 10 })
        assert.are.equal(30000, plan.endMs)
        assert.are.same({ { atMs = 0, remainingMs = 30000 }, { atMs = 20000, remainingMs = 10000 } }, plan.shows)
    end)

    it('judgeActionPress passes only for the first action with the toast gone', function()
        local _, S = loadModules()
        assert.is_true((S.judgeActionPress({ action = 'first' }, false, 'first')))
        assert.is_false((S.judgeActionPress(nil, false, 'first')))
        assert.is_false((S.judgeActionPress({ action = 'second' }, false, 'first')))
        assert.is_false((S.judgeActionPress({ action = 'first' }, true, 'first')))
    end)

    it('historyCheck passes on the real history and fails when a merge adds an entry', function()
        local L, S = loadModules()
        local ok, detail = S.historyCheck(L, 50)
        assert.is_true(ok, detail)
        local ok2, detail2 = S.historyCheck(broken(L, 'createHistory', function(max)
            local h = L.createHistory(max)
            local upsert = h.upsert
            local n = 0
            h.upsert = function(self, e)
                n = n + 1
                local copy = {}
                for k, v in pairs(e) do copy[k] = v end
                copy.id = tostring(e.id) .. '#' .. n
                return upsert(self, copy)
            end
            return h
        end), 50)
        assert.is_false(ok2)
        assert.is_string(detail2)
    end)

    it('historyShape checks newest first, the limit and the entry fields', function()
        local _, S = loadModules()
        local e = function(id, at) return { id = id, owner = 'r', kind = 'toast', type = 'info', title = 't', count = 1, at = at } end
        assert.is_true((S.historyShape({ e('b', 20), e('a', 10) }, 5)))
        assert.is_true((S.historyShape({}, 5)))
        assert.is_false((S.historyShape({ e('a', 10), e('b', 20) }, 5)))
        assert.is_false((S.historyShape({ e('a', 30), e('b', 20), e('c', 10) }, 2)))
        assert.is_false((S.historyShape({ { id = 'x' } }, 5)))
        assert.is_false((S.historyShape(nil, 5)))
    end)
end)

describe('aeterna_notify self-tests: wrappers', function()
    local reports

    local function coreExports()
        reports = {}
        return {
            addSelftest = function(name) return name end,
            reportSelftest = function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
                return true
            end,
        }
    end

    local function coreStub()
        return {
            log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
            t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
            rateLimit = function() return true end,
            time = { now = function() return 1700000000 end },
            kvp = { get = function(_, _, d) return d end, set = function() end },
            key = function() end,
        }
    end

    it('the server registers all eleven rows on start and answers its headless tests', function()
        local core = coreExports()
        local added = {}
        core.addSelftest = function(name) added[#added + 1] = name return name end
        natives.reset({ side = 'server', resource = 'aeterna_notify', exports = { aeterna_core = core } })
        rawset(_G, 'Locales', nil)
        natives.spy('RegisterCommand')
        natives.stub('AeternaCore', coreStub())
        resource.load_resource(DIR, 'server')
        assert.are.equal(11, #added)

        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.countdown_clock', { kind = 'headless', side = 'server' })
        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.history_pull', { kind = 'headless', side = 'client' })
        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_uikit.spec_limits', { kind = 'headless', side = 'server' })
        assert.are.equal(1, #reports)
        assert.are.equal('aeterna_notify.countdown_clock', reports[1].name)
        assert.is_true(reports[1].ok, reports[1].detail)
    end)

    describe('client', function()
        local commands, ui

        local function loadClient(cfg)
            local core = coreExports()
            natives.reset({ side = 'client', resource = 'aeterna_notify', exports = { aeterna_core = core } })
            rawset(_G, 'Locales', nil)
            rawset(_G, 'Config', nil)
            commands, ui = {}, {}
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.spy('RegisterNUICallback')
            natives.spy('SendNUIMessage', function(msg) ui[#ui + 1] = msg end)
            natives.spy('LoadResourceFile', function() return nil end)
            natives.spy('PlaySoundFrontend')
            natives.stub('AeternaCore', coreStub())
            resource.load_resource(DIR, 'client')
            for section, values in pairs(cfg or {}) do
                for k, v in pairs(values) do Config[section][k] = v end
            end
        end

        local function count(kind)
            local n = 0
            for _, m in ipairs(ui) do if m.type == kind then n = n + 1 end end
            return n
        end

        local function fire(short, kind, side)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.' .. short, { kind = kind, side = side or 'client' })
        end

        it('history_pull passes and leaves the player history as it was', function()
            loadClient()
            local before = #exports.aeterna_notify:history()
            fire('history_pull', 'headless')
            natives.advance(100)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.are.equal(before, #exports.aeterna_notify:history())
        end)

        it('history_pull skips when history is off', function()
            loadClient({ history = { max = 0 } })
            fire('history_pull', 'headless')
            natives.advance(100)
            assert.are.equal('skip', reports[1].ok)
            assert.are.equal('Config.history.max = 0', reports[1].detail)
        end)

        it('sound_plays skips while the owner keeps sound off', function()
            loadClient()
            fire('sound_plays', 'eye')
            natives.advance(100)
            assert.are.equal('skip', reports[1].ok)
            assert.are.equal('Config.sound.enabled = false', reports[1].detail)
            assert.are.equal(0, #natives.calls('PlaySoundFrontend'))
        end)

        it('sound_plays with sound allowed plays the four sounds once, then none, and stays out of history', function()
            loadClient({ sound = { enabled = true } })
            fire('sound_plays', 'eye')
            natives.advance(20000)
            assert.are.equal('ready', reports[1].ok)
            assert.are.equal(4, #natives.calls('PlaySoundFrontend'))
            assert.are.equal(8, count('toast:add'))
            assert.are.equal(0, #exports.aeterna_notify:history())
        end)

        it('action_press: the first action reaches the test and the toast closes', function()
            loadClient()
            fire('action_press', 'ped')
            natives.advance(2000)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.are.equal(1, count('toast:clear'))
            assert.are.equal(0, #natives.emitted('server', 'aeterna_notify:sv:action'))
        end)

        it('action_press presses its own toast even when a newer toast with actions arrives', function()
            loadClient()
            fire('action_press', 'ped')
            natives.advance(100)
            natives.stub('GetInvokingResource', function() return 'my_job' end)
            exports.aeterna_notify:notify({ title = 'Newer', actions = { { id = 'ok', label = 'OK' } } })
            natives.advance(2000)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            local presses = natives.emitted('local', 'aeterna_notify:action')
            assert.are.equal(1, #presses)
            assert.are.equal('st_action', presses[1].args[1].toastId)
        end)

        it('toast_types shows four toasts and clears them when the test ends', function()
            loadClient()
            fire('toast_types', 'eye')
            natives.advance(100)
            assert.are.equal('ready', reports[1].ok)
            assert.are.equal(4, count('toast:add'))
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', 'aeterna_notify.toast_types')
            assert.are.equal(4, count('toast:clear'))
            assert.are.equal(0, #exports.aeterna_notify:history())
        end)

        it('stack_merge sends one toast and five merges', function()
            loadClient()
            fire('stack_merge', 'eye')
            natives.advance(100)
            assert.are.equal('ready', reports[1].ok)
            assert.are.equal(1, count('toast:add'))
            assert.are.equal(5, count('toast:merge'))
        end)

        it('countdown_banner shows the banner, again at the mark, and hides it at zero', function()
            loadClient()
            fire('countdown_banner', 'eye')
            natives.advance(100)
            assert.are.equal('ready', reports[1].ok)
            assert.are.equal(1, count('countdown:show'))
            natives.advance(20000)
            assert.are.equal(2, count('countdown:show'))
            natives.advance(10000)
            assert.is_true(count('countdown:hide') >= 1)
            assert.are.equal(0, #exports.aeterna_notify:history())
        end)
    end)
end)
