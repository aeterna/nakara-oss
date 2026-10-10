-- resource.lua -- load a real FiveM resource's scripts into the stubbed environment.
--
--   local natives  = require('helpers.natives')
--   local resource = require('helpers.resource')
--
--   natives.reset()
--   local res = resource.load_resource('packages/my-resource', 'client')
--   natives.advance(0)              -- run threads the scripts created
--
-- load_resource(dir, side, opts) reads <dir>/fxmanifest.lua with a small declarative parser (it never
-- executes the manifest), then runs shared scripts followed by <side> scripts, each list in manifest
-- order -- the same order FiveM uses. Every script shares _G, as scripts of one resource do in FiveM.
--
-- opts:
--   name      resource name for GetCurrentResourceName() (default: manifest `name`, else folder name)
--   reset     natives.reset() options; when given, the harness is reset before loading
--   skip      { ['path/in/manifest.lua'] = true } -- entries not to run
--   externals { ['@ox_lib/init.lua'] = 'path/on/disk.lua' } -- '@resource/file' entries; unmapped ones
--             are skipped and listed in result.skipped
--
-- Returns { name, dir, side, manifest, loaded = { paths }, skipped = { entries }, exports = { ... } }.

-- Load natives.lua next to this file, whatever module prefix the caller used to require us.
local prefix = (...) and (...):match('^(.-)[^%.]+$') or ''
local natives = require(prefix .. 'natives')

local M = {}

local LIST_KEYS = {
    client_script = 'client', client_scripts = 'client',
    server_script = 'server', server_scripts = 'server',
    shared_script = 'shared', shared_scripts = 'shared',
    file = 'files', files = 'files',
    dependency = 'dependencies', dependencies = 'dependencies',
}
local SCALAR_KEYS = {
    fx_version = true, game = true, lua54 = true, name = true, author = true,
    description = true, version = true, ui_page = true, loadscreen = true, repository = true,
}

