-- Child process for the lua-rate-limit golden check. check.sh starts this WITHOUT AETERNA_GOLDEN_NONCE.
-- It loads fixture/ratelimit.lua and runs the expectations. Failures go to stderr. The success line goes to
-- stdout only when every expectation held.
local fixtureDir = arg and arg[1]
if not fixtureDir then
    io.stderr:write('child: missing fixture directory argument\n')
    os.exit(1)
end

-- Snapshot the globals before the fixture is loaded, to detect state kept in globals.
local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

package.path = fixtureDir .. '/?.lua;' .. package.path
local okLoad, M = pcall(require, 'ratelimit')
if not okLoad or type(M) ~= 'table' or type(M.allow) ~= 'function' then
    io.stderr:write('FAIL: fixture/ratelimit.lua must return a table with an allow() function\n')
    os.exit(1)
end
local allow = M.allow

local passed, failed = 0, 0

local function expect(label, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write('FAIL: ' .. label .. '\n')
    end
end

local function expectResult(label, got, want)
    expect(label .. ' (want ' .. tostring(want) .. ', got ' .. tostring(got) .. ')', got == want)
end

-- Returns allow()'s result, or nil when it raises.
local function call(...)
    local ok, res = pcall(allow, ...)
    if ok then return res end
    return nil
end

-- True when allow() raises for these arguments.
local function raises(...)
    local ok = pcall(allow, ...)
    return not ok
end

-- A: max=2, windowMs=1000, one source (matches the example in task.md).
local s = {}
expectResult('A1 first call under max is allowed', call(s, 'a', 0, 2, 1000), true)
expectResult('A2 second call under max is allowed', call(s, 'a', 10, 2, 1000), true)
expectResult('A3 third call inside the window is rejected', call(s, 'a', 20, 2, 1000), false)
expectResult('A4 rejection at 999 (both allowed calls still count)', call(s, 'a', 999, 2, 1000), false)
expectResult('A5 at 1000 the call at 0 has expired', call(s, 'a', 1000, 2, 1000), true)
expectResult('A6 at 1009 the calls at 10 and 1000 both count', call(s, 'a', 1009, 2, 1000), false)
expectResult('A7 at 1010 the call at 10 has expired', call(s, 'a', 1010, 2, 1000), true)

-- B: sources are independent.
s = {}
expectResult('B1 source x first call allowed (max=1)', call(s, 'x', 0, 1, 500), true)
expectResult('B2 source y first call allowed (max=1)', call(s, 'y', 0, 1, 500), true)
expectResult('B3 source x second call rejected', call(s, 'x', 1, 1, 500), false)
expectResult('B4 source y second call rejected', call(s, 'y', 1, 1, 500), false)

-- C: separate state tables are independent.
local s1, s2 = {}, {}
expectResult('C1 state 1 allows the first call', call(s1, 'a', 0, 1, 500), true)
expectResult('C2 state 2 has its own history for the same source', call(s2, 'a', 0, 1, 500), true)

-- D: exact window boundary with max=1, windowMs=100.
s = {}
expectResult('D1 first call allowed', call(s, 'a', 0, 1, 100), true)
expectResult('D2 at 99 the call at 0 still counts', call(s, 'a', 99, 1, 100), false)
expectResult('D3 at 100 the call at 0 has expired', call(s, 'a', 100, 1, 100), true)

-- E: invalid arguments raise an error.
expect('E1 max=0 raises', raises({}, 'a', 0, 0, 1000))
expect('E2 max=1.5 raises', raises({}, 'a', 0, 1.5, 1000))
expect("E3 max='2' raises", raises({}, 'a', 0, '2', 1000))
expect('E4 max=-1 raises', raises({}, 'a', 0, -1, 1000))
expect('E5 windowMs=0 raises', raises({}, 'a', 0, 1, 0))
expect('E6 windowMs=-1 raises', raises({}, 'a', 0, 1, -1))
expect("E7 windowMs='1000' raises", raises({}, 'a', 0, 1, '1000'))

-- F: no state leaked into globals.
local leaked = {}
for k in pairs(_G) do
    if not globalsBefore[k] then leaked[#leaked + 1] = tostring(k) end
end
expect('F1 no new globals (leaked: ' .. table.concat(leaked, ',') .. ')', #leaked == 0)

if failed > 0 then
    io.stderr:write(string.format('%d of %d expectations failed\n', failed, passed + failed))
    os.exit(1)
end
io.write('GOLDEN_OK lua-rate-limit expectations=' .. passed .. '\n')
