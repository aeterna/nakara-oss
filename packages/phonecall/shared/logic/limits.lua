-- limits.lua -- Pure logic for aeterna_phonecall limits and payload schemas. `rl` is shaped like
-- AeternaCore.rateLimit(src, key, max, windowMs) -> boolean, so the server passes the real one and busted a fake.

PhonecallLimits = {}
local L = PhonecallLimits

L.SMS = {
    { key = 'phonecall:sms:short', max = 1, window = 2000 },
    { key = 'phonecall:sms:long', max = 15, window = 60000 },
}
L.SMS_PAIR = { key = 'phonecall:sms:pair:', max = 6, window = 60000 }
L.DIAL = {
    { key = 'phonecall:dial:short', max = 1, window = 3000 },
    { key = 'phonecall:dial:long', max = 10, window = 60000 },
}
L.SERVICE = { key = 'phonecall:service', max = 30, window = 60000 }

-- The spec's schemas; the server checks `{ number = values.number, … }`, never the whole values table.
local NUMBER = { type = 'string', maxLen = 20, pattern = '^[%d%-%s%+%(%)]+$' }
L.DIAL_SCHEMA = { type = 'table', fields = { number = NUMBER } }
L.SEND_SCHEMA = { type = 'table', fields = {
    number = NUMBER,
    body = { type = 'string', maxLen = 300 },
} }

-- Stops at the first rule that refuses, so a refused call does not use up the longer windows.
local function all(rl, src, rules)
    for _, r in ipairs(rules) do
        if not rl(src, r.key, r.max, r.window) then return false end
    end
    return true
end

-- One player message to `peerDigits`: 1 / 2 s and 15 / 60 s per sender, 6 / 60 s per sender and recipient.
function L.checkSms(rl, src, peerDigits)
    local ok = all(rl, src, L.SMS)
    if ok and not rl(src, L.SMS_PAIR.key .. tostring(peerDigits), L.SMS_PAIR.max, L.SMS_PAIR.window) then
        ok = false
    end
    if not ok then return false, 'phonecall.sms.slow' end
    return true
end

-- One dial: 1 / 3000 ms and 10 / 60 s per player.
function L.checkDial(rl, src)
    return all(rl, src, L.DIAL)
end

-- One `sendSms` from a resource: 30 / 60 s per calling resource.
function L.checkService(rl, resource)
    return rl('resource:' .. tostring(resource), L.SERVICE.key, L.SERVICE.max, L.SERVICE.window)
end

return PhonecallLimits