local function read_file(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local body = f:read('*a') -- '*a' (not 'a') keeps Lua 5.1 happy
    f:close()
    return body
end

local function blank(s) return (s:gsub('[^\n]', ' ')) end

local function strip_comments(src)
    -- block comments: --[[ ]] and --[==[ ]==]
    src = src:gsub('(%-%-%[(=*)%[.-%]%2%])', blank)
    -- line comments
    src = src:gsub('%-%-[^\n]*', blank)
    return src
end

local function strings_in(s)
    local out = {}
    local pos = 1
    while true do
        local q1, q2 = s:find('[\'"]', pos)
        if not q1 then break end
        local quote = s:sub(q1, q1)
        local close = s:find(quote, q2 + 1, true)
        if not close then break end
        out[#out + 1] = s:sub(q1 + 1, close - 1)
        pos = close + 1
    end
    return out
end

--- Parse fxmanifest.lua source. Understands `key 'v'`, `key "v"` and `key { 'a', "b" }` (multi-line).
--- Returns { client = {}, server = {}, shared = {}, files = {}, dependencies = {}, <scalar keys> }.
function M.parse_manifest(src)
    local text = strip_comments(src)
    local m = { client = {}, server = {}, shared = {}, files = {}, dependencies = {} }
    local pos = 1
    while true do
        local s, e, key, open = text:find('([%a_][%w_]*)%s*([{\'"])', pos)
        if not s then break end
        local value, stop
        if open == '{' then
            local close = text:find('}', e + 1, true)
            if not close then break end
            value, stop = text:sub(e, close), close
        else
            local close = text:find(open, e + 1, true)
            local nl = text:find('\n', e + 1, true)
            if not close or (nl and nl < close) then
                pos = e + 1
                value = nil
            else
                value, stop = text:sub(e, close), close
            end
        end
        if value then
            local list = LIST_KEYS[key]
            if list then
                for _, v in ipairs(strings_in(value)) do m[list][#m[list] + 1] = v end
            elseif SCALAR_KEYS[key] then
                m[key] = strings_in(value)[1]
            end
            pos = stop + 1
        end
    end
    return m
end

--- Read and parse <dir>/fxmanifest.lua.
function M.read_manifest(dir)
    local path = dir .. '/fxmanifest.lua'
    local src = read_file(path)
    if not src then error('no fxmanifest.lua in ' .. tostring(dir), 2) end
    return M.parse_manifest(src)
end

local function glob_to_pattern(seg)
    return '^' .. seg:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0'):gsub('%*', '.*') .. '$'
end

-- Expand one manifest entry ('client/*.lua' style globs in the last path segment only).
local function expand(dir, entry)
    if not entry:find('*', 1, true) then return { entry } end
    if entry:find('**', 1, true) then
        error('load_resource: recursive glob not supported: ' .. entry, 3)
    end
    local ok, lfs = pcall(require, 'lfs')
    if not ok then
        error('load_resource: glob ' .. entry .. ' needs luafilesystem (luarocks install luafilesystem)', 3)
    end
    local sub, seg = entry:match('^(.*)/([^/]*)$')
    if not sub then sub, seg = '', entry end
    if sub:find('*', 1, true) then
        error('load_resource: glob only supported in the file name: ' .. entry, 3)
    end
    local base = sub == '' and dir or (dir .. '/' .. sub)
    local pat = glob_to_pattern(seg)
    local out = {}
    if lfs.attributes(base, 'mode') ~= 'directory' then return out end
    for f in lfs.dir(base) do
        if f ~= '.' and f ~= '..' and f:match(pat) and lfs.attributes(base .. '/' .. f, 'mode') == 'file' then
            out[#out + 1] = (sub == '' and f) or (sub .. '/' .. f)
        end
    end
    table.sort(out)
    return out
end

local function run_file(path)
    local before = {}
    for k in pairs(_G) do before[k] = true end
    local chunk, err = loadfile(path)
    if not chunk then
        error(('load_resource: cannot load %s: %s\n(CfxLua-only syntax such as `backtick` hashes or '
            .. '<const> does not load in stock Lua -- see busted/README.md)'):format(path, tostring(err)), 0)
    end
    chunk()
    -- globals a resource script defines are removed by the next natives.reset()
    for k in pairs(_G) do
        if not before[k] and type(k) == 'string' then natives.track_global(k) end
    end
end

--- Load a resource directory for `side` ('client' or 'server') into the stubbed environment.
function M.load_resource(dir, side, opts)
    opts = opts or {}
    side = side or 'server'
    if side ~= 'client' and side ~= 'server' then
        error("load_resource: side must be 'client' or 'server'", 2)
    end
    dir = dir:gsub('/+$', '')
    local manifest = M.read_manifest(dir)
    local name = opts.name or manifest.name or dir:match('([^/]+)$')

    if opts.reset then
        local r = {}
        for k, v in pairs(opts.reset) do r[k] = v end
        r.resource, r.side = r.resource or name, r.side or side
        natives.reset(r)
    else
        natives.set_resource(name)
        natives.state().side = side
    end

    local result = { name = name, dir = dir, side = side, manifest = manifest, loaded = {}, skipped = {} }
    local skip = opts.skip or {}
    local externals = opts.externals or {}

    local function run_list(list)
        for _, entry in ipairs(list) do
            if entry:sub(1, 1) == '@' then
                local mapped = externals[entry]
                if mapped then
                    run_file(mapped)
                    result.loaded[#result.loaded + 1] = mapped
                else
                    result.skipped[#result.skipped + 1] = entry
                end
            elseif skip[entry] then
                result.skipped[#result.skipped + 1] = entry
            else
                for _, rel in ipairs(expand(dir, entry)) do
                    if rel:match('%.lua$') then
                        run_file(dir .. '/' .. rel)
                        result.loaded[#result.loaded + 1] = rel
                    else
                        result.skipped[#result.skipped + 1] = rel -- JS/C# scripts are not runnable here
                    end
                end
            end
        end
    end

    run_list(manifest.shared)
    run_list(manifest[side])
    result.exports = natives.exports_of(name)
    return result
end

return M
