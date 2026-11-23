Config = Config or {}

-- Phone numbers: `#` = a random digit, any other character is literal (at least 4 `#`, at most 20 characters).
Config.number = {
    format = '555-####',
    reserved = { '555-0000', '555-0911' },
    assign = 'first_open', -- 'first_open' (first time either app opens) or 'on_load' (when the character loads)
}

-- Messages: visible characters per message (1-300) and messages kept per character (10-100).
Config.sms = {
    maxLen = 160,
    keep = 100,
}

-- Calls: ringing without an answer becomes `missed` (5-60 s, phonekit's ring card ends after 60 s); an active call
-- ends with `limit` after maxMinutes.
-- channelBase: Legacy only, the first pma-voice call channel this package uses (channelBase + 1 ... + 9999).
Config.call = {
    ringSeconds = 30,
    maxMinutes = 60,
    channelBase = 20000,
}

-- Call log entries kept per character.
Config.recentCalls = 30

return Config
