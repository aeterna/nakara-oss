-- aeterna_testkit server: the ACE-checked menu, player B invites, run tracking and the report.
-- aeterna_core owns the registry, the run lock, the destructive gate and every result; this file only shows them.

local Menu = TestkitLogic.menu
local Report = TestkitLogic.report
local Scrub = TestkitLogic.scrub
local Selftest = TestkitLogic.selftest

local RES = GetCurrentResourceName()
local ACE = 'aeterna.testkit.run'

local function clampSeconds(v)
    v = math.tointeger(tonumber(v)) or 30
    return math.min(math.max(v, 10), 120)
end

local inviteSeconds = clampSeconds(Config.inviteSeconds)
local printMode = (Config.printReport == 'json' or Config.printReport == 'none') and Config.printReport or 'md'
local invites = Menu.createInvites({ seconds = inviteSeconds, now = GetGameTimer })
local throttle = Menu.createThrottle(250)

local menus = {}   -- [src] = { panelId, kind = 'main'|'suite'|'invite'|'report'|'denied', busy }
local notes = {}   -- [src] = one line for the menu head (invite refused or declined)
local current = nil -- the run this resource started: { id, by, starter, b, names, rows, startedAt, env, json }
local last = nil   -- { report, plain, rows, file }
local flushScheduled = false

local function t(key, vars)
    return AeternaCore.t(key, vars)
end

local function core(fname, ...)
    local args = table.pack(...)
    local ok, a, b = pcall(function() return exports.aeterna_core[fname](exports.aeterna_core, table.unpack(args, 1, args.n)) end)
    if not ok then return nil end
    return a, b
end

local function kitVersions()
    local kit = {}
    for i = 0, GetNumResources() - 1 do
        local res = GetResourceByFindIndex(i)
        if type(res) == 'string' and res:sub(1, 8) == 'aeterna_' and GetResourceState(res) == 'started' then
            kit[res] = GetResourceMetadata(res, 'version', 0) or '?'
        end
    end
    return kit
end

local function busyLine(b)
    if type(b) ~= 'table' then return t('testkit.busy', { phase = '?', since = 0 }) end
    return t('testkit.busy', { phase = tostring(b.phase), since = tonumber(b.since) or 0 })
end

