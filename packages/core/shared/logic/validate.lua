-- Pure payload schema validator for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

local function getTextHelper()
    if AeternaCoreLogic and AeternaCoreLogic.text then
        return AeternaCoreLogic.text
    end
    local ok, mod = pcall(require, 'packages.core.shared.logic.text')
    if ok and type(mod) == 'table' then
        return mod
    end
    return {
        len = function(s) return type(s) == 'string' and #s or 0 end,
        cut = function(s, n)
            s = tostring(s or '')
            if n and #s > n then return s:sub(1, n) end
            return s
        end,
        clean = function(s, maxLen)
            s = tostring(s or ''):gsub('[%c]', ''):match('^%s*(.-)%s*$') or ''
            if maxLen and #s > maxLen then return s:sub(1, maxLen) end
            return s
        end,
    }
end

local function inEnum(val, list)
    for i = 1, #list do
        if list[i] == val then
            return true
        end
    end
    return false
end

local function isArrayTable(t)
    local n = #t
    local count = 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k > n or math.floor(k) ~= k then
            return false, 0
        end
        count = count + 1
    end
    return count == n, n
end

local function validateNode(value, schema, path, textHelper)
    local p = (path and path ~= '') and path or 'value'
    if type(schema) ~= 'table' then
        return false, p .. ': schema', nil
    end

    if value == nil then
        if schema.optional == true then
            return true, nil, schema.default
        end
        return false, p .. ': type', nil
    end

    local kind = schema.type
    if kind == 'string' then
        if type(value) ~= 'string' then
            return false, p .. ': type', nil
        end
        local cleaned = textHelper.clean(value, schema.maxLen)
        if schema.minLen ~= nil and textHelper.len(cleaned) < schema.minLen then
            return false, p .. ': minLen ' .. tostring(schema.minLen), nil
        end
        if type(schema.enum) == 'table' and not inEnum(cleaned, schema.enum) then
            return false, p .. ': enum', nil
        end
        if type(schema.pattern) == 'string' and not cleaned:find(schema.pattern) then
            return false, p .. ': pattern', nil
        end
        return true, nil, cleaned
    elseif kind == 'number' then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
            return false, p .. ': type', nil
        end
        if schema.integer == true and math.floor(value) ~= value then
            return false, p .. ': integer', nil
        end
        if schema.min ~= nil and value < schema.min then
            return false, p .. ': min ' .. tostring(schema.min), nil
        end
        if schema.max ~= nil and value > schema.max then
            return false, p .. ': max ' .. tostring(schema.max), nil
        end
        if type(schema.enum) == 'table' and not inEnum(value, schema.enum) then
            return false, p .. ': enum', nil
        end
        return true, nil, value
    elseif kind == 'boolean' then
        if type(value) ~= 'boolean' then
            return false, p .. ': type', nil
        end
        return true, nil, value
    elseif kind == 'table' then
        if type(value) ~= 'table' then
            return false, p .. ': type', nil
        end
        local fields = schema.fields
        local allowExtra = (schema.extra == true)

        if schema.maxKeys ~= nil then
            local keyCount = 0
            for _ in pairs(value) do
                keyCount = keyCount + 1
            end
            if keyCount > schema.maxKeys then
                return false, p .. ': maxKeys ' .. tostring(schema.maxKeys), nil
            end
        end

        if type(fields) == 'table' and not allowExtra then
            local extras = {}
            for k in pairs(value) do
                if fields[k] == nil then
                    extras[#extras + 1] = tostring(k)
                end
            end
            if #extras > 0 then
                table.sort(extras)
                local extraKey = extras[1]
                local extraPath = (path and path ~= '') and (path .. '.' .. extraKey) or extraKey
                return false, extraPath .. ': not allowed', nil
            end
        end

        local clean = {}
        if type(fields) == 'table' then
            local keys = {}
            for k in pairs(fields) do
                keys[#keys + 1] = k
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

            for i = 1, #keys do
                local k = keys[i]
                local fSchema = fields[k]
                local childPath = (path and path ~= '') and (path .. '.' .. tostring(k)) or tostring(k)
                local ok, err, cVal = validateNode(value[k], fSchema, childPath, textHelper)
                if not ok then
                    return false, err, nil
                end
                clean[k] = cVal
            end
        end

        if allowExtra or type(fields) ~= 'table' then
            for k, v in pairs(value) do
                if type(fields) ~= 'table' or fields[k] == nil then
                    if type(v) == 'string' then
                        clean[k] = textHelper.clean(v)
                    else
                        clean[k] = v
                    end
                end
            end
        end

        return true, nil, clean
    elseif kind == 'array' then
        if type(value) ~= 'table' then
            return false, p .. ': type', nil
        end
        local isArr, n = isArrayTable(value)
        if not isArr then
            return false, p .. ': type', nil
        end
        if schema.minItems ~= nil and n < schema.minItems then
            return false, p .. ': minItems ' .. tostring(schema.minItems), nil
        end
        if schema.maxItems ~= nil and n > schema.maxItems then
            return false, p .. ': maxItems ' .. tostring(schema.maxItems), nil
        end
        local clean = {}
        for i = 1, n do
            if type(schema.items) == 'table' then
                local itemPath = p .. '[' .. tostring(i) .. ']'
                local ok, err, cItem = validateNode(value[i], schema.items, itemPath, textHelper)
                if not ok then
                    return false, err, nil
                end
                clean[i] = cItem
            elseif type(value[i]) == 'string' then
                clean[i] = textHelper.clean(value[i])
            else
                clean[i] = value[i]
            end
        end
        return true, nil, clean
    end

    return false, p .. ': type', nil
end

function M.validate(value, schema)
    return validateNode(value, schema, '', getTextHelper())
end

setmetatable(M, {
    __call = function(_, value, schema)
        return M.validate(value, schema)
    end,
})

AeternaCoreLogic.validate = M
return M
