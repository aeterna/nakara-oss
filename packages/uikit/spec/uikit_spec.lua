-- uikit_spec.lua -- aeterna_uikit: pure logic in shared/logic/uikit.lua + server/client resource harness tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function validFullSpec()
    return {
        title = 'Vehicle Shop',
        subtitle = 'Choose a configuration',
        size = 'md',
        blocks = {
            { id = 'intro', type = 'text', label = 'Welcome to the shop' },
            {
                id = 'pick',
                type = 'list',
                items = {
                    { id = 'sedan', label = 'Sedan', meta = '4 doors', icon = 'car', disabled = false },
                    { id = 'truck', label = 'Truck', meta = 'Heavy', icon = 'wrench', disabled = true },
                },
            },
            {
                id = 'qty',
                type = 'field',
                label = 'Quantity',
                input = 'number',
                value = 1,
                min = 1,
                max = 100,
            },
            {
                id = 'note',
                type = 'field',
                label = 'Note',
                input = 'text',
                value = '',
                maxLen = 10,
                placeholder = 'Optional note',
            },
            { id = 'on', type = 'toggle', label = 'Insurance', value = false },
            {
                id = 'mode',
                type = 'select',
                label = 'Payment',
                options = {
                    { id = 'cash', label = 'Cash' },
                    { id = 'bank', label = 'Bank' },
                },
                value = 'cash',
            },
            { id = 'load', type = 'progress', label = 'Stock level', value = 0.4 },
            { id = 'sep', type = 'divider' },
            {
                id = 'act',
                type = 'buttons',
                items = {
                    { id = 'ok', label = 'Buy', variant = 'primary' },
                    { id = 'cancel_btn', label = 'Back', variant = 'secondary' },
                },
            },
        },
    }
end

