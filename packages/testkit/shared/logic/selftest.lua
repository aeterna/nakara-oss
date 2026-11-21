-- Pure rules for aeterna_testkit's own self-tests (docs/specs/aeterna_testkit.md "Self-tests"): the rows it
-- registers with aeterna_core and the pass rule of each check. No natives; the report and scrub modules and the
-- JSON decoder are passed in.

TestkitLogic = TestkitLogic or {}

local M = {}

M.REPORT_FILES = { json = 'reports/latest.json', md = 'reports/latest.md' }

-- The spec table, in order. `t(key)` translates the eye tests' expect lines.
function M.rows(owner, t)
    local function row(id, meta) return { name = owner .. '.' .. id, meta = meta } end
    return {
        row('scrub', { kind = 'headless', players = 1, destructive = false }),
        row('report_schema', { kind = 'headless', players = 1, destructive = false }),
        row('save', { kind = 'headless', players = 1, destructive = false }),
        row('env', { kind = 'headless', side = 'client', players = 1, destructive = false }),
        row('eye_card', { kind = 'eye', players = 1, destructive = false, expect = t('testkit.selftest.expect.card') }),
        row('eye_card_b', { kind = 'eye', players = 2, destructive = false,
            expect = t('testkit.selftest.expect.card_b') }),
    }
end

function M.owns(owner, name)
    return type(name) == 'string' and name:sub(1, #owner + 1) == owner .. '.'
end

-- A detail with a name, a license id, an IPv4 and a Windows path.
local SCRUB_IN = 'player Somchai lost license:abc123 at 10.0.0.5:30120 C:\\srv\\x.lua'
local SCRUB_OUT = 'player A lost [id] at [ip] [path]'

function M.scrub(scrub, clean)
    local out = scrub.scrub(SCRUB_IN, { A = 'Somchai' }, clean)
    if out == SCRUB_OUT then return true, out end
    return false, 'scrub gave: ' .. tostring(out)
end

-- A finished run with every schema key known (no nulls, so a decoder that drops null keeps them all).
function M.sampleInput()
    return {
        runId = 'r1-test', startedAt = '2026-01-01T00:00:00Z', ms = 1000, by = 'menu', playerB = false,
        destructive = 'off', cancelled = false,
        env = { fxserver = '13068', gameBuild = 3258, resolution = '1920x1080' },
        kit = { aeterna_core = '0.2.0', aeterna_testkit = '0.1.0' },
        rows = { {
            suite = 'aeterna_testkit', name = 'aeterna_testkit.sample', kind = 'headless', players = 1,
            destructive = false, state = 'PASS', detail = 'ok', ms = 1, step = 1, expected = 'ok',
        } },
    }
end

-- Compares the keys of `obj` with the schema object `node` (required ⊆ keys ⊆ properties). Returns an error or nil.
local function keysMatch(obj, node)
    if type(obj) ~= 'table' or type(node) ~= 'table' then return 'not an object' end
    local props = node.properties or {}
    for _, k in ipairs(node.required or {}) do
        if obj[k] == nil then return 'missing key: ' .. k end
    end
    local unknown = {}
    for k in pairs(obj) do
        if props[k] == nil then unknown[#unknown + 1] = tostring(k) end
    end
    table.sort(unknown)
    if #unknown > 0 then return 'unknown key: ' .. table.concat(unknown, ', ') end
    return nil
end

-- The sample's JSON has exactly the schema's keys (top level, env, counts, each row); Markdown ends with `footer`.
function M.reportSchema(report, schema, decode, footer)
    local built = report.build(M.sampleInput())
    local ok, decoded = pcall(decode, report.encode(built))
    if not ok or type(decoded) ~= 'table' then return false, 'report JSON does not decode' end
    local props = type(schema) == 'table' and schema.properties or nil
    if type(props) ~= 'table' then return false, 'schema has no properties' end
    local err = keysMatch(decoded, schema)
        or keysMatch(decoded.env, props.env)
        or keysMatch(decoded.counts, props.counts)
    if not err then
        for i, row in ipairs(decoded.rows or {}) do
            err = keysMatch(row, props.rows and props.rows.items)
            if err then err = 'row ' .. i .. ': ' .. err break end
        end
    end
    if err then return false, err end
    local md = report.markdown(built, footer)
    if md:sub(-#footer - 1) ~= '\n' .. footer then return false, 'Markdown does not end with the footer' end
    return true, 'JSON keys match the schema; Markdown ends with the footer'
end

-- result = { json = { saved, wrote, back }, md = { saved, wrote, back } }
function M.save(result)
    for _, k in ipairs({ 'json', 'md' }) do
        local r = result[k] or {}
        if r.saved ~= true then return false, M.REPORT_FILES[k] .. ': SaveResourceFile returned false' end
        if r.back ~= r.wrote then return false, M.REPORT_FILES[k] .. ': read back differs' end
    end
    return true, 'both report files saved and read back'
end

-- The schema of aeterna_testkit:sv:env, the client's askEnv reply. The server checks sv:env with it and the env
-- self-test checks the reply the client would send with it.
M.ENV_SCHEMA = { type = 'table', fields = {
    gameBuild = { type = 'number', integer = true, min = 1, max = 99999 },
    w = { type = 'number', integer = true, min = 320, max = 15360 },
    h = { type = 'number', integer = true, min = 240, max = 8640 },
} }

-- `validate` = AeternaCore.validate; `payload` = the askEnv reply { gameBuild, w, h }.
function M.env(validate, payload)
    local ok, err = validate(payload, M.ENV_SCHEMA)
    if not ok then return false, 'askEnv reply refused: ' .. tostring(err) end
    return true, ('game build %d · %dx%d'):format(payload.gameBuild, payload.w, payload.h)
end

TestkitLogic.selftest = M
return M