local function suitesView(rows)
    local out = {}
    if rows then
        for _, s in ipairs(Report.suites(rows)) do
            local ratio = s.passed .. '/' .. s.total
            local passes = s.worst == 'PASS' or s.worst == 'SKIP' or s.worst == 'MOCK'
            out[#out + 1] = { suite = s.suite, meta = passes and ratio or (ratio .. ' · ' .. s.worst), state = s.worst }
        end
        return out
    end
    local count, order = {}, {}
    for _, test in ipairs(core('listSelftests') or {}) do
        local suite = Report.suiteName(test.owner)
        if not count[suite] then
            count[suite] = 0
            order[#order + 1] = suite
        end
        if not test.noTests then count[suite] = count[suite] + 1 end
    end
    for _, suite in ipairs(order) do out[#out + 1] = { suite = suite, meta = '-/' .. count[suite] } end
    return out
end

local function buildView(src)
    local running = current ~= nil and current.id ~= nil
    local rows = (current and current.rows) or (last and last.rows)
    local done, total = 0, 0
    if running then
        local status = core('runStatus', current.id)
        done = status and status.done or #current.rows
        total = status and status.total or #current.rows
    end
    local busy = nil
    if not (running and current.starter == src) then busy = core('busy') end
    return {
        versions = Report.versionsLine(kitVersions()),
        gate = last and last.report.destructive or nil,
        bId = invites:bOf(src),
        note = notes[src],
        running = running,
        mine = running and current.starter == src,
        done = done, total = total,
        counts = Report.counts(rows or {}),
        suites = suitesView(rows),
        busy = busy,
        hasReport = last ~= nil,
    }
end

local function uikit(fname, ...)
    local args = table.pack(...)
    local ok, a = pcall(function() return exports.aeterna_uikit[fname](exports.aeterna_uikit, table.unpack(args, 1, args.n)) end)
    return ok and a or nil
end

-- Opens a testkit panel. The old panel's '__close' (reason replaced) arrives while menus[src] is nil and is ignored.
local function openPanel(src, kind, spec)
    menus[src] = nil
    local panelId = uikit('open', src, spec)
    if not panelId then
        AeternaCore.log.warn('panel refused', { kind = kind })
        return false
    end
    menus[src] = { panelId = panelId, kind = kind, busy = Menu.hasBlock(spec, 'busy') }
    return true
end

local function openMain(src)
    return openPanel(src, 'main', Menu.menuSpec(buildView(src), t))
end

local function openFor(src)
    if AeternaCore.can(src, ACE) then return openMain(src) end
    return openPanel(src, 'denied', {
        title = Menu.cut(t('testkit.menu.title'), 60), size = 'sm',
        blocks = { { id = 'denied', type = 'text', label = Menu.cut(t('testkit.denied'), 400) } },
    })
end

local function refresh(src)
    local m = menus[src]
    if not m or m.kind ~= 'main' then return end
    local spec = Menu.menuSpec(buildView(src), t)
    if Menu.hasBlock(spec, 'busy') ~= m.busy then
        openMain(src)
        return
    end
    uikit('update', src, m.panelId, Menu.menuPatch(spec))
end

local function refreshAll()
    local list = {}
    for src in pairs(menus) do list[#list + 1] = src end
    for _, src in ipairs(list) do refresh(src) end
end

-- At most 4 menu updates a second while a run reports rows.
local function pushProgress()
    if throttle:hit(GetGameTimer()) then
        refreshAll()
        return
    end
    if flushScheduled then return end
    flushScheduled = true
    SetTimeout(throttle:wait(GetGameTimer()), function()
        flushScheduled = false
        if throttle:due(GetGameTimer()) then refreshAll() end
    end)
end

local function setRole(src, role)
    if src and src > 0 then TriggerClientEvent('aeterna_testkit:cl:role', src, { role = role }) end
end

local function nowIso()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

-- Starts a run through aeterna_core. Rows that core decides before startRun returns arrive first,
-- so the run id is taken from the first row and checked against the return value.
local function beginRun(run, opts)
    current = run
    local id, busy = core('startRun', opts)
    if not id then
        current = nil
        return nil, busy
    end
    if run.id ~= id then
        run.id, run.rows = id, {}
    end
    return id
end

local function startMenuRun(src)
    if current then
        refresh(src)
        return
    end
    local b = invites:bOf(src)
    notes[src] = nil
    local id = beginRun({
        by = 'menu', starter = src, b = b, rows = {}, startedAt = nowIso(),
        names = { A = GetPlayerName(src), B = b and GetPlayerName(b) or nil },
    }, { by = src, b = b })
    if id then
        setRole(src, 'A')
        TriggerClientEvent('aeterna_testkit:cl:askEnv', src)
    end
    refresh(src)
end

local function openSuite(src, itemId)
    local rows = (current and current.rows) or (last and last.rows) or {}
    for _, s in ipairs(Report.suites(rows)) do
        if Menu.suiteId(s.suite) == itemId then
            local list = {}
            for _, r in ipairs(rows) do
                if Report.suiteName(r.suite) == s.suite then list[#list + 1] = r end
            end
            openPanel(src, 'suite', Menu.suiteSpec(s.suite, list, Report.shortName))
            return
        end
    end
end

local function openReport(src)
    if not last then return end
    local md = Report.markdown(last.report, '')
    local lines = {}
    for l in (md .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = l end
    openPanel(src, 'report', {
        title = Menu.cut(t('testkit.menu.report'), 60), size = 'md',
        blocks = {
            { id = 'summary', type = 'text', label = Menu.cut(((lines[3] or ''):gsub('%*', '')), 400) },
            { id = 'env', type = 'text', label = Menu.cut(lines[2] or '', 400) },
            { id = 'saved', type = 'text', label = Menu.cut(t('testkit.report.saved', { file = last.file }), 400) },
        },
    })
end

local function online(id)
    return GetPlayerName(id) ~= nil
end

local function inRun(id)
    return current ~= nil and (current.starter == id or current.b == id)
end

local INVITE_SCHEMA = { type = 'table', fields = { target = { type = 'number', integer = true, min = 1, max = 65535 } } }
local ANSWER_SCHEMA = { type = 'table', fields = { accept = { type = 'boolean' } } }

-- A invites B by server id from the invite panel. Rate limit is the caller's.
local function invite(src, payload)
    if not AeternaCore.can(src, ACE) then return end
    local ok, _, p = AeternaCore.validate(payload, INVITE_SCHEMA)
    if not ok or not invites:create(src, p.target, online, inRun) then
        notes[src] = t('testkit.invite.invalid')
        return
    end
    notes[src] = nil
    TriggerClientEvent('aeterna_testkit:cl:invite', p.target, { seconds = inviteSeconds })
end

local function openInvite(src)
    openPanel(src, 'invite', {
        title = Menu.cut(t('testkit.menu.invite'), 60), size = 'sm',
        blocks = {
            { id = 'target', type = 'field', label = Menu.cut(t('testkit.invite.prompt'), 40), input = 'number', min = 1,
                max = 65535 },
            { id = 'act', type = 'buttons', items = {
                { id = 'send', label = Menu.cut(t('testkit.menu.invite'), 24), variant = 'primary' } } },
        },
    })
end

local function scrub(s, names)
    return Scrub.scrub(s, names, AeternaCore.text.clean)
end

local function say(line)
    print(line)
end

local function finish(summary)
    local run = current
    current = nil
    summary = type(summary) == 'table' and summary or {}
    local kit = kitVersions()
    local env = run.env or {}
    local report = Report.build({
        runId = run.id, startedAt = run.startedAt, ms = summary.ms, by = run.by, playerB = run.b ~= nil,
        destructive = summary.destructive, cancelled = summary.cancelled, kit = kit, rows = run.rows,
        env = { fxserver = Report.parseBuild(GetConvar('version', '')), gameBuild = env.gameBuild, resolution = env.resolution },
    })
    local json = Report.encode(report)
    local md = Report.markdown(report, t('testkit.report.footer'))
    local okJson = SaveResourceFile(RES, 'reports/latest.json', json, -1)
    local okMd = SaveResourceFile(RES, 'reports/latest.md', md, -1)
    local file = ('kit-%s-%s.md'):format(kit.aeterna_core or '0', run.id)
    last = { report = report, plain = Report.plain(report), rows = run.rows, file = file }

    local mode = run.by == 'console' and (run.json and 'json' or 'md') or printMode
    if mode == 'json' then say(json) elseif mode == 'md' then say(md) end
    if okJson and okMd then
        if mode ~= 'none' then say(t('testkit.report.saved', { file = file })) end
    else
        AeternaCore.log.warn('report not saved', { json = tostring(okJson), md = tostring(okMd) })
    end

    if run.by == 'menu' then
        local b = invites:release(run.starter)
        setRole(b, 'none')
        setRole(run.starter, 'none')
    end
end

AddEventHandler('aeterna_core:runProgress', function(runId, row)
    local inv = GetInvokingResource()
    if inv ~= 'aeterna_core' or not current or type(row) ~= 'table' or type(runId) ~= 'string' then return end
    if current.id == nil then current.id = runId end
    if runId ~= current.id then return end
    local r = {
        suite = tostring(row.suite or ''), name = tostring(row.name or ''), state = tostring(row.state or ''),
        kind = type(row.kind) == 'string' and row.kind or nil,
        players = math.type(row.players) == 'integer' and row.players or nil,
        destructive = type(row.destructive) == 'boolean' and row.destructive or nil,
        ms = tonumber(row.ms) and math.floor(tonumber(row.ms)) or nil,
        step = math.type(row.step) == 'integer' and row.step or nil,
        detail = scrub(row.detail, current.names), expected = scrub(row.expected, current.names),
    }
    current.rows[#current.rows + 1] = r
    if current.by == 'console' then
        say(('%s %s %s ms %s'):format(r.state, r.name, tostring(r.ms or 0), r.detail or ''))
    end
    pushProgress()
end)

AddEventHandler('aeterna_core:runDone', function(runId, summary)
    local inv = GetInvokingResource()
    if inv ~= 'aeterna_core' then return end
    if current and current.id ~= nil and current.id == runId then finish(summary) end
    throttle:final(GetGameTimer())
    refreshAll()
end)

RegisterNetEvent('aeterna_testkit:sv:open', function()
    local src = tonumber(source)
    if not src or src <= 0 or not AeternaCore.rateLimit(src, 'aeterna_testkit:sv:open', 2, 1000) then return end
    openFor(src)
end)

RegisterNetEvent('aeterna_testkit:sv:inviteAnswer', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 or not AeternaCore.rateLimit(src, 'aeterna_testkit:sv:inviteAnswer', 3, 10000) then return end
    local ok, _, p = AeternaCore.validate(payload, ANSWER_SCHEMA)
    if not ok then return end
    local result, a = invites:answer(src, p.accept)
    if not result then return end
    if result == 'accepted' then
        notes[a] = nil
        setRole(src, 'B')
    else
        notes[a] = t('testkit.invite.declined')
    end
    refresh(a)
end)

RegisterNetEvent('aeterna_testkit:sv:leave', function()
    local src = tonumber(source)
    if not src or src <= 0 or not AeternaCore.rateLimit(src, 'aeterna_testkit:sv:leave', 2, 5000) then return end
    for _, pair in ipairs(invites:leave(src)) do
        setRole(pair.b, 'none')
        refresh(pair.a)
    end
end)

RegisterNetEvent('aeterna_testkit:sv:env', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 or not AeternaCore.rateLimit(src, 'aeterna_testkit:sv:env', 2, 10000) then return end
    local ok, _, p = AeternaCore.validate(payload, Selftest.ENV_SCHEMA)
    if not ok or not current or current.by ~= 'menu' or current.starter ~= src or current.env then return end
    current.env = { gameBuild = p.gameBuild, resolution = ('%dx%d'):format(p.w, p.h) }
end)

-- Menu buttons come back through uikit's own server-local event, ACE-checked again here.
AddEventHandler('aeterna_uikit:action', function(src, data)
    local inv = GetInvokingResource()
    if inv and inv ~= 'aeterna_uikit' then return end
    src = tonumber(src)
    if not src or type(data) ~= 'table' or data.owner ~= RES then return end
    local m = menus[src]
    if not m or m.panelId ~= data.panelId then return end
    local action = tostring(data.action or '')
    if action == '__close' then
        menus[src] = nil
        if m.kind == 'suite' or m.kind == 'invite' or m.kind == 'report' then openFor(src) end
        return
    end
    if not AeternaCore.can(src, ACE) then return end
    if m.kind == 'main' then
        if action == 'run' then
            startMenuRun(src)
        elseif action == 'invite' then
            openInvite(src)
        elseif action == 'cancel' then
            if current and current.id and current.starter == src then core('cancelRun', current.id) end
        elseif action == 'report' then
            openReport(src)
        elseif action:sub(1, 2) == 's_' then
            openSuite(src, action)
        end
    elseif m.kind == 'invite' and action == 'send' then
        if AeternaCore.rateLimit(src, 'aeterna_testkit:invite', 3, 10000) then
            invite(src, { target = type(data.values) == 'table' and data.values.target or nil })
        end
        openMain(src)
    end
end)

AddEventHandler('aeterna_uikit:menu', function(src, picked)
    local inv = GetInvokingResource()
    if inv and inv ~= 'aeterna_uikit' then return end
    src = tonumber(src)
    if src and type(picked) == 'table' and picked.owner == RES and picked.id == 'testkit' then openFor(src) end
end)

-- aeterna_core stopping (or restarting) ends its run without runDone: drop ours, free B and reset the roles.
AddEventHandler('onResourceStop', function(name)
    if name ~= 'aeterna_core' or not current then return end
    local run = current
    current = nil
    if run.by == 'menu' then
        local b = invites:release(run.starter)
        setRole(b, 'none')
        setRole(run.starter, 'none')
    end
    throttle:final(GetGameTimer())
    refreshAll()
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    menus[src], notes[src] = nil, nil
    for _, pair in ipairs(invites:leave(src)) do
        if pair.b ~= src then setRole(pair.b, 'none') end
        if pair.a ~= src then refresh(pair.a) end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for _, gone in ipairs(invites:expire()) do
            notes[gone.a] = t('testkit.invite.declined')
            refresh(gone.a)
        end
    end
end)

RegisterCommand('aeterna_testkit_run', function(src, args)
    if src ~= 0 then
        AeternaCore.log.warn('aeterna_testkit_run is console only')
        return
    end
    local opts = Menu.parseArgs(args)
    if current then
        say(busyLine(core('busy')))
        return
    end
    local id, busy = beginRun({ by = 'console', starter = 0, rows = {}, names = {}, json = opts.json, startedAt = nowIso() },
        { by = 0, only = opts.only and { opts.only } or nil })
    if not id then say(busyLine(busy or core('busy'))) end
end, true)

exports('lastReport', function()
    return last and last.plain or nil
end)

if Config.menuEntry ~= false then
    uikit('addMenuEntry', { id = 'testkit', label = Menu.cut(t('testkit.menu.title'), 60), icon = 'check', ace = ACE })
end

-- Own self-tests (spec § Self-tests). save reads the last report files back and writes nothing; it skips when
-- there is no report yet.

local function readSchema()
    local raw = LoadResourceFile(RES, 'schema/report-1.schema.json')
    if type(raw) ~= 'string' then return nil end
    local ok, schema = pcall(json.decode, raw)
    return ok and schema or nil
end

-- Both report files of a finished run, or nil when there is none yet.
local function lastReportFiles()
    local json1, md1 = LoadResourceFile(RES, 'reports/latest.json'), LoadResourceFile(RES, 'reports/latest.md')
    if type(json1) ~= 'string' or json1 == '' or type(md1) ~= 'string' or md1 == '' then return nil end
    return json1, md1
end

-- Read-only: a write here could race the report a finishing run saves, so the files are only read back.
local function saveCheck()
    local json1, md1 = lastReportFiles()
    if not json1 then return 'skip', 'no report yet' end
    return Selftest.save(json1, md1, json.decode)
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' or not Selftest.owns(RES, name) then return end
    local ok, detail
    if name == RES .. '.scrub' then
        ok, detail = Selftest.scrub(Scrub, AeternaCore.text.clean)
    elseif name == RES .. '.report_schema' then
        ok, detail = Selftest.reportSchema(Report, readSchema(), json.decode, t('testkit.report.footer'))
    elseif name == RES .. '.save' then
        ok, detail = saveCheck()
    else
        return
    end
    local sent, err = pcall(function() return exports.aeterna_core:reportSelftest(runId, name, ok, detail) end)
    if not sent then AeternaCore.log.warn('reportSelftest failed', { name = name, err = tostring(err) }) end
end)

for _, r in ipairs(Selftest.rows(RES, t)) do
    core('addSelftest', r.name, r.meta)
end