describe('aeterna_uikit', function()
    describe('1. spec validation (shared/logic/uikit.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
        end)

        it('passes a full valid spec with all block types', function()
            local ok, err, clean = L.validateSpec(validFullSpec())
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.equal('Vehicle Shop', clean.title)
            assert.are.equal('md', clean.size)
            assert.are.equal(9, #clean.blocks)
        end)

        it('fails when title exceeds 60 characters with title path', function()
            local s = validFullSpec()
            s.title = string.rep('a', 61)
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^title:'))
        end)

        it('fails when blocks exceed 40 items with blocks path', function()
            local s = validFullSpec()
            s.blocks = {}
            for i = 1, 41 do
                s.blocks[i] = { id = 'b_' .. i, type = 'divider' }
            end
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks:'))
        end)

        it('fails when list items exceed 50 with blocks[i].items path', function()
            local items = {}
            for i = 1, 51 do
                items[i] = { id = 'item_' .. i, label = 'Item ' .. i }
            end
            local s = {
                title = 'List limit',
                size = 'md',
                blocks = {
                    { id = 'pick', type = 'list', items = items },
                },
            }
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.items:'))
        end)

        it('fails when buttons exceed 4 with blocks[i].items path', function()
            local btns = {}
            for i = 1, 5 do
                btns[i] = { id = 'btn_' .. i, label = 'B' .. i, variant = 'primary' }
            end
            local s = {
                title = 'Buttons limit',
                size = 'sm',
                blocks = {
                    { id = 'act', type = 'buttons', items = btns },
                },
            }
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.items:'))
        end)

        it('fails on duplicate id with .id path', function()
            local s = {
                title = 'Dup test',
                size = 'sm',
                blocks = {
                    { id = 'same', type = 'divider' },
                    { id = 'same', type = 'divider' },
                },
            }
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[2%]%.id:'))
        end)

        it('fails on unknown icon name with .icon path', function()
            local s = {
                title = 'Icon test',
                size = 'sm',
                blocks = {
                    {
                        id = 'pick',
                        type = 'list',
                        items = {
                            { id = 'a', label = 'Row', icon = 'nonexistent-icon' },
                        },
                    },
                },
            }
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.items%[1%]%.icon:'))
        end)

        it('fails on unknown block type with .type path', function()
            local s = {
                title = 'Type test',
                size = 'sm',
                blocks = {
                    { id = 'bad', type = 'chart', label = 'Invalid' },
                },
            }
            local ok, err = L.validateSpec(s)
            assert.is_false(ok)
            assert.is_truthy(err and err:match('^blocks%[1%]%.type:'))
        end)
    end)

    describe('2. action filter (shared/logic/uikit.lua)', function()
        local L, pm, panelId
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
            pm = L.createPanelManager()
            panelId = assert(pm:open(1, 'test_owner', validFullSpec()))
        end)

        it('passes a valid button id or list item id from the open spec', function()
            local ok, err, res = pm:handleAction(1, {
                panelId = panelId,
                action = 'ok',
                values = { qty = 5, note = 'hello', on = true, mode = 'bank' },
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.equal('ok', res.action)
            assert.are.equal('test_owner', res.owner)

            local ok2, _, res2 = pm:handleAction(1, {
                panelId = panelId,
                action = 'sedan',
                values = {},
            })
            assert.is_true(ok2)
            assert.are.equal('sedan', res2.action)
        end)

        it('drops an action id not in the spec or a disabled item', function()
            local ok, err = pm:handleAction(1, {
                panelId = panelId,
                action = 'not_in_spec',
                values = {},
            })
            assert.is_false(ok)
            assert.is_truthy(err)

            local okDisabled = pm:handleAction(1, {
                panelId = panelId,
                action = 'truck',
                values = {},
            })
            assert.is_false(okDisabled)
        end)

        it('drops an action for a closed panel or mismatched panelId', function()
            local okWrongId = pm:handleAction(1, {
                panelId = 'p999',
                action = 'ok',
                values = {},
            })
            assert.is_false(okWrongId)

            pm:close(1, panelId)
            local okClosed = pm:handleAction(1, {
                panelId = panelId,
                action = 'ok',
                values = {},
            })
            assert.is_false(okClosed)
        end)

        it('always passes __close for the open panel and closes it', function()
            local ok, err, res = pm:handleAction(1, {
                panelId = panelId,
                action = '__close',
                values = {},
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.equal('__close', res.action)
            assert.is_nil(pm:isOpen(1))
        end)
    end)

    describe('3. values validation and cleaning (shared/logic/uikit.lua)', function()
        local L, spec
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
            local ok, _, clean = L.validateSpec(validFullSpec())
            assert.is_true(ok)
            spec = clean
        end)

        it('drops number out of range', function()
            local okLow = L.validateValues(spec, { qty = 0 })
            assert.is_false(okLow)
            local okHigh = L.validateValues(spec, { qty = 101 })
            assert.is_false(okHigh)
        end)

        it('drops string over maxLen', function()
            local ok, err = L.validateValues(spec, { note = '12345678901' })
            assert.is_false(ok)
            assert.is_truthy(err and err:match('maxLen'))
        end)

        it('drops select option not in list', function()
            local ok, err = L.validateValues(spec, { mode = 'crypto' })
            assert.is_false(ok)
            assert.is_truthy(err)
        end)

        it('drops an extra key not in field/toggle/select blocks', function()
            local okExtra = L.validateValues(spec, { unknown_field = 'abc' })
            assert.is_false(okExtra)
            local okNonInputBlock = L.validateValues(spec, { intro = 'text block is not an input' })
            assert.is_false(okNonInputBlock)
        end)

        it('passes good values with strings cleaned of control characters and trimmed', function()
            local zwsp = string.char(0xE2, 0x80, 0x8B)
            local ok, err, clean = L.validateValues(spec, {
                qty = 42,
                note = '  hi' .. zwsp .. '\nworld  ',
                on = true,
                mode = 'bank',
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.same({
                qty = 42,
                note = 'hiworld',
                on = true,
                mode = 'bank',
            }, clean)
        end)
    end)

    describe('4. update patch validation (shared/logic/uikit.lua)', function()
        local L, pm, panelId
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
            pm = L.createPanelManager()
            panelId = assert(pm:open(1, 'test_owner', validFullSpec()))
        end)

        it('accepts label, value, items and disabled changes', function()
            local ok = pm:update(1, panelId, {
                blocks = {
                    qty = { label = 'New Qty', value = 10, disabled = true },
                    pick = {
                        items = {
                            { id = 'coupe', label = 'Coupe', icon = 'car' },
                        },
                    },
                },
            })
            assert.is_true(ok)
        end)

        it('refuses fields other than label, value, items, disabled', function()
            assert.is_false(pm:update(1, panelId, {
                blocks = {
                    qty = { min = 0 },
                },
            }))
            assert.is_false(pm:update(1, panelId, {
                blocks = {
                    qty = { type = 'text' },
                },
            }))
            assert.is_false(pm:update(1, panelId, {
                blocks = {
                    mode = { options = { { id = 'a', label = 'A' } } },
                },
            }))
            assert.is_false(pm:update(1, panelId, {
                blocks = {
                    qty = { id = 'new_id' },
                },
            }))
        end)
    end)

    describe('5. menu registry (shared/logic/uikit.lua)', function()
        local L, mm, aces
        local function canFn(src, ace)
            return aces[src] and aces[src][ace] == true or false
        end

        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/uikit.lua'))()
            mm = L.createMenuManager()
            aces = {
                [1] = { ['aeterna.admin.panel'] = true },
                [2] = {},
            }
            assert(mm:add('res_b', { id = 'z_entry', label = 'Zeta', icon = 'box', order = 50 }))
            assert(mm:add('res_a', { id = 'b_entry', label = 'Beta', icon = 'user', order = 100 }))
            assert(mm:add('res_a', { id = 'a_entry', label = 'Alpha', icon = 'home', order = 100 }))
            assert(mm:add('res_a', { id = 'admin', label = 'Admin', icon = 'shield', order = 10, ace = 'aeterna.admin.panel' }))
        end)

        it('filters entries by ACE and sorts by order then label', function()
            local p1 = mm:listForPlayer(1, canFn)
            assert.are.equal(4, #p1)
            assert.are.equal('admin', p1[1].id)
            assert.are.equal('z_entry', p1[2].id)
            assert.are.equal('a_entry', p1[3].id)
            assert.are.equal('b_entry', p1[4].id)

            local p2 = mm:listForPlayer(2, canFn)
            assert.are.equal(3, #p2)
            assert.are.equal('z_entry', p2[1].id)
            assert.are.equal('a_entry', p2[2].id)
            assert.are.equal('b_entry', p2[3].id)
        end)

        it('removes an owner resource entries when that owner stops', function()
            mm:removeByOwner('res_a')
            local p1 = mm:listForPlayer(1, canFn)
            assert.are.equal(1, #p1)
            assert.are.equal('z_entry', p1[1].id)
            assert.are.equal('res_b', p1[1].owner)
        end)

        it('drops a pick for an entry the player lacks ACE for or that no longer exists', function()
            local okDenied = mm:pick(2, 'res_a', 'admin', canFn)
            assert.is_false(okDenied)

            local okAllowed, _, picked = mm:pick(1, 'res_a', 'admin', canFn)
            assert.is_true(okAllowed)
            assert.are.same({ owner = 'res_a', id = 'admin' }, picked)

            mm:remove('res_a', 'a_entry')
            local okGone = mm:pick(1, 'res_a', 'a_entry', canFn)
            assert.is_false(okGone)
        end)
    end)

    describe('6. resource scripts under harness', function()
        it('runs server exports, rate limits net events, and fires local action/menu events', function()
            natives.reset({ resource = 'aeterna_uikit', side = 'server', invoker = 'shop_res' })
            local allowedAce = false
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                text = nil,
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                rateLimit = function() return true end,
                can = function(_, ace) return ace == 'aeterna.shop.vip' and allowedAce end,
            })

            local res = resource.load_resource(DIR, 'server')
            local api = res.exports

            local pid, err = api.open(1, validFullSpec())
            assert.is_nil(err)
            assert.are.equal('p1', pid)
            assert.are.equal('p1', api.isOpen(1))

            local secondPid = api.open(1, validFullSpec())
            assert.are.equal('p2', secondPid)
            local closeEvs = natives.emitted('client', 'aeterna_uikit:cl:close')
            assert.are.equal(1, #closeEvs)
            assert.are.equal('replaced', closeEvs[1].args[1].reason)

            natives.fire_net('aeterna_uikit:sv:action', 1, {
                panelId = secondPid,
                action = 'ok',
                values = { qty = 3, on = true, mode = 'cash' },
            })
            local actEv = natives.last_emitted('local', 'aeterna_uikit:action')
            assert.is_truthy(actEv)
            assert.are.equal(1, actEv.args[1])
            assert.are.equal('ok', actEv.args[2].action)
            assert.are.equal(3, actEv.args[2].values.qty)

            api.addMenuEntry({ id = 'vip', label = 'VIP Shop', icon = 'star', order = 1, ace = 'aeterna.shop.vip' })
            natives.fire_net('aeterna_uikit:sv:menu', 1, { owner = 'shop_res', id = 'vip' })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_uikit:menu'))

            allowedAce = true
            natives.fire_net('aeterna_uikit:sv:menu', 1, { owner = 'shop_res', id = 'vip' })
            local menuEv = natives.last_emitted('local', 'aeterna_uikit:menu')
            assert.is_truthy(menuEv)
            assert.are.same({ owner = 'shop_res', id = 'vip' }, menuEv.args[2])
        end)

        it('runs client panels, focus preemption (__close), prompts and keyHints', function()
            natives.reset({ resource = 'aeterna_uikit', side = 'client' })
            local nuiCallbacks = {}
            local nuiMessages = natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback', function(name, fn)
                nuiCallbacks[name] = fn
            end)
            natives.spy('RegisterCommand')
            natives.spy('GetControlInstructionalButton', function(_, hash)
                if hash == '+aeterna_invkit_open' then return 't_E' end
                return 'b_-1'
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                key = function() end,
            })
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)

            local res = resource.load_resource(DIR, 'client')
            local api = res.exports

            -- Open panel from server, then lose focus -> sends __close to server
            natives.fire_net('aeterna_uikit:cl:open', 1, {
                panelId = 'p1',
                title = 'Test Panel',
                size = 'md',
                blocks = {},
            })
            natives.fire('aeterna_core:focusLost', 'aeterna_uikit', 'tok_1', 'preempted')
            local closeAction = natives.last_emitted('server', 'aeterna_uikit:sv:action')
            assert.is_truthy(closeAction)
            assert.are.equal('p1', closeAction.args[1].panelId)
            assert.are.equal('__close', closeAction.args[1].action)

            -- keyHints resolves bound and unbound keys
            api.keyHints({
                { key = '+aeterna_invkit_open', label = 'Open Stash' },
                { key = '+aeterna_unbound_cmd', label = 'Action' },
            })
            local lastMsg = nuiMessages[#nuiMessages][1]
            assert.are.equal('hints:show', lastMsg.type)
            assert.are.equal('E', lastMsg.hints[1].bind)
            assert.are.equal('Unbound', lastMsg.hints[2].bind)

            -- confirm prompt resolves via NUI callback promptResult
            local confirmed = nil
            CreateThread(function()
                confirmed = api.confirm({ title = 'Delete item?' })
            end)
            natives.advance(0)
            nuiCallbacks.promptResult({ kind = 'confirm', value = true }, function() end)
            natives.advance(20)
            assert.is_true(confirmed)
        end)
    end)
end)
