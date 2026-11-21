-- config.lua -- Pure logic for aeterna_phonecall: reads config.lua into checked values. A value out of range falls
-- back to its default with one warn; a number format with fewer than 4 `#` is refused at start with one error.

PhonecallConfig = {}
local C = PhonecallConfig

C.DEFAULTS = {
    number = { format = '555-####', reserved = { '555-0000', '555-0911' }, assign = 'first_open' },
    sms = { maxLen = 160, keep = 100 },
    call = { ringSeconds = 30, maxMinutes = 60, channelBase = 20000 },
    recentCalls = 30,
}

local RANGES = {
    { 'sms', 'maxLen', 1, 300 },
    { 'sms', 'keep', 10, 100 },
    { 'call', 'ringSeconds', 5, 120 },
    { 'call', 'maxMinutes', 1, 1440 },
    { 'call', 'channelBase', 1, 1000000 },
}

local function int(v)
    return type(v) == 'number' and v == v and math.floor(v) == v
end

-- cfg = the shipped Config table; warn(msg, fields) and err(msg, fields) log. Returns a fresh table.
function C.resolve(cfg, warn, err)
    local src = type(cfg) == 'table' and cfg or {}
    local D = C.DEFAULTS
    local out = {
        number = { format = D.number.format, reserved = {}, assign = D.number.assign },
        sms = { maxLen = D.sms.maxLen, keep = D.sms.keep },
        call = { ringSeconds = D.call.ringSeconds, maxMinutes = D.call.maxMinutes, channelBase = D.call.channelBase },
        recentCalls = D.recentCalls,
    }
    local number = type(src.number) == 'table' and src.number or {}

    if number.format ~= nil then
        local ok, why = PhonecallNumber.validateFormat(number.format)
        if ok then
            out.number.format = number.format
        else
            err('phonecall Config.number.format refused, using 555-####', { reason = why })
        end
    end

    local reserved = type(number.reserved) == 'table' and number.reserved or D.number.reserved
    for _, r in ipairs(reserved) do
        if type(r) == 'string' then out.number.reserved[#out.number.reserved + 1] = r end
    end

    if number.assign ~= nil then
        if number.assign == 'first_open' or number.assign == 'on_load' then
            out.number.assign = number.assign
        else
            warn('phonecall Config.number.assign is not first_open or on_load, using first_open', {})
        end
    end

    for _, r in ipairs(RANGES) do
        local group, key, lo, hi = r[1], r[2], r[3], r[4]
        local v = type(src[group]) == 'table' and src[group][key] or nil
        if v ~= nil then
            if int(v) and v >= lo and v <= hi then
                out[group][key] = v
            else
                warn('phonecall Config value out of range, using the default', { key = group .. '.' .. key })
            end
        end
    end

    if src.recentCalls ~= nil then
        if int(src.recentCalls) and src.recentCalls >= 1 and src.recentCalls <= 100 then
            out.recentCalls = src.recentCalls
        else
            warn('phonecall Config value out of range, using the default', { key = 'recentCalls' })
        end
    end
    return out
end

return PhonecallConfig
