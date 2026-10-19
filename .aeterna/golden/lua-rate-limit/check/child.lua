-- Child process for the lua-rate-limit golden check. check.sh starts this WITHOUT AETERNA_GOLDEN_NONCE.
-- Parent/child design: check.sh holds the nonce and never loads fixture/. This child loads fixture/ratelimit.lua
-- and runs the expectations. The success line goes to stdout only when every expectation held and the count is
-- exactly EXPECTED; every other outcome exits 1. The fixture runs in this process without the nonce in its
-- environment, so it never sees the nonce.
-- Builtins are captured as locals BEFORE the fixture is loaded, so a fixture that replaces globals (os.exit,
-- pcall, io.write, _G, ...) cannot change how failures are reported or counted.
local EXPECTED = 39

local pcall, next, tostring, type, require = pcall, next, tostring, type, require
local sformat, tconcat = string.format, table.concat
local exit = os.exit
local G, argv, pkg = _G, arg, package
local stdout, stderr = io.stdout, io.stderr
local writeOut, writeErr = stdout.write, stderr.write

local fixtureDir = argv and argv[1]
if not fixtureDir then
    writeErr(stderr, 'child: missing fixture directory argument\n')
    exit(1)
    return
end

-- Snapshot the globals before the fixture is loaded, to detect state kept in globals.
-- `next` is used directly so a metatable __pairs on _G cannot hide a leak.
local globalsBefore = {}
for k in next, G do globalsBefore[k] = true end

pkg.path = fixtureDir .. '/?.lua;' .. pkg.path
local okLoad, M = pcall(require, 'ratelimit')
if not okLoad or type(M) ~= 'table' or type(M.allow) ~= 'function' then
    writeErr(stderr, 'FAIL: fixture/ratelimit.lua must return a table with an allow() function\n')
    exit(1)
    return
end
local allow = M.allow

local passed, failed = 0, 0

local function expect(label, cond)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        writeErr(stderr, 'FAIL: ' .. label .. '\n')
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

-- I: two sources interleaved in one state table (max=3, windowMs=500). Clock never goes backwards.
s = {}
expectResult('I1 g at 0 allowed', call(s, 'g', 0, 3, 500), true)
expectResult('I2 h at 100 allowed (own history)', call(s, 'h', 100, 3, 500), true)
expectResult('I3 g at 300 allowed', call(s, 'g', 300, 3, 500), true)
expectResult('I4 g at 350 allowed (0 and 300 count)', call(s, 'g', 350, 3, 500), true)
expectResult('I5 h at 350 allowed (only the call at 100 counts)', call(s, 'h', 350, 3, 500), true)
expectResult('I6 g at 360 rejected (0, 300, 350 all count)', call(s, 'g', 360, 3, 500), false)
expectResult('I7 h at 400 allowed (100 and 350 count)', call(s, 'h', 400, 3, 500), true)
expectResult('I8 g at 500 allowed (the call at 0 has expired)', call(s, 'g', 500, 3, 500), true)
expectResult('I9 h at 520 rejected (100, 350, 400 count)', call(s, 'h', 520, 3, 500), false)
expectResult('I10 g at 800 allowed (300 expired; rejected 360 never counted)', call(s, 'g', 800, 3, 500), true)
expectResult('I11 g at 801 rejected (350, 500, 800 count)', call(s, 'g', 801, 3, 500), false)

-- N: an invalid call changes no state.
s = {}
expectResult('N1 first valid call allowed', call(s, 'a', 0, 2, 100), true)
expect('N2 invalid max=0 call raises', raises(s, 'a', 10, 0, 100))
expectResult('N3 next valid call sees only the call at 0', call(s, 'a', 20, 2, 100), true)
expectResult('N4 third call sees the calls at 0 and 20', call(s, 'a', 30, 2, 100), false)

-- F: no state leaked into globals.
local leaked = {}
for k in next, G do
    if not globalsBefore[k] then leaked[#leaked + 1] = tostring(k) end
end
expect('F1 no new globals (leaked: ' .. tconcat(leaked, ',') .. ')', #leaked == 0)

-- Success line only when every expectation held and the count is the one this child defines.
if failed == 0 and passed == EXPECTED then
    writeOut(stdout, sformat('GOLDEN_OK lua-rate-limit expectations=%d\n', passed))
else
    writeErr(stderr, sformat('lua-rate-limit: %d failed, ran %d expectations, want %d\n',
        failed, passed + failed, EXPECTED))
    exit(1)
end
