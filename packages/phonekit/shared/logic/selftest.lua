-- selftest.lua -- Pure rules for the aeterna_phonekit self-tests (spec § Self-tests (0.2)): the rows registered
-- with aeterna_core, the config-based skip of each row, and the pass rule and detail text of each check.
-- Natives-free so stock Lua can test it; the wrappers in server/main.lua and client/main.lua stay thin.

PhoneSelftest = {}
local P = PhoneSelftest

P.MODEL_ORDER = { 'keypad', 'burner', 'qwerty', 'slab', 'fold', 'pro', 'book', 'pad' }
P.BUILTINS = { 'calculator', 'notes', 'contacts', 'settings' }
-- Rows of the spec table this package cannot build as written (reported, not registered).
P.NOT_BUILT = { 'eye_battery_dead' }
-- Page-only ids the client tests draw with; nothing on the server knows them.
P.APP_ID = 'aeterna_phonekit_selftest'
P.RING_ID = 'selftest'

local function num(v)
    return ('%.14g'):format(v)
end

-- The spec table, in order. `t(key, vars)` translates; `labelOf(id)` = the model's display name.
function P.rows(owner, t, labelOf)
    local out = {}
    local function row(id, meta)
        out[#out + 1] = { name = owner .. '.' .. id, meta = meta }
    end
    local function plain(kind, destructive)
        return { kind = kind, players = 1, destructive = destructive == true }
    end
    local function eye(key, vars)
        return { kind = 'eye', players = 1, destructive = false, expect = t('phonekit.selftest.expect.' .. key, vars) }
    end
    row('rules_loaded', plain('headless'))
    row('models_have_apps', plain('headless'))
    row('battery_drain_tick', plain('headless'))
    row('battery_zero_closes_all', plain('mock', true))
    row('battery_kvp_roundtrip', plain('mock', true))
    row('stale_pulse_is_off', plain('headless'))
    row('gate_items_silence_denies', plain('mock'))
    row('open_close_prop', plain('ped'))
    row('fold_keeps_screen', plain('ped'))
    row('clamp_on_unfold', plain('ped'))
    row('exit_contract', plain('ped'))
    for _, id in ipairs(P.MODEL_ORDER) do
        row('eye_model_' .. id, eye('model', { model = labelOf(id) }))
    end
    row('eye_book_two_pane', eye('book_two_pane'))
    row('eye_fold_cover', eye('fold_cover'))
    row('eye_lock', eye('lock'))
    row('eye_control_centre', eye('control_centre'))
    row('ring_cover', eye('ring_cover'))
    row('contacts_hooks', { kind = 'mock', side = 'client', players = 1, destructive = false })
    return out
end

-- The short name of a test of this resource ('rules_loaded'), or nil for another resource's test.
function P.shortName(owner, name)
    if type(name) ~= 'string' or name:sub(1, #owner + 1) ~= owner .. '.' then return nil end
    return name:sub(#owner + 2)
end

-- env = { battery, mode, lockScreen, cover, model (held), ped }. Returns the SKIP reason or nil.
function P.skipReason(short, env)
    if not env.battery and (short == 'battery_drain_tick' or short == 'battery_zero_closes_all'
        or short == 'stale_pulse_is_off') then
        return 'Config.battery is false'
    end
    if short == 'battery_kvp_roundtrip' and env.mode == 'items' then return "Config.devices is 'items'" end
    if short == 'gate_items_silence_denies' and env.mode == 'single' then return "Config.devices is 'single'" end
    if short == 'open_close_prop' and not env.ped then return 'presser not spawned' end
    if short == 'fold_keeps_screen' then
        local folds = env.model == 'book' or (env.model == 'fold' and env.cover ~= false)
        if not folds then return 'held model does not fold' end
    end
    if short == 'clamp_on_unfold' and env.model ~= 'book' then return 'held model is not book' end
    if short == 'eye_lock' and env.lockScreen ~= true then return 'Config.lockScreen is false' end
    if short == 'ring_cover' then
        if env.model ~= 'fold' then return 'held model is not fold' end
        if env.cover == false then return 'Config.cover is false' end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Server checks
--------------------------------------------------------------------------------

-- env = { mode, singleModel, models (DeviceLogic.MODELS), batteryOn, battery (validated config or false) }
function P.rulesLoaded(env)
    local count = 0
    for _, id in ipairs(P.MODEL_ORDER) do
        local m = type(env.models) == 'table' and env.models[id]
        if type(m) == 'table' and (tonumber(m.w) or 0) > 0 and (tonumber(m.h) or 0) > 0 then count = count + 1 end
    end
    if count ~= #P.MODEL_ORDER then return false, ('models: %d of %d'):format(count, #P.MODEL_ORDER) end
    if env.mode ~= 'single' and env.mode ~= 'items' then return false, 'mode: unknown' end
    if not env.models[env.singleModel] then return false, 'singleModel: not a model id' end
    local cfg = env.battery
    if env.batteryOn then
        if type(cfg) ~= 'table' or type(cfg.tickSec) ~= 'number' or cfg.tickSec < 5 or cfg.tickSec > 60 then
            return false, 'battery: config did not load'
        end
    elseif cfg ~= false then
        return false, 'battery: on although Config.battery is false'
    end
    return true, ('mode %s · model %s · battery %s · %d models'):format(env.mode, env.singleModel,
        env.batteryOn and 'on' or 'off', count)
end

-- `resolve(id)` = the resolved model ({ label, apps }). Lists how many built-in apps each model draws.
function P.modelsHaveApps(D, resolve)
    local parts = {}
    for _, id in ipairs(P.MODEL_ORDER) do
        local info = resolve(id)
        if type(info.label) ~= 'string' or info.label == '' then return false, id .. ': no label' end
        local spec = D.parseAppSpec(info.apps)
        local n = 0
        for _, app in ipairs(P.BUILTINS) do
            if D.isAppAllowed(spec, app, nil, id) then n = n + 1 end
        end
        if not D.isAppAllowed(spec, 'settings', nil, id) then return false, id .. ': settings missing' end
        parts[#parts + 1] = id .. ' ' .. n
    end
    return true, table.concat(parts, ' · ')
end

local function fakeTick(B, cfg, screen, pulseAge)
    local st = B.createState(100)
    B.advance(st, 60, { chargers = {}, inVehicle = false, screen = screen, pulseAge = pulseAge, call = false,
        multiplier = 1 }, cfg)
    return st.pct
end

-- One minute on a fake in-memory slab with the screen on: 100 - (standby + screen).
function P.drainTick(B, cfg)
    local want = 100 - (cfg.standby + cfg.screen)
    local got = fakeTick(B, cfg, 'on', 0)
    if math.abs(got - want) > 1e-6 then return false, ('expected %s %%, got %s %%'):format(num(want), num(got)) end
    return true, ('100 → %s %% in 60 s (screen on, slab)'):format(num(got))
end

-- A screen pulse older than pulseTtlSec drains like the screen off (standby only).
function P.stalePulse(B, cfg)
    local stale = fakeTick(B, cfg, 'on', cfg.pulseTtlSec + 1)
    local off = fakeTick(B, cfg, 'off', 0)
    if math.abs(stale - off) > 1e-6 then
        return false, ('stale pulse drained %s %%/min, off drains %s'):format(num(100 - stale), num(100 - off))
    end
    return true, ('stale pulse drained %s %%/min, as off'):format(num(100 - stale))
end

-- A made-up items-mode check that nobody answers: the timeout must deny with nodevice. The live gate is untouched.
function P.silenceDenies(L)
    local mgr = L.createOpeningCheckManager({})
    local got
    local id = mgr:createCheck(0, function(_, allowed, reason) got = { allowed = allowed, reason = reason } end,
        { silenceDenies = true, silenceReason = 'phonekit.refused.nodevice' })
    mgr:handleTimeout(id)
    if not got then return false, 'the check never resolved' end
    if got.allowed ~= false then return false, 'silence allowed the phone' end
    if got.reason ~= 'phonekit.refused.nodevice' then return false, 'silence denied with ' .. tostring(got.reason) end
    return true, 'silence denied with phonekit.refused.nodevice'
end

-- r = { dead, device (device() still returns one), open (phone open on the server), screens, powerOff }
function P.zeroClosed(r)
    if not r.dead then return false, 'battery not dead at 0 %' end
    if not r.powerOff then return false, 'no power off sent' end
    if r.device then return false, 'device() still returns a phone' end
    if r.screens then return false, 'an app screen is still open' end
    if r.open then return false, 'phone still open' end
    return true, 'at 0 %: power off, no device, no screen, phone closed'
end

function P.kvpRoundtrip(sample, back)
    if type(back) ~= 'table' then return false, 'nothing read back' end
    if back.battery ~= sample.battery then return false, 'read back battery ' .. tostring(back.battery) end
    if back.fold ~= sample.fold then return false, 'read back fold ' .. tostring(back.fold) end
    return true, 'wrote and read back the device KVP'
end

--------------------------------------------------------------------------------
-- Client checks
--------------------------------------------------------------------------------

local function notOpened(r)
    return false, 'phone did not open: ' .. tostring(r.reason or 'timeout')
end

-- r = { opened, reason, animation, prop (a prop existed while open), attached, gone (no prop after close) }
function P.propResult(r)
    if not r.opened then return notOpened(r) end
    if r.animation then
        if not r.prop then return false, 'no prop while open' end
        if not r.attached then return false, 'prop is not attached to the ped' end
    elseif r.prop then
        return false, 'prop shown with Config.animation off'
    end
    if not r.gone then return false, 'prop left after close' end
    if not r.animation then return true, 'Config.animation is off: no prop' end
    return true, 'prop attached while open, gone after close'
end

-- r = { opened, expected, before (top screen after showing it), after (top after fold and unfold) }
function P.foldKept(r)
    if not r.opened then return notOpened(r) end
    if r.before ~= r.expected then return false, 'step 1: top is ' .. tostring(r.before or 'home') end
    if r.after ~= r.expected then return false, 'step 2: top is ' .. tostring(r.after or 'home') end
    return true, r.expected .. ' on top after fold and unfold'
end

-- r = { opened, fold, rect = { x, y, w, h }, vw, vh } read from the page after unfolding the book.
function P.clampInside(r)
    if not r.opened then return notOpened(r) end
    if r.fold ~= 'open' or type(r.rect) ~= 'table' then return false, 'frame did not unfold' end
    local x, y, w, h = r.rect.x, r.rect.y, r.rect.w, r.rect.h
    local size = ('%dx%d'):format(math.floor(w + 0.5), math.floor(h + 0.5))
    local view = ('%dx%d'):format(math.floor(r.vw + 0.5), math.floor(r.vh + 0.5))
    local e = 0.5
    if x < -e or y < -e or x + w > r.vw + e or y + h > r.vh + e then
        return false, ('open frame %s at %d,%d leaves %s'):format(size, math.floor(x + 0.5), math.floor(y + 0.5), view)
    end
    return true, ('open frame %s inside %s'):format(size, view)
end

-- r = { opened, escClosed, reopenIgnored, keyCode (bound open key or nil), keyClosed }
function P.exitResult(r)
    if not r.opened then return notOpened(r) end
    if not r.escClosed then return false, 'step 1: ESC did not close' end
    if not r.reopenIgnored then return false, 'step 2: reopen within 300 ms was not ignored' end
    if r.keyCode and not r.keyClosed then return false, 'step 3: ' .. r.keyCode .. ' did not close' end
    return true, 'ESC closes; reopen within 300 ms ignored; '
        .. (r.keyCode and (r.keyCode .. ' closes') or 'no key bound')
end

-- r = { added, reason, found, changes, restored }
function P.contactsResult(r)
    if not r.added then return false, 'addContact refused: ' .. tostring(r.reason) end
    if not r.found then return false, 'getContacts does not list the new contact' end
    if r.changes ~= 1 then return false, ('contactsChanged fired %d times'):format(r.changes or 0) end
    if not r.restored then return false, 'contact list not restored' end
    return true, 'addContact added, contactsChanged once, list restored'
end

return PhoneSelftest
