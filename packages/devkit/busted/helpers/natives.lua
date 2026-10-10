-- natives.lua -- stub FiveM globals so plain resource scripts can run under busted.
--
-- FiveM resource scripts are not modules: they call CreateThread / AddEventHandler / exports / GetConvar
-- at the top level and talk to the world through globals. This helper installs those globals into _G,
-- records everything the script does (events, exports, convar writes, spied natives) and gives the spec a
-- controllable clock that drives threads, Wait() and SetTimeout().
--
--   local natives = require('helpers.natives')
--   before_each(function() natives.reset({ resource = 'my_resource', side = 'server' }) end)
--
-- Every reset() starts from a clean slate: fresh registries, clock at 0, and every global this helper
-- (or resource.lua) installed is removed first. Compatible with Lua 5.1 - 5.5.

local M = {}

local unpack = table.unpack or unpack -- luacheck: ignore 143

local installed = {}  -- global name -> true for every global we put into _G
local state           -- current registries, rebuilt on every reset()

local function set_global(name, value)
    installed[name] = true
    rawset(_G, name, value)
end

--- Remember that `name` is a global owned by the harness, so reset() removes it.
function M.track_global(name)
    installed[name] = true
end

local function pack(...)
    return { n = select('#', ...), ... }
end

local function record(list, entry)
    list[#list + 1] = entry
    return entry
end

-------------------------------------------------------------------------------------------------------
-- json: dkjson when available (it is a dependency of busted itself), else a small encoder.
-------------------------------------------------------------------------------------------------------

local function simple_encode(v, seen)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' then return tostring(v) end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if v == math.floor(v) and math.abs(v) < 2^53 then return string.format('%d', v) end
        return string.format('%.14g', v)
    end
    if t == 'string' then
        local escaped = v:gsub('[%c"\\]', function(c)
            local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or string.format('\\u%04x', c:byte())
        end)
        return '"' .. escaped .. '"'
    end
    if t == 'table' then
        seen = seen or {}
        if seen[v] then error('json.encode: cyclic table', 0) end
        seen[v] = true
        local n = #v
        local is_array = true
        for k in pairs(v) do
            if type(k) ~= 'number' or k < 1 or k > n or k ~= math.floor(k) then is_array = false break end
        end
        local parts = {}
        if is_array then
            for i = 1, n do parts[i] = simple_encode(v[i], seen) end
            seen[v] = nil
            return '[' .. table.concat(parts, ',') .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            parts[#parts + 1] = simple_encode(k, seen) .. ':' .. simple_encode(val, seen)
        end
        seen[v] = nil
        return '{' .. table.concat(parts, ',') .. '}'
    end
    error('json.encode: cannot encode ' .. t, 0)
end

local function make_json()
    local ok, dk = pcall(require, 'dkjson')
    if ok and type(dk) == 'table' then
        return {
            encode = function(v) return dk.encode(v) end,
            decode = function(s)
                local v = dk.decode(s)
                return v
            end,
            backend = 'dkjson',
        }
    end
    return {
        encode = function(v) return simple_encode(v) end,
        decode = function() error('json.decode needs dkjson (luarocks install dkjson)', 2) end,
        backend = 'simple',
    }
end

-------------------------------------------------------------------------------------------------------
-- vector3: enough for coords math. `#(a - b)` works on Lua 5.2+ only (5.1 ignores __len on tables);
-- use natives.length(v) in specs that must also run on 5.1.
-------------------------------------------------------------------------------------------------------

local vec_mt = {}
vec_mt.__index = vec_mt

local function vector3(x, y, z)
    if type(x) == 'table' then x, y, z = x.x, x.y, x.z end
    return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vec_mt)
end

local function as_vec(v)
    if type(v) == 'number' then return { x = v, y = v, z = v } end
    return v
end

vec_mt.__add = function(a, b) a, b = as_vec(a), as_vec(b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
vec_mt.__sub = function(a, b) a, b = as_vec(a), as_vec(b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vec_mt.__mul = function(a, b) a, b = as_vec(a), as_vec(b) return vector3(a.x * b.x, a.y * b.y, a.z * b.z) end
vec_mt.__unm = function(a) return vector3(-a.x, -a.y, -a.z) end
vec_mt.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
vec_mt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vec_mt.__tostring = function(a) return ('vector3(%g, %g, %g)'):format(a.x, a.y, a.z) end

--- Length of a vector3 (portable replacement for `#v`).
function M.length(v) return vec_mt.__len(v) end

-------------------------------------------------------------------------------------------------------
-- Scheduler: threads are coroutines woken by the fake clock. Nothing runs until the spec calls
-- natives.advance(ms) -- like FiveM, CreateThread schedules for the next tick, it does not run inline.
-------------------------------------------------------------------------------------------------------

local MAX_STEPS = 100000

local function current_thread()
    local co, is_main = coroutine.running()
    if co == nil or is_main then return nil end
    for _, th in ipairs(state.threads) do
        if th.co == co then return th end
    end
    return nil
end

local function schedule_thread(fn, label)
    local th = { co = coroutine.create(fn), wake = state.clock.now, label = label or 'thread' }
    record(state.threads, th)
    return th
end

local function wait(ms)
    local th = current_thread()
    if not th then
        -- Top-level Wait() in a script body: nothing to suspend. Treat it as a no-op.
        return
    end
    ms = tonumber(ms) or 0
    if ms < 1 then ms = 1 end -- Wait(0) = "next frame"; 1 ms keeps advance() finite
    coroutine.yield(ms)
end

local function next_due(target)
    local best_kind, best, best_idx
    for i, th in ipairs(state.threads) do
        if not th.dead and th.wake <= target and (not best or th.wake < best.wake) then
            best_kind, best, best_idx = 'thread', th, i
        end
    end
    for i, tm in ipairs(state.timers) do
        if not tm.cleared and tm.wake <= target and (not best or tm.wake < best.wake) then
            best_kind, best, best_idx = 'timer', tm, i
        end
    end
    return best_kind, best, best_idx
end

local function resume(th)
    local ok, ms = coroutine.resume(th.co)
    if not ok then
        th.dead = true
        error(('%s raised: %s'):format(th.label, tostring(ms)), 0)
    end
    if coroutine.status(th.co) == 'dead' then
        th.dead = true
    else
        th.wake = state.clock.now + (ms or 1)
    end
end

--- Advance the fake clock by `ms` (default 0), running every thread / timer that falls due, in time order.
--- Returns the number of thread resumes + timer callbacks executed.
function M.advance(ms)
    local target = state.clock.now + (tonumber(ms) or 0)
    local steps = 0
    while true do
        local kind, item, idx = next_due(target)
        if not kind then break end
        steps = steps + 1
        if steps > MAX_STEPS then
            error('natives.advance: more than ' .. MAX_STEPS .. ' steps -- a thread loops without Wait()?', 2)
        end
        if item.wake > state.clock.now then state.clock.now = item.wake end
        if kind == 'thread' then
            resume(item)
        else
            table.remove(state.timers, idx)
            item.fn()
        end
    end
    state.clock.now = target
    -- drop finished threads so the list does not grow forever
    for i = #state.threads, 1, -1 do
        if state.threads[i].dead then table.remove(state.threads, i) end
    end
    return steps
end

--- Number of live (not finished) threads.
function M.thread_count()
    local n = 0
    for _, th in ipairs(state.threads) do if not th.dead then n = n + 1 end end
    return n
end

--- Current fake time in ms (what GetGameTimer() returns).
function M.now() return state.clock.now end

--- Set the fake clock directly (does not run anything).
function M.set_time(ms) state.clock.now = ms end

-------------------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------------------

local function dispatch(name, src, args)
    local list = state.handlers[name]
    if not list then return 0 end
    local copy = {}
    for i, h in ipairs(list) do copy[i] = h end
    local prev_source = rawget(_G, 'source')
    local n = 0
    for _, h in ipairs(copy) do
        if not h.removed then
            n = n + 1
            rawset(_G, 'source', src)
            local ok, err = pcall(h.fn, unpack(args, 1, args.n))
            rawset(_G, 'source', prev_source)
            if not ok then error(err, 0) end
        end
    end
    return n
end

local function add_handler(name, fn)
    state.handlers[name] = state.handlers[name] or {}
    local h = { name = name, fn = fn }
    record(state.handlers[name], h)
    return h
end

--- Every captured call of one kind: 'local' (TriggerEvent), 'client' (TriggerClientEvent),
--- 'server' (TriggerServerEvent). Optional `name` filters by event name.
--- Each entry: { name = ..., target = <client id, client kind only>, args = { n = ..., ... } }
function M.emitted(kind, name)
    local list = state.emitted[kind]
    if not list then error('natives.emitted: unknown kind ' .. tostring(kind), 2) end
    if not name then return list end
    local out = {}
    for _, e in ipairs(list) do if e.name == name then out[#out + 1] = e end end
    return out
end

--- Last captured call of `kind` (optionally filtered by `name`), or nil.
function M.last_emitted(kind, name)
    local list = M.emitted(kind, name)
    return list[#list]
end

--- Fire a local event (as another resource or the engine would). Returns handlers run.
function M.fire(name, ...)
    return dispatch(name, rawget(_G, 'source'), pack(...))
end

--- Simulate a client sending a net event to the server. Only handlers of events registered with
--- RegisterNetEvent are reachable (as in FiveM). `source` is set to `src` while they run.
--- Returns handlers run (0 when the event is not net-registered).
function M.fire_net(name, src, ...)
    if not state.net_events[name] then return 0 end
    return dispatch(name, src, pack(...))
end

--- Number of handlers registered for an event.
function M.handler_count(name)
    local n = 0
    for _, h in ipairs(state.handlers[name] or {}) do if not h.removed then n = n + 1 end end
    return n
end

--- true when RegisterNetEvent was called for `name`.
function M.is_net_event(name) return state.net_events[name] == true end

-------------------------------------------------------------------------------------------------------
-- Exports: exports('name', fn) registers for the current resource; exports.res:name(...) calls it.
-------------------------------------------------------------------------------------------------------

local function export_proxy(resource)
    return setmetatable({}, {
        __index = function(_, fname)
            return function(_self, ...)
                local bucket = state.exports[resource]
                local fn = bucket and bucket[fname]
                if not fn then
                    error(('No such export %s in resource %s'):format(tostring(fname), tostring(resource)), 2)
                end
                return fn(...)
            end
        end,
    })
end

local function make_exports()
    return setmetatable({}, {
        __call = function(_, fname, fn)
            local res = state.resource
            state.exports[res] = state.exports[res] or {}
            state.exports[res][fname] = fn
        end,
        __index = function(_, resource) return export_proxy(resource) end,
    })
end

--- Stub an export of another resource: natives.stub_export('ox_inventory', 'GetItem', fn).
--- `fn` receives the arguments WITHOUT the colon-call self.
function M.stub_export(resource, fname, fn)
    state.exports[resource] = state.exports[resource] or {}
    state.exports[resource][fname] = fn
end

--- Exports registered by `resource` (defaults to the current resource).
function M.exports_of(resource)
    return state.exports[resource or state.resource] or {}
end

-------------------------------------------------------------------------------------------------------
-- Spies: record calls to any native the harness does not model.
-------------------------------------------------------------------------------------------------------

--- Install global `name` that records every call; `impl` (optional) provides the return value.
--- Returns the call list: each entry is a packed argument table ({ n = ..., ... }).
function M.spy(name, impl)
    local calls = {}
    state.spies[name] = calls
    set_global(name, function(...)
        record(calls, pack(...))
        if impl then return impl(...) end
    end)
    return calls
end

--- Calls recorded by M.spy(name) (empty table when never spied).
function M.calls(name) return state.spies[name] or {} end

--- Install (or replace) any global the script needs, and have reset() remove it later.
function M.stub(name, value)
    set_global(name, value)
    return value
end

-------------------------------------------------------------------------------------------------------
-- Players / convars helpers
-------------------------------------------------------------------------------------------------------

--- Add a connected player (server side). id is a number; name is what GetPlayerName returns.
function M.add_player(id, name)
    state.players[tonumber(id)] = { name = name or ('player' .. tostring(id)) }
end

function M.remove_player(id) state.players[tonumber(id)] = nil end

--- Set a convar as the server config would (`set name value`).
function M.set_convar(name, value) state.convars[name] = tostring(value) end

--- Convar writes made by the script via SetConvar*: { { name, value, kind } ... }
function M.convar_writes() return state.convar_writes end

--- The current registries (advanced use / debugging).
function M.state() return state end

-------------------------------------------------------------------------------------------------------
-- reset / install
-------------------------------------------------------------------------------------------------------

--- reset{ resource = 'name', side = 'server'|'client', convars = {...}, players = { [1] = 'Alice' } }
--- Removes every global installed earlier, rebuilds all registries and installs fresh stubs.
function M.reset(opts)
    opts = opts or {}
    for name in pairs(installed) do rawset(_G, name, nil) end
    installed = {}

    state = {
        resource = opts.resource or 'spec_resource',
        side = opts.side or 'server',
        clock = { now = opts.now or 0 },
        threads = {},
        timers = {},
        handlers = {},
        net_events = {},
        emitted = { ['local'] = {}, client = {}, server = {} },
        exports = {},
        spies = {},
        players = {},
        convars = {},
        convar_writes = {},
    }
    for k, v in pairs(opts.convars or {}) do state.convars[k] = tostring(v) end
    for id, name in pairs(opts.players or {}) do M.add_player(id, name) end

    -- threads / timers
    local function create_thread(fn) schedule_thread(fn) end
    local timer_seq = 0
    local function set_timeout(ms, fn)
        timer_seq = timer_seq + 1
        record(state.timers, { id = timer_seq, wake = state.clock.now + (tonumber(ms) or 0), fn = fn })
        return timer_seq
    end
    local function clear_timeout(id)
        for _, tm in ipairs(state.timers) do if tm.id == id then tm.cleared = true end end
    end

    set_global('CreateThread', create_thread)
    set_global('Wait', wait)
    set_global('SetTimeout', set_timeout)
    set_global('ClearTimeout', clear_timeout)
    set_global('Citizen', {
        CreateThread = create_thread,
        CreateThreadNow = function(fn) resume(schedule_thread(fn)) end,
        Wait = wait,
        SetTimeout = set_timeout,
        ClearTimeout = clear_timeout,
        Trace = function(s) io.write(tostring(s)) end,
    })
    set_global('GetGameTimer', function() return state.clock.now end)

    -- events
    set_global('AddEventHandler', function(name, fn) return add_handler(name, fn) end)
    set_global('RemoveEventHandler', function(h) if type(h) == 'table' then h.removed = true end end)
    set_global('RegisterNetEvent', function(name, fn)
        state.net_events[name] = true
        if fn then return add_handler(name, fn) end
    end)
    set_global('RegisterServerEvent', rawget(_G, 'RegisterNetEvent'))
    set_global('CancelEvent', function() end)
    set_global('WasEventCanceled', function() return false end)
    set_global('TriggerEvent', function(name, ...)
        local args = pack(...)
        record(state.emitted['local'], { name = name, args = args })
        dispatch(name, rawget(_G, 'source'), args)
    end)
    set_global('TriggerClientEvent', function(name, target, ...)
        record(state.emitted.client, { name = name, target = target, args = pack(...) })
    end)
    set_global('TriggerLatentClientEvent', function(name, target, _bps, ...)
        record(state.emitted.client, { name = name, target = target, args = pack(...), latent = true })
    end)
    set_global('TriggerServerEvent', function(name, ...)
        record(state.emitted.server, { name = name, args = pack(...) })
    end)
    set_global('TriggerLatentServerEvent', function(name, _bps, ...)
        record(state.emitted.server, { name = name, args = pack(...), latent = true })
    end)

    -- exports
    set_global('exports', make_exports())

    -- convars
    local function read_convar(name, default)
        local v = state.convars[name]
        if v == nil then return default end
        return v
    end
    set_global('GetConvar', function(name, default) return read_convar(name, default) end)
    set_global('GetConvarInt', function(name, default)
        local v = tonumber(state.convars[name])
        if v == nil then return default end
        return math.floor(v)
    end)
    set_global('GetConvarFloat', function(name, default)
        local v = tonumber(state.convars[name])
        if v == nil then return default end
        return v
    end)
    set_global('GetConvarBool', function(name, default)
        local v = state.convars[name]
        if v == nil then return default end
        return v == 'true' or v == '1'
    end)
    local function writer(kind)
        return function(name, value)
            state.convars[name] = tostring(value)
            record(state.convar_writes, { name = name, value = tostring(value), kind = kind })
        end
    end
    set_global('SetConvar', writer('SetConvar'))
    set_global('SetConvarReplicated', writer('SetConvarReplicated'))
    set_global('SetConvarServerInfo', writer('SetConvarServerInfo'))

    -- players
    set_global('GetPlayerName', function(id)
        local p = state.players[tonumber(id)]
        return p and p.name or nil
    end)
    set_global('GetPlayers', function()
        local ids = {}
        for id in pairs(state.players) do ids[#ids + 1] = id end
        table.sort(ids)
        for i, id in ipairs(ids) do ids[i] = tostring(id) end -- FiveM returns strings
        return ids
    end)
    set_global('GetNumPlayerIndices', function()
        local n = 0
        for _ in pairs(state.players) do n = n + 1 end
        return n
    end)
    set_global('DropPlayer', function(id, reason)
        state.players[tonumber(id)] = nil
        record(state.emitted['local'], { name = 'DropPlayer', target = id, args = pack(reason) })
    end)
    set_global('source', nil)

    -- resource / runtime
    set_global('GetCurrentResourceName', function() return state.resource end)
    set_global('GetInvokingResource', function() return opts.invoker end)
    set_global('IsDuplicityVersion', function() return state.side == 'server' end)
    set_global('json', opts.json or make_json())
    set_global('vector3', vector3)
    set_global('vec3', vector3)
    set_global('PlayerPedId', function() return 1 end)
    set_global('PlayerId', function() return 0 end)
    set_global('GetHashKey', function(s) return tostring(s) end) -- not joaat on purpose: pin names, not hashes

    -- Minimal ox_lib-style `lib` (opt in with reset{ lib = true }): only what is safe to fake.
    if opts.lib then
        set_global('lib', {
            print = { info = function() end, warn = function() end, error = function() end, debug = function() end },
            callback = setmetatable({ register = function() end }, { __call = function() end }),
            locale = function() end,
        })
    end

    return M
end

--- Which side the harness currently models ('server' or 'client').
function M.side() return state.side end

--- Switch the current resource name (what GetCurrentResourceName() and exports('x', fn) use).
function M.set_resource(name) state.resource = name end

M.reset()
return M
