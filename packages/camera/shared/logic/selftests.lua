-- selftests.lua -- aeterna_camera self-test rows (spec "Self-tests (0.2)") and what counts as a pass for each.
-- The server and client wrappers only gather results and report them. No natives.

CameraLogic = CameraLogic or {}

local M = {}

M.FAKE_WHO = 'test:camera'

function M.rows(t)
    return {
        { name = 'aeterna_camera.id_and_path_guard', meta = { kind = 'headless', players = 1, destructive = false } },
        { name = 'aeterna_camera.http_router', meta = { kind = 'headless', players = 1, destructive = false } },
        { name = 'aeterna_camera.store_roundtrip', meta = { kind = 'mock', players = 1, destructive = false } },
        { name = 'aeterna_camera.caps', meta = { kind = 'mock', players = 1, destructive = false } },
        { name = 'aeterna_camera.saved_hook', meta = { kind = 'mock', players = 1, destructive = false } },
        { name = 'aeterna_camera.screenshot_detect', meta = { kind = 'headless', players = 1, destructive = false } },
        { name = 'aeterna_camera.viewfinder', meta = { kind = 'eye', players = 1, destructive = false,
            expect = t('camera.selftest.viewfinder') } },
        { name = 'aeterna_camera.shoot_and_view', meta = { kind = 'eye', players = 1, destructive = true,
            expect = t('camera.selftest.shoot_and_view'), skipWhen = { resources = { 'screenshot-basic' } },
            timeout = 15000 } },
    }
end

-- The eye test drives the viewfinder itself, then hands over to the person (ms from the test's start).
M.VIEWFINDER_STEPS = {
    { at = 0, action = 'open' },
    { at = 1500, action = 'selfie' },
    { at = 3000, action = 'close' },
}

-- shoot_and_view on the client: wait for the server's viewfinder, shoot, then wait for the gallery it opens
-- (capture plus a latent upload of a few hundred KB). Both fit inside the row's 15 s timeout.
M.SHOOT_WAIT_VIEWFINDER_MS = 5000
M.SHOOT_WAIT_GALLERY_MS = 8000

local BAD_IDS = {
    '../0123456789abcdef0123456789ab', '0123456789ABCDEF0123456789ABCDEF', '0123456789abcdef0123456789abcde',
    '0123456789abcdef0123456789abcdef0', '0123456789abcdef0123456789abcd/x', '0123456789abcdef0123456789abcdeg', '',
}

-- Generated ids match ^[0-9a-f]{32}$, never repeat, and the guard refuses every bad form.
function M.guard(isId, nextId)
    local seen = {}
    for i = 1, 200 do
        local id = nextId()
        if type(id) ~= 'string' or #id ~= 32 or not id:find('^[0-9a-f]+$') or not isId(id) then
            return false, 'generated id ' .. i .. ' does not match ^[0-9a-f]{32}$'
        end
        if seen[id] then return false, 'generated id ' .. i .. ' repeats' end
        seen[id] = true
    end
    for _, bad in ipairs(BAD_IDS) do
        if isId(bad) then return false, 'guard accepted a bad id' end
    end
    return true, '200 distinct ids, ' .. #BAD_IDS .. ' bad forms refused'
end

-- Requests for one router, in order; the last ones push a single address over the 60-in-10-s limit.
function M.httpCases(id)
    local addr = '192.0.2.1:1'
    local cases = {
        { req = { method = 'GET', path = '/p/' .. id .. '.jpg', address = addr }, status = 200 },
        { req = { method = 'GET', path = '/p/../' .. id .. '.jpg', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. id:upper() .. '.jpg', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. id:sub(2) .. '.jpg', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. id .. '0.jpg', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. id .. '.png', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. string.rep('0', 32) .. '.jpg', address = addr }, status = 404 },
        { req = { method = 'POST', path = '/p/' .. id .. '.jpg', address = addr }, status = 404 },
        { req = { method = 'GET', path = '/p/' .. id .. '.jpg?v=1', address = addr }, status = 200 },
    }
    for _ = #cases + 1, 60 do
        cases[#cases + 1] = { req = { method = 'GET', path = '/', address = addr }, status = 404 }
    end
    cases[#cases + 1] = { req = { method = 'GET', path = '/p/' .. id .. '.jpg', address = addr }, status = 429 }
    return cases
end

-- answers[i] = { status, headers } as the fake response object saw them.
function M.judgeHttp(cases, answers)
    if type(answers) ~= 'table' or #answers ~= #cases then return false, 'missing answers' end
    for i, c in ipairs(cases) do
        local a = answers[i]
        if type(a.headers) ~= 'table' or next(a.headers) == nil then
            return false, 'case ' .. i .. ': writeHead without a header'
        end
        if a.status ~= c.status then
            return false, ('case %d: %s, expected %d'):format(i, tostring(a.status), c.status)
        end
    end
    return true, #cases .. ' requests answered as expected'
end

local PHOTO_FIELDS = {
    { 'id', 'string' }, { 'who', 'string' }, { 'ts', 'number' }, { 'mode', 'string' }, { 'bytes', 'number' },
    { 'path', 'string' }, { 'urlPath', 'string' },
}

-- events = { { src, photo }, … } caught for the test's own photo.
function M.checkSaved(events, id)
    if #events ~= 1 then return false, 'saved fired ' .. #events .. ' times' end
    local photo = events[1][2]
    if type(photo) ~= 'table' or photo.id ~= id then return false, 'saved carried another photo' end
    for _, f in ipairs(PHOTO_FIELDS) do
        if type(photo[f[1]]) ~= f[2] then return false, 'saved photo has no ' .. f[1] end
    end
    if photo.path ~= 'photos/' .. id .. '.jpg' or photo.urlPath ~= '/aeterna_camera/p/' .. id .. '.jpg' then
        return false, 'saved photo paths do not match its id'
    end
    return true, 'one saved event with every field'
end

-- before = { total }, after = { total, count = photos left under the fake key, left = records still in KVP }.
function M.restored(before, after)
    return after.total == before.total and after.count == 0 and after.left == 0
end

function M.screenshotDetail(started)
    if started then return true, 'screenshot-basic started: photos on' end
    return true, 'screenshot-basic not started: photos off, viewfinder only'
end

CameraLogic.selftests = M
return M
