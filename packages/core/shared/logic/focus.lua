-- Pure NUI focus lock state machine for aeterna_core. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

function M.new(callbacks)
    callbacks = type(callbacks) == 'table' and callbacks or {}
    local onLost = callbacks.onLost
    local onApply = callbacks.onApply

    local currentOwner = nil
    local currentToken = nil
    local currentOpts = nil
    local seq = 0

    local inst = {}

    local function requestImpl(owner, opts)
        local nextOwner = tostring(owner or 'aeterna_core')
        local normalized = type(opts) == 'table' and opts or {}
        local cursor = normalized.cursor ~= false
        local keyboard = normalized.keyboard ~= false
        local keepGameInput = normalized.keepGameInput == true

        local preempted = nil
        if currentToken ~= nil and currentOwner ~= nil and currentOwner ~= nextOwner then
            local prevOwner = currentOwner
            local prevToken = currentToken
            preempted = { owner = prevOwner, token = prevToken, reason = 'preempted' }
            if onLost then
                onLost(prevOwner, prevToken, 'preempted')
            end
        end

        seq = seq + 1
        local token = 'focus_' .. tostring(seq)
        currentOwner = nextOwner
        currentToken = token
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
        if type(token) ~= 'string' or currentToken == nil or token ~= currentToken then
            return false
        end
        currentOwner = nil
        currentToken = nil
        currentOpts = nil
        if onApply then
            onApply(false, false, false)
        end
        return true
    end

    local function stopImpl(stoppedResource, coreResource)
        if currentToken == nil or currentOwner == nil then
            return nil
        end
        local coreName = coreResource or 'aeterna_core'
        local reason = nil
        if stoppedResource == coreName then
            reason = 'released_by_core'
        elseif stoppedResource == currentOwner then
            reason = 'owner_stopped'
        end
        if not reason then
            return nil
        end

        local prevOwner = currentOwner
        local prevToken = currentToken
        currentOwner = nil
        currentToken = nil
        currentOpts = nil

        if onApply then
            onApply(false, false, false)
        end
        if onLost then
            onLost(prevOwner, prevToken, reason)
        end
        return { owner = prevOwner, token = prevToken, reason = reason }
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

    function inst.onResourceStop(a, b, c)
        if a == inst then
            return stopImpl(b, c)
        end
        return stopImpl(a, b)
    end

    function inst.reset()
        currentOwner = nil
        currentToken = nil
        currentOpts = nil
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
