-- shell.lua -- Pure logic for the aeterna_phonekit 0.2 shell: keypad list, two panes and fold continuity,
-- the frame's own clamp and drawn scale, and the lock-screen rule. html/devicelayout.js mirrors these rules.
-- Natives-free so stock Lua can test it.

ShellLogic = {}
local S = ShellLogic

--------------------------------------------------------------------------------
-- Keypad list (keypad, burner)
--------------------------------------------------------------------------------

-- Returns the new highlighted row and, when the key opens a row, that row's index.
-- ArrowUp / ArrowDown wrap; Enter opens the highlight; '1'-'9' open rows 1-9 and '0' row 10.
function S.keypadMove(index, count, key)
    local n = math.max(0, math.floor(tonumber(count) or 0))
    if n == 0 then return 0, nil end
    local i = math.floor(tonumber(index) or 1)
    if i < 1 or i > n then i = 1 end
    if key == 'ArrowDown' then
        return (i % n) + 1, nil
    elseif key == 'ArrowUp' then
        return ((i - 2) % n) + 1, nil
    elseif key == 'Enter' then
        return i, i
    elseif type(key) == 'string' and key:match('^%d$') then
        local row = tonumber(key)
        if row == 0 then row = 10 end
        if row <= n then return row, row end
    end
    return i, nil
end

--------------------------------------------------------------------------------
-- Two panes (`detailOf`) and fold continuity
--------------------------------------------------------------------------------

-- Whether `spec` holds a `list` or `table` block with id `blockId`.
function S.hasDetailTarget(spec, blockId)
    if type(spec) ~= 'table' or type(spec.blocks) ~= 'table' or type(blockId) ~= 'string' then return false end
    for _, b in ipairs(spec.blocks) do
        if type(b) == 'table' and b.id == blockId and (b.type == 'list' or b.type == 'table') then
            return true
        end
    end
    return false
end

-- Which entries of an app's screen stack are drawn: { main = top index, left = index under it, highlight }.
-- Two panes only on an open book, and only when the top's `detailOf` names a block of the screen under it.
-- The answer depends on the stack and the fold only, so folding never redraws a screen from scratch.
function S.panes(stack, model, fold)
    local n = type(stack) == 'table' and #stack or 0
    if n == 0 then return {} end
    local top = stack[n]
    local under = stack[n - 1]
    if model == 'book' and fold == 'open' and under and type(top) == 'table' and type(top.spec) == 'table'
        and S.hasDetailTarget(under.spec, top.spec.detailOf) then
        return { main = n, left = n - 1, highlight = top.spec.detailItem }
    end
    return { main = n }
end

--------------------------------------------------------------------------------
-- Frame placement: fit, drawn scale and own clamp
--------------------------------------------------------------------------------

local function rawFit(w, h, vw, vh)
    local m = 0.048 * vh
    return math.min((vh - m) / h, (vw - m) / w)
end

function S.calcFit(w, h, vw, vh)
    return math.max(0, math.min(1, rawFit(w, h, vw, vh)))
end

-- The frame is scaled by `fit`, then by the layout scale.
function S.drawnScale(placeScale, fit)
    local scale = tonumber(placeScale) or 1
    local f = tonumber(fit) or 1
    return scale * f
end

-- Top-left corner and scale of the frame in viewport px. `place` is the last applied layout place
-- ({ x, y, ax, ay, scale }, fractions of the viewport) or nil for `position`. The result is shifted inside
-- the viewport and never written back: the caller's place is not changed and nothing is saved.
function S.frameRect(place, position, w, h, vw, vh)
    local fw, fh = tonumber(w) or 392, tonumber(h) or 812
    local fit = S.calcFit(fw, fh, vw, vh)
    local hasPlace = type(place) == 'table' and tonumber(place.x) ~= nil and tonumber(place.y) ~= nil
    local scale = S.drawnScale(hasPlace and place.scale or 1, fit)
    scale = math.max(0.05, math.min(scale, rawFit(fw, fh, vw, vh)))
    local dw, dh = fw * scale, fh * scale
    local margin = 0.024 * vh
    local x, y
    if hasPlace then
        x = place.x * vw - (tonumber(place.ax) or 0) * dw
        y = place.y * vh - (tonumber(place.ay) or 0) * dh
    else
        x = position == 'bottom-left' and 24 or (vw - 24 - dw)
        y = vh - 24 - dh
    end
    x = math.max(margin, math.min(x, vw - margin - dw))
    y = math.max(margin, math.min(y, vh - margin - dh))
    return { x = x, y = y, scale = scale }
end

--------------------------------------------------------------------------------
-- Lock screen and notification history
--------------------------------------------------------------------------------

function S.unreadCount(history, seenAt)
    local mark = tonumber(seenAt) or 0
    local n = 0
    if type(history) == 'table' then
        for _, e in ipairs(history) do
            if type(e) == 'table' and (tonumber(e.at) or 0) > mark then n = n + 1 end
        end
    end
    return n
end

-- The lock screen shows on open only when it is enabled and something is waiting (a badge or an unread entry).
function S.shouldLock(enabled, badges, history, seenAt)
    if enabled ~= true then return false end
    if type(badges) == 'table' then
        for _, count in pairs(badges) do
            if (tonumber(count) or 0) > 0 then return true end
        end
    end
    return S.unreadCount(history, seenAt) > 0
end

return ShellLogic
