-- voice.lua -- Pure logic for aeterna_phonecall voice backends. `channels` (FiveM Enhanced): FXServer's
-- server-side voice channels. `pma` (anything else): pma-voice call channels while pma-voice is started.
-- Natives and the pma-voice export come in through `opts`, so busted drives both with fakes.

PhonecallVoice = {}
local V = PhonecallVoice

V.NATIVES = { 'CreateVoiceChannel', 'AddPlayerToVoiceChannel', 'RemovePlayerFromVoiceChannel',
    'SetPlayerMutedInVoiceChannel', 'DeleteVoiceChannel' }
V.FULL = 65535
V.SLOTS = 9999

function V.pick(gamename)
    return gamename == 'gta5enhanced' and 'channels' or 'pma'
end

-- opts = { gamename, natives = { <name> = fn }, resourceState = fn(name), setPlayerCall = fn(src, channel),
--          channelBase = 20000, warn = fn(msg, fields) }
function V.create(opts)
    local o = type(opts) == 'table' and opts or {}
    local n = type(o.natives) == 'table' and o.natives or {}
    local warn = type(o.warn) == 'function' and o.warn or function() end
    local b = { kind = V.pick(o.gamename), base = tonumber(o.channelBase) or 20000, used = {} }

    if b.kind == 'channels' then
        b.nativesOk = true
        for _, name in ipairs(V.NATIVES) do
            if type(n[name]) ~= 'function' then b.nativesOk = false end
        end
    end

    function b:available()
        if self.kind == 'channels' then return self.nativesOk end
        return type(o.resourceState) == 'function' and o.resourceState('pma-voice') == 'started'
    end

    function b:name()
        return self:available() and self.kind or 'none'
    end

    local function createChannel()
        local ok, ch = pcall(n.CreateVoiceChannel, 0, 0.0)
        if not ok or type(ch) ~= 'number' or ch < 0 or ch == V.FULL then
            local result = ok and tostring(ch) or ('error: ' .. tostring(ch))
            warn('phonecall voice channel not created', { result = result })
            return nil, result
        end
        return ch
    end

    local function lowestSlot()
        for s = 1, V.SLOTS do
            if not b.used[s] then
                b.used[s] = true
                return s
            end
        end
        return nil
    end

    -- Puts `players` ({ a, b }) in one channel. Returns true or false, 'voice_off'.
    function b:connect(call, players)
        if not self:available() then return false, 'voice_off' end
        if self.kind == 'channels' then
            local ch = createChannel()
            if not ch then return false, 'voice_off' end
            call.voice = { channel = ch, players = { players[1], players[2] } }
            for _, src in ipairs(players) do
                pcall(n.AddPlayerToVoiceChannel, ch, src)
                pcall(n.SetPlayerMutedInVoiceChannel, ch, src, false)
            end
            return true
        end
        local slot = lowestSlot()
        if not slot then
            warn('phonecall pma-voice call channels are all in use', {})
            return false, 'voice_off'
        end
        call.voice = { slot = slot, players = { players[1], players[2] } }
        for _, src in ipairs(players) do
            local ok, e = pcall(o.setPlayerCall, src, self.base + slot)
            if not ok then warn('phonecall pma-voice setPlayerCall failed', { error = tostring(e) }) end
        end
        return true
    end

    -- Takes the call's players out (only those `isConnected(src)` says are still here) and frees the channel once.
    function b:disconnect(call, isConnected)
        local v = call.voice
        if not v then return end
        call.voice = nil
        local players = v.players
        if v.channel then
            for _, src in ipairs(players) do
                if src ~= nil and isConnected(src) then
                    local ok, e = pcall(n.RemovePlayerFromVoiceChannel, v.channel, src)
                    if not ok then warn('phonecall voice channel remove failed', { error = tostring(e) }) end
                end
            end
            local ok, e = pcall(n.DeleteVoiceChannel, v.channel)
            if not ok then warn('phonecall voice channel delete failed', { error = tostring(e) }) end
        elseif v.slot then
            for _, src in ipairs(players) do
                if src ~= nil and isConnected(src) and self:available() then
                    pcall(o.setPlayerCall, src, 0)
                end
            end
            self.used[v.slot] = nil
        end
    end

    -- voice_channel self-test: one mode-0 channel created and deleted, nobody in it.
    function b:probe()
        local ch, result = createChannel()
        if not ch then return false, 'create returned ' .. tostring(result) end
        local ok, e = pcall(n.DeleteVoiceChannel, ch)
        if not ok then return false, 'delete failed: ' .. tostring(e) end
        return true, 'channel ' .. tostring(ch) .. ' created and deleted'
    end

    return b
end

return PhonecallVoice
