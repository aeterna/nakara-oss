-- Pure report building for aeterna_testkit: the aeterna_testkit.report/1 table, its JSON line and the Markdown file.
-- No natives. Rows come from aeterna_core:runProgress and are already scrubbed.

TestkitLogic = TestkitLogic or {}

local M = {}

M.SCHEMA = 'aeterna_testkit.report/1'
M.MAX_ROWS = 500
-- JSON null. Keys whose value is unknown hold this marker so every schema key is present.
M.NULL = setmetatable({}, { __tostring = function() return 'null' end })

M.STATES = { 'PASS', 'FAIL', 'SKIP', 'GAP', 'MOCK', 'MISSING' }
local RANK = { FAIL = 1, MISSING = 2, GAP = 3, SKIP = 4, MOCK = 5, PASS = 6 }
local PASSED = { PASS = true, SKIP = true, MOCK = true }

local TOP_KEYS = { 'schema', 'runId', 'startedAt', 'ms', 'by', 'playerB', 'destructive', 'cancelled', 'env', 'kit',
    'counts', 'ok', 'rows', 'truncated' }
local ENV_KEYS = { 'fxserver', 'gameBuild', 'resolution' }
local ROW_KEYS = { 'suite', 'name', 'kind', 'players', 'destructive', 'state', 'detail', 'ms', 'step', 'expected' }

local function orNull(v)
    if v == nil then return M.NULL end
    return v
end

local function isNull(v)
    return v == nil or v == M.NULL
end

-- 'aeterna_phonekit' -> 'phonekit'; other names unchanged.
function M.suiteName(owner)
    owner = tostring(owner or '')
    if owner:sub(1, 8) == 'aeterna_' then return owner:sub(9) end
    return owner
end

-- 'aeterna_phonekit.fold_keeps_screen' -> 'phonekit.fold_keeps_screen' (Markdown only).
function M.shortName(name)
    return M.suiteName(name)
end

-- The build number from the server's `version` convar, or nil. Nothing else of the string is kept.
function M.parseBuild(version)
    if type(version) ~= 'string' then return nil end
    return version:match('v1%.0%.0%.(%d+)')
end

-- The worse of two states: FAIL, MISSING, GAP, SKIP, MOCK, PASS.
function M.worst(a, b)
    if RANK[a] == nil then return b end
    if RANK[b] == nil then return a end
    if RANK[a] <= RANK[b] then return a end
    return b
end

function M.counts(rows)
    local c = {}
    for _, s in ipairs(M.STATES) do c[s] = 0 end
    for _, r in ipairs(rows or {}) do
        if c[r.state] ~= nil then c[r.state] = c[r.state] + 1 end
    end
    return c
end

-- One entry per suite in order of first appearance: { suite, passed, total, worst }.
-- passed counts PASS, SKIP and MOCK; total counts every row.
function M.suites(rows)
    local out, index = {}, {}
    for _, r in ipairs(rows or {}) do
        local name = M.suiteName(r.suite)
        local s = index[name]
        if not s then
            s = { suite = name, passed = 0, total = 0, worst = 'PASS' }
            index[name] = s
            out[#out + 1] = s
        end
        s.total = s.total + 1
        if PASSED[r.state] then s.passed = s.passed + 1 end
        s.worst = M.worst(s.worst, r.state)
    end
    return out
end

local function reportRow(r)
    return {
        suite = M.suiteName(r.suite), name = tostring(r.name or ''), kind = orNull(r.kind), players = orNull(r.players),
        destructive = orNull(r.destructive), state = tostring(r.state or ''), detail = orNull(r.detail),
        ms = orNull(r.ms), step = orNull(r.step), expected = orNull(r.expected),
    }
end

-- input = { runId, startedAt, ms, by, playerB, destructive, cancelled, env = { fxserver, gameBuild, resolution },
--           kit = { [resource] = version }, rows }. Counts and ok come from all rows; rows past 500 are cut.
function M.build(input)
    local rows = input.rows or {}
    local counts = M.counts(rows)
    local env = input.env or {}
    local kit = {}
    for res, ver in pairs(input.kit or {}) do kit[res] = tostring(ver) end
    local out = {
        schema = M.SCHEMA, runId = tostring(input.runId or ''), startedAt = tostring(input.startedAt or ''),
        ms = tonumber(input.ms) or 0, by = input.by == 'console' and 'console' or 'menu',
        playerB = input.playerB == true, destructive = input.destructive == 'on' and 'on' or 'off',
        cancelled = input.cancelled == true,
        env = { fxserver = orNull(env.fxserver), gameBuild = orNull(env.gameBuild), resolution = orNull(env.resolution) },
        kit = kit, counts = counts, ok = counts.FAIL == 0 and counts.MISSING == 0, rows = {},
    }
    for i = 1, math.min(#rows, M.MAX_ROWS) do out.rows[i] = reportRow(rows[i]) end
    if #rows > M.MAX_ROWS then out.truncated = true end
    return out
end

-- The report with every null marker removed, for the lastReport export (exports cannot carry the marker).
function M.plain(v)
    if v == M.NULL then return nil end
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = M.plain(x) end
    return out
end

local ESCAPES = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r',
    ['\t'] = '\\t' }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(ch)
        return ESCAPES[ch] or string.format('\\u%04x', ch:byte())
    end) .. '"'
