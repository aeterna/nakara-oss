-- notify_spec.lua -- aeterna_notify: pure logic in shared/logic/notify.lua + server/client resource harness tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

describe('aeterna_notify', function()
    describe('1. toast queue (shared/logic/notify.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/notify.lua'))()
        end)

        it('pushes out the oldest toast when a fifth toast is added', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000 })
            assert(q:push({ id = 't1', title = 'First' }))
            assert(q:push({ id = 't2', title = 'Second' }))
            assert(q:push({ id = 't3', title = 'Third' }))
            assert(q:push({ id = 't4', title = 'Fourth' }))
            assert.are.equal(4, q:count())

            local ok, err, res = q:push({ id = 't5', title = 'Fifth' })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_false(res.replaced)
            assert.is_truthy(res.evicted)
            assert.are.equal('t1', res.evicted.id)

            local list = q:list()
            assert.are.equal(4, #list)
            assert.are.equal('t2', list[1].id)
            assert.are.equal('t3', list[2].id)
            assert.are.equal('t4', list[3].id)
            assert.are.equal('t5', list[4].id)
        end)

        it('replaces in place and keeps position when a toast with the same id is added', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000 })
            assert(q:push({ id = 'a', title = 'Alpha', duration = 3000 }))
            assert(q:push({ id = 'b', title = 'Beta', duration = 3000 }))
            assert(q:push({ id = 'c', title = 'Gamma', duration = 3000 }))

            local ok, err, res = q:push({
                id = 'b',
                title = 'Beta Updated',
                description = 'New details',
                type = 'success',
                duration = 6000,
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_true(res.replaced)
            assert.are.equal(2, res.index)
            assert.is_nil(res.evicted)

            local list = q:list()
            assert.are.equal(3, #list)
            assert.are.equal('a', list[1].id)
            assert.are.equal('b', list[2].id)
            assert.are.equal('Beta Updated', list[2].title)
            assert.are.equal('New details', list[2].description)
            assert.are.equal('success', list[2].type)
            assert.are.equal(6000, list[2].duration)
            assert.are.equal('c', list[3].id)
        end)

        it('clears a single toast by id or all toasts when id is omitted', function()
            local q = L.createToastQueue({ max = 4 })
            assert(q:push({ id = 'a', title = 'One' }))
            assert(q:push({ id = 'b', title = 'Two' }))
            assert(q:push({ id = 'c', title = 'Three' }))

            assert.is_true(q:clear('b'))
            local list = q:list()
            assert.are.equal(2, #list)
            assert.are.equal('a', list[1].id)
            assert.are.equal('c', list[2].id)

            assert.is_true(q:clear())
            assert.are.equal(0, q:count())
        end)
    end)

    describe('2. toast opts validation and normalization (shared/logic/notify.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/notify.lua'))()
        end)

        it('cuts over-long title to 60 characters and over-long description to 160 characters', function()
            local longTitle = string.rep('T', 85)
            local longDesc = string.rep('D', 210)
            local ok, err, clean = L.validateToastOpts({
                title = longTitle,
                description = longDesc,
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.equal(60, #clean.title)
            assert.are.equal(string.rep('T', 60), clean.title)
            assert.are.equal(160, #clean.description)
            assert.are.equal(string.rep('D', 160), clean.description)
        end)

        it('falls back to info for unknown or missing toast type', function()
            local ok1, _, c1 = L.validateToastOpts({ title = 'Hello', type = 'unknown_type' })
            assert.is_true(ok1)
            assert.are.equal('info', c1.type)

            local ok2, _, c2 = L.validateToastOpts({ title = 'Hello' })
            assert.is_true(ok2)
            assert.are.equal('info', c2.type)

            local ok3, _, c3 = L.validateToastOpts({ title = 'Hello', type = 'warning' })
            assert.is_true(ok3)
            assert.are.equal('warning', c3.type)
        end)

        it('clamps duration to 1000-15000 ms', function()
            local okLow, _, cLow = L.validateToastOpts({ title = 'Fast', duration = 200 })
            assert.is_true(okLow)
            assert.are.equal(1000, cLow.duration)

            local okHigh, _, cHigh = L.validateToastOpts({ title = 'Slow', duration = 45000 })
            assert.is_true(okHigh)
            assert.are.equal(15000, cHigh.duration)

            local okMid, _, cMid = L.validateToastOpts({ title = 'Normal', duration = 5500 })
            assert.is_true(okMid)
            assert.are.equal(5500, cMid.duration)

            local okDef, _, cDef = L.validateToastOpts({ title = 'Default' }, { defaultDuration = 4000 })
            assert.is_true(okDef)
            assert.are.equal(4000, cDef.duration)
        end)

        it('validates icon from the uikit icon map and rejects empty title', function()
            local okIcon, _, cIcon = L.validateToastOpts({ title = 'Bell', icon = 'bell' })
            assert.is_true(okIcon)
            assert.are.equal('bell', cIcon.icon)

            local okBadIcon = L.validateToastOpts({ title = 'Bad icon', icon = 'not-an-icon' })
            assert.is_false(okBadIcon)

            local okEmpty = L.validateToastOpts({ title = '   ' })
            assert.is_false(okEmpty)
        end)
    end)

    describe('3. announce queue (shared/logic/notify.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/notify.lua'))()
        end)

        it('keeps one shown, five waiting, and drops the seventh with a warn', function()
            local warnings = {}
            local shown = {}
            local aq = L.createAnnounceQueue({
                max = 5,
                warn = function(msg, fields)
                    warnings[#warnings + 1] = { msg = msg, fields = fields }
                end,
                onShow = function(item)
                    shown[#shown + 1] = item
                end,
            })

            local ok1, err1, r1 = aq:push({ title = 'Announce 1', body = 'First' })
            assert.is_true(ok1)
            assert.is_nil(err1)
            assert.are.equal('shown', r1.status)
            assert.are.equal(1, #shown)
            assert.are.equal('Announce 1', aq:getCurrent().title)
            assert.are.equal(0, aq:waitingCount())

            for i = 2, 6 do
                local ok, err, r = aq:push({ title = 'Announce ' .. i, body = 'Waiting ' .. i })
                assert.is_true(ok)
                assert.is_nil(err)
                assert.are.equal('queued', r.status)
            end

            assert.are.equal('Announce 1', aq:getCurrent().title)
            assert.are.equal(5, aq:waitingCount())
            assert.are.equal(0, #warnings)

            local ok7, err7, r7 = aq:push({ title = 'Announce 7', body = 'Overflow' })
            assert.is_false(ok7)
            assert.is_truthy(err7)
            assert.are.equal('dropped', r7.status)
            assert.are.equal(5, aq:waitingCount())
            assert.are.equal(1, #warnings)

            -- Advancing moves the first waiting announcement into current
            local nextItem = aq:next()
            assert.is_truthy(nextItem)
            assert.are.equal('Announce 2', nextItem.title)
            assert.are.equal('Announce 2', aq:getCurrent().title)
            assert.are.equal(4, aq:waitingCount())
            assert.are.equal(2, #shown)
        end)
    end)

    describe('4. MOTD validation and display rules (shared/logic/notify.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/notify.lua'))()
        end)

        it('shows MOTD when seen ~= version and does not show when equal', function()
            local raw = json.encode({
                version = '2026-11-17',
                eyebrow = 'Message of the day',
                title = 'Welcome',
                lines = { 'Bind your phone key in Settings -> Key Bindings -> FiveM' },
                buttons = { dismiss = true },
            })
            local warnings = {}
            local ctrl = L.createMotdController({
                rawJson = raw,
                decode = json.decode,
                enabled = true,
                warn = function(msg, fields)
                    warnings[#warnings + 1] = { msg = msg, fields = fields }
                end,
            })

            assert.are.equal(0, #warnings)
            assert.is_true(ctrl:isValid())
            assert.is_true(ctrl:shouldShow(nil))
            assert.is_true(ctrl:shouldShow('2026-11-01'))
            assert.is_false(ctrl:shouldShow('2026-11-17'))
        end)

        it('disables MOTD and logs one warn when motd.json fails validation or is bad JSON', function()
            local warnings = {}
            local badJson = L.loadMotdJson('{ bad json ', json.decode, function(msg, fields)
                warnings[#warnings + 1] = { msg = msg, fields = fields }
            end)
            assert.is_nil(badJson)
            assert.are.equal(1, #warnings)

            local schemaWarnings = {}
            local tooManyLines = {}
            for i = 1, 9 do
                tooManyLines[i] = 'Line ' .. i
            end
            local badSchemaRaw = json.encode({
                version = '2026-11-17',
                eyebrow = 'MOTD',
                title = 'Welcome',
                lines = tooManyLines,
            })
            local ctrl = L.createMotdController({
                rawJson = badSchemaRaw,
                decode = json.decode,
                enabled = true,
                warn = function(msg, fields)
                    schemaWarnings[#schemaWarnings + 1] = { msg = msg, fields = fields }
                end,
            })
            assert.is_false(ctrl:isValid())
            assert.is_false(ctrl:shouldShow(nil))
            assert.is_false(ctrl:shouldShow('other'))
            assert.are.equal(1, #schemaWarnings)
            assert.is_truthy(schemaWarnings[1].fields and schemaWarnings[1].fields.path:match('^lines:'))
        end)
    end)

    describe('5. aeterna_announce command logic (shared/logic/notify.lua)', function()
        local L, translations
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/notify.lua'))()
            translations = {
                ['notify.announce.title'] = 'Announcement',
                ['notify.announce.console'] = 'Console',
                ['notify.announce.usage'] = 'Usage: aeterna_announce <text>',
                ['notify.announce.denied'] = 'You do not have permission to send announcements',
            }
        end)

        it('returns notify.announce.denied when player lacks ACE aeterna.notify.announce', function()
            local toasts = {}
            local announced = {}
            local ok, key, msg = L.handleAnnounceCommand(1, 'Server restart soon', {
                can = function() return false end,
                t = function(k) return translations[k] or k end,
                getPlayerName = function() return 'Alice' end,
                notify = function(src, opts) toasts[#toasts + 1] = { src = src, opts = opts } end,
                announce = function(opts) announced[#announced + 1] = opts; return true end,
            })
            assert.is_false(ok)
            assert.are.equal('notify.announce.denied', key)
            assert.are.equal(translations['notify.announce.denied'], msg)
            assert.are.equal(0, #announced)
            assert.are.equal(1, #toasts)
            assert.are.equal(1, toasts[1].src)
            assert.are.equal(translations['notify.announce.denied'], toasts[1].opts.title)
        end)

        it('returns notify.announce.usage on empty text', function()
            local toasts = {}
            local announced = {}
            local ok, key, msg = L.handleAnnounceCommand(1, '   ', {
                can = function() return true end,
                t = function(k) return translations[k] or k end,
                getPlayerName = function() return 'Alice' end,
                notify = function(src, opts) toasts[#toasts + 1] = { src = src, opts = opts } end,
                announce = function(opts) announced[#announced + 1] = opts; return true end,
            })
            assert.is_false(ok)
            assert.are.equal('notify.announce.usage', key)
            assert.are.equal(translations['notify.announce.usage'], msg)
            assert.are.equal(0, #announced)
            assert.are.equal(1, #toasts)
            assert.are.equal(translations['notify.announce.usage'], toasts[1].opts.title)
        end)

        it('allows console (src = 0) and authorized players to announce', function()
            local announced = {}
            local okConsole, errConsole = L.handleAnnounceCommand(0, 'Maintenance in 10m', {
                can = function() return false end,
                t = function(k) return translations[k] or k end,
                announce = function(opts) announced[#announced + 1] = opts; return true end,
            })
            assert.is_true(okConsole)
            assert.is_nil(errConsole)
            assert.are.equal(1, #announced)
            assert.are.equal('Announcement', announced[1].title)
            assert.are.equal('Maintenance in 10m', announced[1].body)
            assert.are.equal('Console', announced[1].by)

            local okAdmin = L.handleAnnounceCommand(2, 'Event starting', {
                can = function(_, ace) return ace == 'aeterna.notify.announce' end,
                t = function(k) return translations[k] or k end,
                getPlayerName = function() return 'AdminBob' end,
                announce = function(opts) announced[#announced + 1] = opts; return true end,
            })
            assert.is_true(okAdmin)
            assert.are.equal(2, #announced)
            assert.are.equal('AdminBob', announced[2].by)
        end)
    end)

    describe('6. resource scripts under harness', function()
        it('runs server notify export, announce queue, and aeterna_announce command', function()
            natives.reset({
                resource = 'aeterna_notify',
                side = 'server',
                players = { [1] = 'Alice', [2] = 'Bob' },
            })
            local commands = {}
            natives.spy('RegisterCommand', function(name, fn)
                commands[name] = fn
            end)
            local allowed = { [2] = true }
            local warnings = {}
            natives.stub('AeternaCore', {
                log = {
                    debug = function() end,
                    info = function() end,
                    warn = function(msg, fields) warnings[#warnings + 1] = { msg = msg, fields = fields } end,
                    error = function() end,
                },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                can = function(src, ace)
                    if tonumber(src) == 0 then return true end
                    return ace == 'aeterna.notify.announce' and allowed[tonumber(src)] == true
                end,
            })

            local res = resource.load_resource(DIR, 'server')
            local api = res.exports

            -- notify(src, opts) refuses -1 and sends to valid single player
            assert.is_false(api.notify(-1, { title = 'Broadcast attempt' }))
            assert.are.equal(0, #natives.emitted('client', 'aeterna_notify:cl:toast'))

            assert.is_true(api.notify(1, { title = 'Hello Alice', type = 'success', duration = 3000 }))
            local toastEvs = natives.emitted('client', 'aeterna_notify:cl:toast')
            assert.are.equal(1, #toastEvs)
            assert.are.equal(1, toastEvs[1].target)
            assert.are.equal('Hello Alice', toastEvs[1].args[1].title)

            -- aeterna_announce command: denied for player 1, usage on empty, allowed for player 2
            assert.is_function(commands.aeterna_announce)
            commands.aeterna_announce(1, { 'Illegal' }, 'aeterna_announce Illegal')
            toastEvs = natives.emitted('client', 'aeterna_notify:cl:toast')
            assert.are.equal(2, #toastEvs)
            assert.are.equal(1, toastEvs[2].target)
            assert.are.equal(Locales.en['notify.announce.denied'], toastEvs[2].args[1].title)
            assert.are.equal(0, #natives.emitted('client', 'aeterna_notify:cl:announce'))

            commands.aeterna_announce(2, {}, 'aeterna_announce   ')
            toastEvs = natives.emitted('client', 'aeterna_notify:cl:toast')
            assert.are.equal(3, #toastEvs)
            assert.are.equal(2, toastEvs[3].target)
            assert.are.equal(Locales.en['notify.announce.usage'], toastEvs[3].args[1].title)

            commands.aeterna_announce(2, { 'Weather', 'clear' }, 'aeterna_announce Weather clear')
            local annEvs = natives.emitted('client', 'aeterna_notify:cl:announce')
            assert.are.equal(1, #annEvs)
            assert.are.equal(-1, annEvs[1].target)
            assert.are.equal('Weather clear', annEvs[1].args[1].body)
            assert.are.equal('Bob', annEvs[1].args[1].by)
        end)

        it('runs client toasts, MOTD KVP persistence, and aeterna_layout protocol', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client' })
            local nuiCallbacks = {}
            local nuiMessages = natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback', function(name, fn)
                nuiCallbacks[name] = fn
            end)
            natives.spy('LoadResourceFile', function(_, path)
                if path == 'config/motd.json' then
                    return json.encode({
                        version = '2026-11-17',
                        eyebrow = 'Message of the day',
                        title = 'Welcome',
                        lines = { 'Bind your phone key in Settings -> Key Bindings -> FiveM' },
                        buttons = { dismiss = true },
                    })
                end
                return nil
            end)
            natives.spy('GetResourceState', function(resName)
                if resName == 'qbx_core' then return 'missing' end
                return 'started'
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                kvp = {
                    get = function(name, version, default)
                        local raw = natives.get_kvp('aeterna_notify:' .. name .. ':v' .. version)
                        if not raw then return default end
                        return json.decode(raw)
                    end,
                    set = function(name, version, val)
                        natives.set_kvp('aeterna_notify:' .. name .. ':v' .. version, json.encode(val))
                    end,
                },
            })
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'motd_tok' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)

            local res = resource.load_resource(DIR, 'client')
            local api = res.exports

            -- Layout add events fired on start and on aeterna_layout:hello
            local layoutAdds = natives.emitted('local', 'aeterna_layout:add')
            assert.are.equal(2, #layoutAdds)
            natives.fire('aeterna_layout:hello')
            layoutAdds = natives.emitted('local', 'aeterna_layout:add')
            assert.are.equal(4, #layoutAdds)

            -- Layout apply for own resource updates placement
            natives.fire('aeterna_layout:apply', 'aeterna_notify', 'toasts', {
                x = 0.95, y = 0.95, ax = 1, ay = 1, scale = 1.0, hidden = false,
            })

            -- Toast export and clear export
            assert.is_true(api.notify({ id = 'job', title = 'Shift started', type = 'info' }))
            api.clear('job')

            -- MOTD shown on playerSpawned when seen ~= version
            natives.fire('playerSpawned')
            local foundMotdShow = false
            for i = 1, #nuiMessages do
                if nuiMessages[i][1] and nuiMessages[i][1].type == 'motd:show' then
                    foundMotdShow = true
                end
            end
            assert.is_true(foundMotdShow)

            -- Dismiss stores version in KVP aeterna_notify:motd_seen:v1
            nuiCallbacks.motdClose({ dismiss = true }, function() end)
            assert.are.equal('"2026-11-17"', natives.get_kvp('aeterna_notify:motd_seen:v1'))

            -- Calling showMotd again when seen == version does not show it
            local countBefore = #nuiMessages
            assert.is_false(api.showMotd())
            assert.are.equal(countBefore, #nuiMessages)
        end)
    end)
end)
