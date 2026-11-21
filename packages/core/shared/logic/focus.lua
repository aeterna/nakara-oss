-- Pure NUI focus lock state machine for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

function M.new(callbacks)
    callbacks = type(callbacks) == 'table' and callbacks or {}
    local onLost = callbacks.onLost
    local onApply = callbacks.onApply
    local onPaused = callbacks.onPaused
    local onResumed = callbacks.onResumed

    local currentOwner = nil
    local currentToken = nil
    local currentOpts = nil
    local currentOverlay = false
    local paused = nil -- { owner, token, opts } of the normal holder that an overlay covers
    local seq = 0

    local inst = {}

    local function lost(owner, token, reason)
        if onLost then
            onLost(owner, token, reason)
        end
    end

    local function clearActive()
        currentOwner = nil
        currentToken = nil
        currentOpts = nil
        currentOverlay = false
    end

    -- Gives focus back to the paused holder (same token), or clears the natives when there is none.
    local function resumeOrClear()
        if paused == nil then
            if onApply then
                onApply(false, false, false)
            end
            return
        end
        local p = paused
        paused = nil
        currentOwner, currentToken, currentOpts, currentOverlay = p.owner, p.token, p.opts, false
        if onApply then
            onApply(p.opts.keyboard, p.opts.cursor, p.opts.keepGameInput)
        end
        if onResumed then
            onResumed(p.owner, p.token)
        end
    end

    local function requestImpl(owner, opts)
        local nextOwner = tostring(owner or 'aeterna_core')
        local normalized = type(opts) == 'table' and opts or {}
        local overlay = normalized.overlay == true
        local cursor = normalized.cursor ~= false
        local keyboard = normalized.keyboard ~= false
        local keepGameInput = normalized.keepGameInput == true
        local changed = currentToken ~= nil and currentOwner ~= nextOwner

        local preempted = nil
        if changed and overlay and not currentOverlay then
            -- An overlay pauses a normal holder: no focusLost, and the holder keeps its token.
            paused = { owner = currentOwner, token = currentToken, opts = currentOpts }
            if onPaused then
                onPaused(currentOwner, currentToken)
            end
        elseif changed then
            preempted = { owner = currentOwner, token = currentToken, reason = 'preempted' }
            lost(currentOwner, currentToken, 'preempted')
        end
        if paused ~= nil and not overlay then
            -- A normal request also preempts the paused holder.
            local p = paused
            paused = nil
            if p.owner ~= nextOwner then
                lost(p.owner, p.token, 'preempted')
            end
        elseif paused ~= nil and paused.owner == nextOwner then
            paused = nil -- the paused holder takes the card itself; nothing resumes later
        end

        seq = seq + 1
        local token = 'focus_' .. tostring(seq)
        currentOwner = nextOwner
        currentToken = token
        currentOverlay = overlay
        currentOpts = {
            cursor = cursor,
            keyboard = keyboard,
            keepGameInput = keepGameInput,
        }

        if onApply then
            onApply(keyboard, cursor, keepGameInput)
        end

        return token, preempted
    end

    local function releaseImpl(token)
        if type(token) ~= 'string' then
            return false
        end
        if paused ~= nil and token == paused.token then
            -- A paused holder releases its own token; nothing resumes when the overlay ends.
            paused = nil
            return true
        end
        if currentToken == nil or token ~= currentToken then
            return false
        end
        clearActive()
        resumeOrClear()
        return true
    end

    local function stopImpl(stoppedResource, coreResource)
        local coreName = coreResource or 'aeterna_core'
        if stoppedResource == coreName then
            local p = paused
            local prevOwner, prevToken = currentOwner, currentToken
            paused = nil
            clearActive()
            resumeOrClear()
            if p ~= nil then
                lost(p.owner, p.token, 'released_by_core')
            end
            if prevToken == nil then
                return nil
            end
            lost(prevOwner, prevToken, 'released_by_core')
            return { owner = prevOwner, token = prevToken, reason = 'released_by_core' }
        end
        if paused ~= nil and stoppedResource == paused.owner then
            -- The paused holder is gone: nothing to resume when the overlay ends.
            local p = paused
            paused = nil
            lost(p.owner, p.token, 'owner_stopped')
            return { owner = p.owner, token = p.token, reason = 'owner_stopped' }
        end
        if currentToken == nil or currentOwner == nil or stoppedResource ~= currentOwner then
            return nil
        end
        local prevOwner, prevToken = currentOwner, currentToken
        clearActive()
        lost(prevOwner, prevToken, 'owner_stopped')
        resumeOrClear()
        return { owner = prevOwner, token = prevToken, reason = 'owner_stopped' }
    end

    function inst.request(a, b, c)
        if a == inst then
            return requestImpl(b, c)
        end
        return requestImpl(a, b)
    end

    inst.requestFocus = inst.request

    function inst.release(a, b)
        if a == inst then
            return releaseImpl(b)
        end
        return releaseImpl(a)
    end

    inst.releaseFocus = inst.release

    function inst.owner()
        return currentOwner
    end

    inst.focusOwner = inst.owner

    function inst.token()
        return currentToken
    end

    function inst.opts()
        return currentOpts
    end

    function inst.pausedOwner()
        return paused and paused.owner or nil
    end

    function inst.pausedToken()
        return paused and paused.token or nil
    end

    function inst.onResourceStop(a, b, c)
        if a == inst then
            return stopImpl(b, c)
        end
        return stopImpl(a, b)
    end

    function inst.reset()
        paused = nil
        clearActive()
    end

    return inst
end

local defaultFocus = M.new()

function M.request(owner, opts)
    return defaultFocus.request(owner, opts)
end

M.requestFocus = M.request

function M.release(token)
    return defaultFocus.release(token)
end

M.releaseFocus = M.release

function M.owner()
    return defaultFocus.owner()
end

M.focusOwner = M.owner

function M.onResourceStop(stoppedResource, coreResource)
    return defaultFocus.onResourceStop(stoppedResource, coreResource)
end

function M.reset()
    return defaultFocus.reset()
end

AeternaCoreLogic.focus = M
return M