end

local encodeValue

local function encodeObject(t, keys)
    local parts = {}
    for _, k in ipairs(keys) do
        if t[k] ~= nil then parts[#parts + 1] = encodeString(k) .. ':' .. encodeValue(t[k]) end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

function encodeValue(v, keys)
    if v == M.NULL or v == nil then return 'null' end
    local tv = type(v)
    if tv == 'boolean' then return v and 'true' or 'false' end
    if tv == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if math.type(v) == 'integer' or v == math.floor(v) then return string.format('%d', v) end
        return string.format('%.14g', v)
    end
    if tv == 'string' then return encodeString(v) end
    if tv == 'table' then
        if keys then return encodeObject(v, keys) end
        if #v > 0 or next(v) == nil then
            local parts = {}
            for i = 1, #v do parts[i] = encodeValue(v[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        end
        return encodeObject(v, sortedKeys(v))
    end
    return 'null'
end

-- One JSON line with keys in schema order (kit keys sorted).
function M.encode(report)
    local parts = {}
    for _, k in ipairs(TOP_KEYS) do
        local v = report[k]
        if v ~= nil then
            local enc
            if k == 'env' then
                enc = encodeValue(v, ENV_KEYS)
            elseif k == 'counts' then
                enc = encodeValue(v, M.STATES)
            elseif k == 'kit' then
                enc = encodeObject(v, sortedKeys(v))
            elseif k == 'rows' then
                local rows = {}
                for i = 1, #v do rows[i] = encodeValue(v[i], ROW_KEYS) end
                enc = '[' .. table.concat(rows, ',') .. ']'
            else
                enc = encodeValue(v)
            end
            parts[#parts + 1] = encodeString(k) .. ':' .. enc
        end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function show(v)
    if isNull(v) then return '-' end
    return tostring(v)
end

-- Markdown table cells cannot hold a pipe.
local function cell(s)
    return (tostring(s):gsub('|', '/'))
end

local function versionsLine(kit)
    local parts = {}
    for _, res in ipairs(sortedKeys(kit or {})) do parts[#parts + 1] = res .. ' ' .. tostring(kit[res]) end
    return table.concat(parts, ' · ')
end
M.versionsLine = versionsLine

local function itemLine(r, withKind)
    local parts = { M.shortName(r.name) .. ((withKind and not isNull(r.kind)) and (' (' .. tostring(r.kind) .. ')') or '') }
    if not isNull(r.step) then parts[#parts + 1] = 'step ' .. tostring(r.step) end
    if not isNull(r.expected) then parts[#parts + 1] = 'expected ' .. tostring(r.expected) end
    if not isNull(r.detail) and r.detail ~= '' then parts[#parts + 1] = tostring(r.detail) end
    return '- ' .. table.concat(parts, ' · ')
end

-- The Markdown report. footer = the translated testkit.report.footer line, always last.
function M.markdown(report, footer)
    local c = report.counts
    local out = {
        '# Starter Kit test report · ' .. report.runId,
        string.format('FXServer %s · game build %s · %s · by %s · player B %s · destructive %s',
            show(report.env.fxserver), show(report.env.gameBuild), show(report.env.resolution), report.by,
            report.playerB and 'yes' or 'no', report.destructive),
        string.format('**%s** · PASS %d · FAIL %d · SKIP %d · GAP %d · MOCK %d · MISSING %d · %d s%s%s',
            report.ok and 'PASS' or 'FAIL', c.PASS, c.FAIL, c.SKIP, c.GAP, c.MOCK, c.MISSING,
            math.floor((report.ms or 0) / 1000), report.cancelled and ' · cancelled' or '',
            report.truncated and (' · first ' .. M.MAX_ROWS .. ' rows') or ''),
        '',
        '| Suite | Passed | Worst |',
        '| --- | --- | --- |',
    }
    for _, s in ipairs(M.suites(report.rows)) do
        out[#out + 1] = string.format('| %s | %d/%d | %s |', cell(s.suite), s.passed, s.total, s.worst)
    end
    local sections = {
        { title = '## FAIL and MISSING', states = { FAIL = true, MISSING = true }, kind = true },
        { title = '## Left for a person (GAP)', states = { GAP = true } },
        { title = '## SKIP', states = { SKIP = true } },
    }
    for _, sec in ipairs(sections) do
        local items = {}
        for _, r in ipairs(report.rows) do
            if sec.states[r.state] then items[#items + 1] = itemLine(r, sec.kind) end
        end
        if #items > 0 then
            out[#out + 1] = ''
            out[#out + 1] = sec.title
            for _, l in ipairs(items) do out[#out + 1] = l end
        end
    end
    out[#out + 1] = ''
    out[#out + 1] = '## Versions'
    out[#out + 1] = versionsLine(report.kit)
    out[#out + 1] = ''
    out[#out + 1] = tostring(footer or '')
    return table.concat(out, '\n')
end

TestkitLogic.report = M
return M
