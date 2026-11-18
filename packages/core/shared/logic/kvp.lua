-- Pure versioned client KVP storage logic for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

M.MAX_BYTES = 16384

function M.pkgName(resourceName)
    local res = tostring(resourceName or 'core')
    if res:sub(1, 8) == 'aeterna_' then
        return res:sub(9)
    end
    return res
end

function M.keyFor(resourceName, name, version)
    local pkg = M.pkgName(resourceName)
    return 'aeterna_' .. pkg .. ':' .. tostring(name) .. ':v' .. tostring(version)
end

function M.new(adapter)
    adapter = type(adapter) == 'table' and adapter or {}
    local backing = adapter
    local getResource = type(adapter.resource) == 'function'
        and adapter.resource
        or function() return adapter.resource or 'aeterna_core' end
    local getString = type(adapter.getString) == 'function'
        and adapter.getString
        or function(k) return backing[k] end
    local setString = type(adapter.setString) == 'function'
        and adapter.setString
        or function(k, v) backing[k] = tostring(v) end
    local deleteKey = type(adapter.delete) == 'function'
        and adapter.delete
        or function(k) backing[k] = nil end
    local encode = type(adapter.encode) == 'function'
        and adapter.encode
        or function(v) return json and json.encode(v) or tostring(v) end
    local decode = type(adapter.decode) == 'function'
        and adapter.decode
        or function(s) return json and json.decode(s) or nil end
    local warn = type(adapter.warn) == 'function'
        and adapter.warn
        or function() end

    local warnedBadJson = {}
    local inst = {}

    local function getImpl(name, version, default)
        local key = M.keyFor(getResource(), name, version)
        local raw = getString(key)
        if raw == nil or raw == '' then
            return default
        end
        local ok, decoded = pcall(decode, raw)
        if not ok or (decoded == nil and raw ~= 'null') then
            if warnedBadJson[key] ~= raw then
                warnedBadJson[key] = raw
                warn('invalid JSON in KVP key ' .. key)
            end
            return default
        end
        return decoded
    end

    local function setImpl(name, version, value)
        local key = M.keyFor(getResource(), name, version)
        local ok, encoded = pcall(encode, value)
        if not ok or type(encoded) ~= 'string' then
            warn('cannot encode KVP value for ' .. key)
            return nil
        end
        if #encoded > M.MAX_BYTES then
            warn('KVP value exceeds 16 KB limit for ' .. key)
            return nil
        end
        setString(key, encoded)
        return nil
    end

    local function migrateImpl(name, from, to, fn)
        local res = getResource()
        local fromKey = M.keyFor(res, name, from)
        local toKey = M.keyFor(res, name, to)
        local rawFrom = getString(fromKey)
        local rawTo = getString(toKey)
        if rawFrom ~= nil and rawFrom ~= '' and (rawTo == nil or rawTo == '') then
            local oldVal = getImpl(name, from, nil)
            if oldVal ~= nil and type(fn) == 'function' then
                local newVal = fn(oldVal)
                setImpl(name, to, newVal)
            end
            deleteKey(fromKey)
        end
        return nil
    end

    function inst.get(a, b, c, d)
        if a == inst then
            return getImpl(b, c, d)
        end
        return getImpl(a, b, c)
    end

    function inst.set(a, b, c, d)
        if a == inst then
            return setImpl(b, c, d)
        end
        return setImpl(a, b, c)
    end

    function inst.migrate(a, b, c, d, e)
        if a == inst then
            return migrateImpl(b, c, d, e)
        end
        return migrateImpl(a, b, c, d)
    end

    function inst.keyFor(name, version)
        return M.keyFor(getResource(), name, version)
    end

    return inst
end

AeternaCoreLogic.kvp = M
return M
