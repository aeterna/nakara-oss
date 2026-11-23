-- Pure logic for aeterna_layout: coordinate math, anchor selection, clamping, grid snapping,
-- schema validation, element registry and session/KVP persistence, 0.2 clamp on size change, presets and snap
-- prefs. Natives-free for stock Lua 5.1+.

LayoutLogic = {}
local L = LayoutLogic

L.VALID_ANCHORS = {
    [0] = true,
    [0.5] = true,
    [1] = true,
}

L.DEFAULT_SNAP = 8
L.DEFAULT_SCALE = {
    min = 0.5,
    max = 2.0,
    step = 0.05,
}
L.DEFAULT_MAX_ELEMENTS = 64
L.MIN_SIZE = 8
L.MAX_SIZE = 2000

local DEF_ALLOWED_KEYS = {
    id = true,
    label = true,
    w = true,
    h = true,
    x = true,
    y = true,
    ax = true,
    ay = true,
    scale = true,
    scalable = true,
    hideable = true,
    owner = true,
}

local MOVED_ALLOWED_KEYS = {
    owner = true,
    id = true,
    x = true,
    y = true,
    ax = true,
    ay = true,
    scale = true,
}

local HIDE_ALLOWED_KEYS = {
    owner = true,
    id = true,
    hidden = true,
}

local RESET_ALLOWED_KEYS = {
    owner = true,
    id = true,
}

local function emitWarn(warnFn, msg, fields)
    if type(warnFn) == 'function' then
        warnFn(msg, fields)
        return
    end
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function isFiniteNumber(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

function L.isValidId(id, maxLen)
    local limit = maxLen or 32
    if type(id) ~= 'string' then return false end
    if #id < 1 or #id > limit then return false end
    return id:match('^[%w_%-]+$') ~= nil
end

function L.isValidAnchor(v)
    return isFiniteNumber(v) and L.VALID_ANCHORS[v] == true
end

-- UTF-8 helpers (portable across Lua 5.1 - 5.4; Thai combining marks count as 0 visible chars)
local function isThaiCombining(b1, b2, b3)
    if b1 ~= 224 then return false end
    if b2 == 184 then
        return b3 == 177 or (b3 >= 180 and b3 <= 186)
    elseif b2 == 185 then
        return b3 >= 135 and b3 <= 142
    end
    return false
end

local function isControlSeq(b1, b2, b3)
    if b1 < 32 or b1 == 127 then return true, 1 end
    if b1 == 226 and b2 == 128 and b3 then
        if (b3 >= 139 and b3 <= 143) or (b3 >= 170 and b3 <= 174) then
            return true, 3
        end
    end
    return false, 0
end

local function utf8SeqLen(b1)
    if not b1 then return 0 end
    if b1 < 128 then return 1 end
    if b1 >= 194 and b1 <= 223 then return 2 end
    if b1 >= 224 and b1 <= 239 then return 3 end
    if b1 >= 240 and b1 <= 244 then return 4 end
    return 1
end

function L.stripControlAndTrim(s)
    if type(s) ~= 'string' then return '' end
    local out = {}
    local i = 1
    local len = #s
    while i <= len do
        local b1 = s:byte(i)
        local b2 = s:byte(i + 1)
        local b3 = s:byte(i + 2)
        local isCtrl, ctrlLen = isControlSeq(b1, b2, b3)
        if isCtrl then
            i = i + ctrlLen
        else
            local seqLen = utf8SeqLen(b1)
            if i + seqLen - 1 > len then
                break
            end
            out[#out + 1] = s:sub(i, i + seqLen - 1)
            i = i + seqLen
        end
    end
    local joined = table.concat(out)
    return joined:match('^%s*(.-)%s*$') or ''
end

function L.textLen(s)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.len) == 'function' then
        return AeternaCore.text.len(s)
    end
    if type(s) ~= 'string' then return 0 end
    local count = 0
    local i = 1
    local len = #s
    while i <= len do
        local b1 = s:byte(i)
        local seqLen = utf8SeqLen(b1)
        if i + seqLen - 1 > len then break end
        if seqLen == 3 then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            if not isThaiCombining(b1, b2, b3) then
                count = count + 1
            end
        else
            count = count + 1
        end
        i = i + seqLen
    end
    return count
end

function L.textCut(s, maxVisible)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.cut) == 'function' then
        return AeternaCore.text.cut(s, maxVisible)
    end
    if type(s) ~= 'string' then return '' end
    if maxVisible <= 0 then return '' end
    local visible = 0
    local i = 1
    local len = #s
    local lastEnd = 0
    while i <= len do
        local b1 = s:byte(i)
        local seqLen = utf8SeqLen(b1)
        if i + seqLen - 1 > len then break end
        local combining = false
        if seqLen == 3 then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            combining = isThaiCombining(b1, b2, b3)
        end
        if combining then
            if visible == 0 then
                i = i + seqLen
            else
                lastEnd = i + seqLen - 1
                i = i + seqLen
            end
        else
            if visible >= maxVisible then
                break
            end
            visible = visible + 1
            lastEnd = i + seqLen - 1
            i = i + seqLen
        end
    end
    if lastEnd == 0 then return '' end
    return s:sub(1, lastEnd)
end

function L.textClean(s, maxLen)
    if AeternaCore and AeternaCore.text and type(AeternaCore.text.clean) == 'function' then
        return AeternaCore.text.clean(s, maxLen)
    end
    local stripped = L.stripControlAndTrim(s)
    if maxLen then
        return L.textCut(stripped, maxLen)
    end
    return stripped
end

function L.resolveSnap(snap)
    if isFiniteNumber(snap) and snap >= 0 then
        return math.floor(snap)
    end
    return L.DEFAULT_SNAP
end

function L.resolveScaleConfig(scaleCfg)
    if type(scaleCfg) ~= 'table' then
        return {
            min = L.DEFAULT_SCALE.min,
            max = L.DEFAULT_SCALE.max,
            step = L.DEFAULT_SCALE.step,
        }
    end
    local minVal = isFiniteNumber(scaleCfg.min) and scaleCfg.min > 0 and scaleCfg.min or L.DEFAULT_SCALE.min
    local maxVal = isFiniteNumber(scaleCfg.max) and scaleCfg.max >= minVal and scaleCfg.max or L.DEFAULT_SCALE.max
    local stepVal = isFiniteNumber(scaleCfg.step) and scaleCfg.step > 0 and scaleCfg.step or L.DEFAULT_SCALE.step
    return {
        min = minVal,
        max = maxVal,
        step = stepVal,
    }
end

function L.resolveMaxElements(maxEl)
    if isFiniteNumber(maxEl) and maxEl >= 1 then
        return math.floor(maxEl)
    end
    return L.DEFAULT_MAX_ELEMENTS
end

--------------------------------------------------------------------------------
-- Coordinate model: placement, anchor choice, clamping, snapping
--------------------------------------------------------------------------------

function L.placeToPixels(place, w, h, screenW, screenH)
    local p = type(place) == 'table' and place or {}
    local scale = isFiniteNumber(p.scale) and p.scale or 1.0
    local ax = isFiniteNumber(p.ax) and p.ax or 0
    local ay = isFiniteNumber(p.ay) and p.ay or 0
    local x = isFiniteNumber(p.x) and p.x or 0
    local y = isFiniteNumber(p.y) and p.y or 0
    local bw = isFiniteNumber(w) and w or 0
    local bh = isFiniteNumber(h) and h or 0
    local sw = bw * scale
    local sh = bh * scale
    local left = x * screenW - ax * sw
    local top = y * screenH - ay * sh
    return left, top, sw, sh
end

L.toPixels = L.placeToPixels

function L.chooseAnchorAxis(pos, span)
    local frac = (isFiniteNumber(span) and span > 0) and (pos / span) or pos
    if frac < (1 / 3) then
        return 0
    elseif frac <= (2 / 3) then
        return 0.5
    else
        return 1
    end
end

function L.chooseAnchor(x, y, screenW, screenH, w, h, scale)
    local s = isFiniteNumber(scale) and scale or 1.0
    local refX = x
    local refY = y
    if isFiniteNumber(w) and isFiniteNumber(h) then
        refX = x + (w * s) * 0.5
        refY = y + (h * s) * 0.5
    end
    local spanW = isFiniteNumber(screenW) and screenW > 0 and screenW or 1
    local spanH = isFiniteNumber(screenH) and screenH > 0 and screenH or 1
    return L.chooseAnchorAxis(refX, spanW), L.chooseAnchorAxis(refY, spanH)
end

L.pickAnchor = L.chooseAnchor

function L.snapValue(v, snap, shiftHeld)
    if shiftHeld == true or not isFiniteNumber(snap) or snap <= 0 then
        return v
    end
    return math.floor(v / snap + 0.5) * snap
end

function L.snapPosition(left, top, snap, shiftHeld)
    return L.snapValue(left, snap, shiftHeld), L.snapValue(top, snap, shiftHeld)
end

L.snap = L.snapPosition

function L.clampPixels(left, top, w, h, scale, screenW, screenH)
    local s = isFiniteNumber(scale) and scale or 1.0
    local sw = (isFiniteNumber(w) and w or 0) * s
    local sh = (isFiniteNumber(h) and h or 0) * s
    local maxLeft = math.max(0, screenW - sw)
    local maxTop = math.max(0, screenH - sh)
    local clampedLeft = math.min(maxLeft, math.max(0, left))
    local clampedTop = math.min(maxTop, math.max(0, top))
    return clampedLeft, clampedTop, sw, sh
end

L.clamp = L.clampPixels

function L.dropToPlace(left, top, w, h, scale, screenW, screenH, opts)
    local s = isFiniteNumber(scale) and scale or 1.0
    local o = type(opts) == 'table' and opts or {}
    local curLeft = left
    local curTop = top
    if o.snap ~= nil then
        curLeft, curTop = L.snapPosition(curLeft, curTop, o.snap, o.shift == true)
    end
    local cLeft, cTop, sw, sh = L.clampPixels(curLeft, curTop, w, h, s, screenW, screenH)
    local ax, ay = L.chooseAnchor(cLeft, cTop, screenW, screenH, w, h, s)
    local x = (isFiniteNumber(screenW) and screenW > 0) and ((cLeft + ax * sw) / screenW) or 0
    local y = (isFiniteNumber(screenH) and screenH > 0) and ((cTop + ay * sh) / screenH) or 0
    x = math.min(1, math.max(0, x))
    y = math.min(1, math.max(0, y))
    return {
        x = x,
        y = y,
        ax = ax,
        ay = ay,
        scale = s,
        hidden = o.hidden == true,
    }
end

L.fromDrop = L.dropToPlace

--------------------------------------------------------------------------------
-- Owner detection & payload schema validation
--------------------------------------------------------------------------------

function L.resolveOwner(invokingResource, payloadOwner, isResourceStartedFn)
    if type(invokingResource) == 'string' and invokingResource ~= '' then
        return true, nil, invokingResource
    end
    if not L.isValidId(payloadOwner, 64) then
        return false, 'owner: required', nil
    end
    if type(isResourceStartedFn) == 'function' and not isResourceStartedFn(payloadOwner) then
        return false, 'owner: resource not started', nil
    end
    return true, nil, payloadOwner
end

local function checkNoExtraKeys(tbl, allowed)
    local extras = {}
    for k in pairs(tbl) do
        if not allowed[k] then
            extras[#extras + 1] = tostring(k)
        end
    end
    if #extras > 0 then
        table.sort(extras)
        return false, extras[1] .. ': not allowed'
    end
    return true, nil
end

function L.validateDef(def, config, warnFn)
    if type(def) ~= 'table' then
        local err = 'def: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    local okExtra, errExtra = checkNoExtraKeys(def, DEF_ALLOWED_KEYS)
    if not okExtra then
        emitWarn(warnFn, 'invalid layout def', { err = errExtra })
        return false, errExtra, nil
    end

    if type(def.id) ~= 'string' then
        local err = 'id: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if not L.isValidId(def.id, 32) then
        local err = 'id: pattern'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if type(def.label) ~= 'string' then
        local err = 'label: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    local strippedLabel = L.stripControlAndTrim(def.label)
    local labelLen = L.textLen(strippedLabel)
    if labelLen < 1 then
        local err = 'label: minLen 1'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if labelLen > 32 then
        local err = 'label: maxLen 32'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    local cleanLabel = L.textClean(def.label, 32)

    if not isFiniteNumber(def.w) then
        local err = 'w: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.w < L.MIN_SIZE then
        local err = 'w: min ' .. tostring(L.MIN_SIZE)
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.w > L.MAX_SIZE then
        local err = 'w: max ' .. tostring(L.MAX_SIZE)
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(def.h) then
        local err = 'h: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.h < L.MIN_SIZE then
        local err = 'h: min ' .. tostring(L.MIN_SIZE)
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.h > L.MAX_SIZE then
        local err = 'h: max ' .. tostring(L.MAX_SIZE)
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(def.x) then
        local err = 'x: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.x < 0 then
        local err = 'x: min 0'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.x > 1 then
        local err = 'x: max 1'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(def.y) then
        local err = 'y: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.y < 0 then
        local err = 'y: min 0'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if def.y > 1 then
        local err = 'y: max 1'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(def.ax) then
        local err = 'ax: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if not L.isValidAnchor(def.ax) then
        local err = 'ax: enum'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(def.ay) then
        local err = 'ay: type'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end
    if not L.isValidAnchor(def.ay) then
        local err = 'ay: enum'
        emitWarn(warnFn, 'invalid layout def', { err = err })
        return false, err, nil
    end

    local scaleCfg = L.resolveScaleConfig(type(config) == 'table' and config.scale or nil)
    local scaleVal = 1.0
    if def.scale ~= nil then
        if not isFiniteNumber(def.scale) then
            local err = 'scale: type'
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        if def.scale < scaleCfg.min then
            local err = 'scale: min ' .. tostring(scaleCfg.min)
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        if def.scale > scaleCfg.max then
            local err = 'scale: max ' .. tostring(scaleCfg.max)
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        scaleVal = def.scale
    end

    local scalable = true
    if def.scalable ~= nil then
        if type(def.scalable) ~= 'boolean' then
            local err = 'scalable: type'
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        scalable = def.scalable
    end

    local hideable = false
    if def.hideable ~= nil then
        if type(def.hideable) ~= 'boolean' then
            local err = 'hideable: type'
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        hideable = def.hideable
    end

    local cleanOwner
    if def.owner ~= nil then
        if not L.isValidId(def.owner, 64) then
            local err = 'owner: pattern'
            emitWarn(warnFn, 'invalid layout def', { err = err })
            return false, err, nil
        end
        cleanOwner = def.owner
    end

    return true, nil, {
        id = def.id,
        label = cleanLabel,
        w = def.w,
        h = def.h,
        x = def.x,
        y = def.y,
        ax = def.ax,
        ay = def.ay,
        scale = scalable and scaleVal or 1.0,
        scalable = scalable,
        hideable = hideable,
        owner = cleanOwner,
    }
end

function L.validateMoved(payload, config, warnFn)
    if type(payload) ~= 'table' then
        local err = 'payload: type'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end

    local okExtra, errExtra = checkNoExtraKeys(payload, MOVED_ALLOWED_KEYS)
    if not okExtra then
        emitWarn(warnFn, 'invalid moved payload', { err = errExtra })
        return false, errExtra, nil
    end

    if not L.isValidId(payload.owner, 64) then
        local err = 'owner: pattern'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if not L.isValidId(payload.id, 32) then
        local err = 'id: pattern'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end

    if not isFiniteNumber(payload.x) or payload.x < 0 or payload.x > 1 then
        local err = not isFiniteNumber(payload.x) and 'x: type' or (payload.x < 0 and 'x: min 0' or 'x: max 1')
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if not isFiniteNumber(payload.y) or payload.y < 0 or payload.y > 1 then
        local err = not isFiniteNumber(payload.y) and 'y: type' or (payload.y < 0 and 'y: min 0' or 'y: max 1')
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if not L.isValidAnchor(payload.ax) then
        local err = isFiniteNumber(payload.ax) and 'ax: enum' or 'ax: type'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if not L.isValidAnchor(payload.ay) then
        local err = isFiniteNumber(payload.ay) and 'ay: enum' or 'ay: type'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end

    local scaleCfg = L.resolveScaleConfig(type(config) == 'table' and config.scale or nil)
    if not isFiniteNumber(payload.scale) then
        local err = 'scale: type'
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if payload.scale < scaleCfg.min then
        local err = 'scale: min ' .. tostring(scaleCfg.min)
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end
    if payload.scale > scaleCfg.max then
        local err = 'scale: max ' .. tostring(scaleCfg.max)
        emitWarn(warnFn, 'invalid moved payload', { err = err })
        return false, err, nil
    end

    return true, nil, {
        owner = payload.owner,
        id = payload.id,
        x = payload.x,
        y = payload.y,
        ax = payload.ax,
        ay = payload.ay,
        scale = payload.scale,
    }
end

function L.validateHide(payload, warnFn)
    if type(payload) ~= 'table' then
        local err = 'payload: type'
        emitWarn(warnFn, 'invalid hide payload', { err = err })
        return false, err, nil
    end

    local okExtra, errExtra = checkNoExtraKeys(payload, HIDE_ALLOWED_KEYS)
    if not okExtra then
        emitWarn(warnFn, 'invalid hide payload', { err = errExtra })
        return false, errExtra, nil
    end

    if not L.isValidId(payload.owner, 64) then
        local err = 'owner: pattern'
        emitWarn(warnFn, 'invalid hide payload', { err = err })
        return false, err, nil
    end
    if not L.isValidId(payload.id, 32) then
        local err = 'id: pattern'
        emitWarn(warnFn, 'invalid hide payload', { err = err })
        return false, err, nil
    end
    if type(payload.hidden) ~= 'boolean' then
        local err = 'hidden: type'
        emitWarn(warnFn, 'invalid hide payload', { err = err })
        return false, err, nil
    end

    return true, nil, {
        owner = payload.owner,
        id = payload.id,
        hidden = payload.hidden,
    }
end

function L.validateReset(payload, warnFn)
    if payload == nil then
        return true, nil, {}
    end
    if type(payload) ~= 'table' then
        local err = 'payload: type'
        emitWarn(warnFn, 'invalid reset payload', { err = err })
        return false, err, nil
    end

    local okExtra, errExtra = checkNoExtraKeys(payload, RESET_ALLOWED_KEYS)
    if not okExtra then
        emitWarn(warnFn, 'invalid reset payload', { err = errExtra })
        return false, errExtra, nil
    end

    if payload.owner == nil and payload.id == nil then
        return true, nil, {}
    end
    if not L.isValidId(payload.owner, 64) then
        local err = 'owner: pattern'
        emitWarn(warnFn, 'invalid reset payload', { err = err })
        return false, err, nil
    end
    if not L.isValidId(payload.id, 32) then
        local err = 'id: pattern'
        emitWarn(warnFn, 'invalid reset payload', { err = err })
        return false, err, nil
    end

    return true, nil, {
        owner = payload.owner,
        id = payload.id,
    }
end

function L.validateEmptyCallback(payload, warnFn)
    if payload == nil then
        return true, nil, {}
    end
    if type(payload) ~= 'table' then
        local err = 'payload: type'
        emitWarn(warnFn, 'invalid callback payload', { err = err })
        return false, err, nil
    end
    local okExtra, errExtra = checkNoExtraKeys(payload, {})
    if not okExtra then
        emitWarn(warnFn, 'invalid callback payload', { err = errExtra })
        return false, errExtra, nil
    end
    return true, nil, {}
end

--------------------------------------------------------------------------------
-- Registry & editor session manager
--------------------------------------------------------------------------------

local function copyPlace(p)
    return {
        x = p.x,
        y = p.y,
        ax = p.ax,
        ay = p.ay,
        scale = p.scale,
        hidden = p.hidden == true,
    }
end

local function copyPlacesMap(map)
    local out = {}
    if type(map) ~= 'table' then return out end
    for k, v in pairs(map) do
        if type(k) == 'string' and type(v) == 'table' then
            out[k] = copyPlace(v)
        end
    end
    return out
end

local function placesMatch(a, b)
    return a.x == b.x
        and a.y == b.y
        and a.ax == b.ax
        and a.ay == b.ay
        and a.scale == b.scale
        and (a.hidden == true) == (b.hidden == true)
end

local function sanitizeSavedPlace(saved, cleanDef, scaleCfg)
    if type(saved) ~= 'table' then return nil end
    if not isFiniteNumber(saved.x) or saved.x < 0 or saved.x > 1 then return nil end
    if not isFiniteNumber(saved.y) or saved.y < 0 or saved.y > 1 then return nil end
    if not L.isValidAnchor(saved.ax) or not L.isValidAnchor(saved.ay) then return nil end
    local scaleVal = 1.0
    if cleanDef.scalable then
        if isFiniteNumber(saved.scale) then
            scaleVal = math.min(scaleCfg.max, math.max(scaleCfg.min, saved.scale))
        end
    end
    local hiddenVal = cleanDef.hideable and (saved.hidden == true) or false
    return {
        x = saved.x,
        y = saved.y,
        ax = saved.ax,
        ay = saved.ay,
        scale = scaleVal,
        hidden = hiddenVal,
    }
end

--------------------------------------------------------------------------------
-- 0.2: place checks, clamp on size change, presets, snap prefs, callback payloads
--------------------------------------------------------------------------------

L.MAX_PRESETS = 8
L.DEFAULT_SNAP_STEPS = { 8, 16, 32 }
L.MAX_SCREEN = 16384

local PLACE_FIELDS = { 'x', 'y', 'ax', 'ay', 'scale', 'hidden' }

-- Splits "<owner>/<id>"; owner per the resource rule (≤ 64), id per the def rule (≤ 32).
function L.parsePlaceKey(key)
    if type(key) ~= 'string' then return nil end
    local owner, id = key:match('^([^/]+)/([^/]+)$')
    if not L.isValidId(owner, 64) or not L.isValidId(id, 32) then return nil end
    return owner, id
end

-- Checks one place with the drop rules. opts.hidden: allow a boolean `hidden`; opts.scaleOptional: default 1.0.
-- Returns ok, field, rule, clean.
function L.checkPlace(place, scaleCfg, opts)
    local o = type(opts) == 'table' and opts or {}
    if type(place) ~= 'table' then return false, nil, 'type', nil end
    local allowed = { x = true, y = true, ax = true, ay = true, scale = true, hidden = o.hidden == true }
    local extras = {}
    for k in pairs(place) do
        if not allowed[k] then extras[#extras + 1] = tostring(k) end
    end
    if #extras > 0 then
        table.sort(extras)
        return false, extras[1], 'not allowed', nil
    end
    for _, f in ipairs({ 'x', 'y' }) do
        if not isFiniteNumber(place[f]) then return false, f, 'type', nil end
        if place[f] < 0 or place[f] > 1 then return false, f, 'out of range', nil end
    end
    for _, f in ipairs({ 'ax', 'ay' }) do
        if not isFiniteNumber(place[f]) then return false, f, 'type', nil end
        if not L.isValidAnchor(place[f]) then return false, f, 'enum', nil end
    end
    local scaleVal = place.scale
    if scaleVal == nil and o.scaleOptional then
        scaleVal = 1.0
    elseif not isFiniteNumber(scaleVal) then
        return false, 'scale', 'type', nil
    end
    if scaleVal < scaleCfg.min or scaleVal > scaleCfg.max then return false, 'scale', 'out of range', nil end
    if place.hidden ~= nil and type(place.hidden) ~= 'boolean' then return false, 'hidden', 'type', nil end
    return true, nil, nil, {
        x = place.x,
        y = place.y,
        ax = place.ax,
        ay = place.ay,
        scale = scaleVal,
        hidden = place.hidden == true,
    }
end

-- Moves the anchor point just far enough that the whole box is on screen (ax/ay unchanged). An axis on which
-- the box is larger than the screen starts at 0 (anchor 0, coordinate 0). Returns a copy and whether it changed.
function L.clampPlace(place, w, h, screenW, screenH)
    local out = {}
    for _, f in ipairs(PLACE_FIELDS) do out[f] = place[f] end
    out.hidden = place.hidden == true
    if not isFiniteNumber(screenW) or not isFiniteNumber(screenH) or screenW <= 0 or screenH <= 0 then
        return out, false
    end
    local scale = isFiniteNumber(out.scale) and out.scale or 1.0
    local changed = false
    local function axis(posKey, anchorKey, size, span)
        if size > span then
            if out[posKey] ~= 0 or out[anchorKey] ~= 0 then
                out[posKey], out[anchorKey] = 0, 0
                changed = true
            end
            return
        end
        local start = out[posKey] * span - out[anchorKey] * size
        local fixed = start
        if start < 0 then
            fixed = 0
        elseif start + size > span then
            fixed = span - size
        end
        if fixed ~= start then
            out[posKey] = math.min(1, math.max(0, (fixed + out[anchorKey] * size) / span))
            changed = true
        end
    end
    axis('x', 'ax', (isFiniteNumber(w) and w or 0) * scale, screenW)
    axis('y', 'ay', (isFiniteNumber(h) and h or 0) * scale, screenH)
    return out, changed
end

local function presetOrder(a, b)
    if a == 'default' then return b ~= 'default' end
    if b == 'default' then return false end
    return a < b
end

-- Config.presets → clean map name → { [key] = place } and the ordered list of names (default first, ≤ 8).
-- A bad name, a bad entry and the presets over the limit are each skipped with one warn.
function L.validatePresets(presets, config, warnFn)
    local scaleCfg = L.resolveScaleConfig(type(config) == 'table' and config.scale or nil)
    local names = {}
    if type(presets) == 'table' then
        for name, entries in pairs(presets) do
            if type(name) ~= 'string' or not L.isValidId(name, 24) then
                emitWarn(warnFn, 'layout preset refused', { preset = tostring(name), err = 'name: pattern' })
            elseif type(entries) ~= 'table' then
                emitWarn(warnFn, 'layout preset refused', { preset = name, err = 'places: type' })
            else
                names[#names + 1] = name
            end
        end
    end
    table.sort(names, presetOrder)
    if #names > L.MAX_PRESETS then
        emitWarn(warnFn, 'layout presets over the limit', { max = L.MAX_PRESETS, count = #names })
        for i = #names, L.MAX_PRESETS + 1, -1 do names[i] = nil end
    end
    local clean = {}
    for _, name in ipairs(names) do
        local out = {}
        local keys = {}
        for key in pairs(presets[name]) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            local ok, field, rule, place = false, 'key', 'pattern', nil
            if L.parsePlaceKey(key) then
                ok, field, rule, place = L.checkPlace(presets[name][key], scaleCfg, { scaleOptional = true })
            end
            if ok then
                out[key] = place
            else
                emitWarn(warnFn, 'layout preset entry skipped', {
                    preset = name, key = tostring(key), err = tostring(field or 'place') .. ': ' .. tostring(rule),
                })
            end
        end
        clean[name] = out
    end
    return clean, names
end

-- Snap steps offered in the editor: Config.snapSteps (positive integers ≤ 256) plus Config.snap when it is on.
function L.resolveSnapSteps(config)
    local cfg = type(config) == 'table' and config or {}
    local seen, steps = {}, {}
    local function addStep(v)
        if isFiniteNumber(v) and v >= 1 and v <= 256 and v == math.floor(v) and not seen[v] then
            seen[v] = true
            steps[#steps + 1] = math.floor(v)
        end
    end
    if type(cfg.snapSteps) == 'table' then
        for _, v in ipairs(cfg.snapSteps) do addStep(v) end
    end
    if #steps == 0 then
        for _, v in ipairs(L.DEFAULT_SNAP_STEPS) do addStep(v) end
    end
    addStep(L.resolveSnap(cfg.snap))
    table.sort(steps)
    return steps
end

function L.isValidSnapStep(step, config)
    if not isFiniteNumber(step) or step ~= math.floor(step) then return false end
    if step == 0 then return true end
    for _, v in ipairs(L.resolveSnapSteps(config)) do
        if v == step then return true end
    end
    return false
end

-- KVP aeterna_layout:prefs:v1 → the snap step; nothing valid saved = Config.snap.
function L.resolveSnapPref(prefs, config)
    if type(prefs) == 'table' and L.isValidSnapStep(prefs.snap, config) then
        return math.floor(prefs.snap)
    end
    return L.resolveSnap(type(config) == 'table' and config.snap or nil)
end

local function refuse(warnFn, what, err)
    emitWarn(warnFn, 'invalid ' .. what .. ' payload', { err = err })
    return false, err, nil
end

local function onlyKeys(payload, allowed, warnFn, what)
    if type(payload) ~= 'table' then return refuse(warnFn, what, 'payload: type') end
    local ok, err = checkNoExtraKeys(payload, allowed)
    if not ok then return refuse(warnFn, what, err) end
    return true
end

function L.validateScreen(payload, warnFn)
    local ok, err = onlyKeys(payload, { w = true, h = true }, warnFn, 'screen')
    if not ok then return false, err, nil end
    for _, f in ipairs({ 'w', 'h' }) do
        local v = payload[f]
        if not isFiniteNumber(v) or v ~= math.floor(v) or v < 1 or v > L.MAX_SCREEN then
            return refuse(warnFn, 'screen', f .. ': integer 1-' .. L.MAX_SCREEN)
        end
    end
    return true, nil, { w = math.floor(payload.w), h = math.floor(payload.h) }
end

function L.validatePresetCallback(payload, warnFn)
    local ok, err = onlyKeys(payload, { name = true }, warnFn, 'preset')
    if not ok then return false, err, nil end
    if not L.isValidId(payload.name, 24) then return refuse(warnFn, 'preset', 'name: pattern') end
    return true, nil, { name = payload.name }
end

function L.validateSnapCallback(payload, config, warnFn)
    local ok, err = onlyKeys(payload, { step = true }, warnFn, 'snap')
    if not ok then return false, err, nil end
    if not L.isValidSnapStep(payload.step, config) then return refuse(warnFn, 'snap', 'step: enum') end
    return true, nil, { step = math.floor(payload.step) }
end

local function defaultPlaceOf(el)
    return {
        x = el.def.x,
        y = el.def.y,
        ax = el.def.ax,
        ay = el.def.ay,
        scale = el.def.scale or 1.0,
        hidden = false,
    }
end

-- A preset or imported place fitted to one element's def (scale 1 when not scalable).
local function fitPlace(place, el, hidden)
    return {
        x = place.x,
        y = place.y,
        ax = place.ax,
        ay = place.ay,
        scale = el.def.scalable and (place.scale or 1.0) or 1.0,
        hidden = el.def.hideable and hidden == true or false,
    }
end

-- Registry of elements. Each element keeps the place the player chose (`place`) and the place last sent to its
-- owner (`applied`), which is `place` clamped to the current screen (0.2). Only `applied` reaches the owner and
-- the editor; outside the editor nothing is ever saved by a clamp.
function L.createRegistry(opts)
    opts = type(opts) == 'table' and opts or {}
    local cfg = type(opts.config) == 'table' and opts.config or {}
    local warnFn = opts.warn
    local onApply = type(opts.onApply) == 'function' and opts.onApply or function() end
    local onClamp = type(opts.onClamp) == 'function' and opts.onClamp or function() end
    local savePlacesFn = type(opts.savePlaces) == 'function' and opts.savePlaces or function() end

    local initial = opts.initialPlaces
    if initial == nil and type(opts.loadPlaces) == 'function' then
        initial = opts.loadPlaces()
    end

    local reg = {
        config = cfg,
        elements = {},
        order = {},
        count = 0,
        savedPlaces = copyPlacesMap(initial),
        session = nil,
        screen = nil,
    }

    local function effectivePlace(self, el)
        if not self.screen then
            return copyPlace(el.place), false
        end
        return L.clampPlace(el.place, el.def.w, el.def.h, self.screen.w, self.screen.h)
    end

    -- Sends the element's effective place to its owner; returns it and whether a clamp changed it.
    local function applyElement(self, el)
        local eff, clamped = effectivePlace(self, el)
        el.applied = copyPlace(eff)
        onApply(el.owner, el.id, copyPlace(eff))
        return eff, clamped
    end

    local function forEachElement(self, fn)
        for i = 1, #self.order do
            local el = self.elements[self.order[i]]
            if el then fn(el, self.order[i]) end
        end
    end

    function reg:setSavedPlaces(places)
        self.savedPlaces = copyPlacesMap(places)
    end

    function reg:getSavedPlaces()
        return copyPlacesMap(self.savedPlaces)
    end

    function reg:countElements()
        return self.count
    end

    -- "<owner>/<id>" of every registered element, in registration order.
    function reg:registeredKeys()
        local out = {}
        forEachElement(self, function(_, key)
            out[#out + 1] = key
        end)
        return out
    end

    function reg:get(owner, id)
        if type(owner) ~= 'string' or type(id) ~= 'string' then return nil end
        local el = self.elements[owner .. '/' .. id]
        if not el then return nil end
        return {
            owner = el.owner,
            id = el.id,
            def = el.def,
            place = copyPlace(el.place),
            applied = copyPlace(el.applied or el.place),
        }
    end

    -- Screen size in CSS px reported by the page. Re-clamps every element and applies the ones whose effective
    -- place changed (it may also come back unclamped on a larger screen).
    function reg:setScreen(w, h)
        if not isFiniteNumber(w) or not isFiniteNumber(h) or w <= 0 or h <= 0 then
            return false
        end
        self.screen = { w = w, h = h }
        forEachElement(self, function(el)
            local eff = effectivePlace(self, el)
            if not el.applied or not placesMatch(eff, el.applied) then
                el.applied = copyPlace(eff)
                onApply(el.owner, el.id, copyPlace(eff))
                onClamp(el.owner, el.id, copyPlace(eff))
            end
        end)
        return true
    end

    function reg:add(owner, def)
        if type(owner) == 'table' and def == nil then
            def = owner
            owner = def.owner
        end
        if not L.isValidId(owner, 64) then
            local err = 'owner: required'
            emitWarn(warnFn, 'layout add refused', { err = err })
            return false, err, nil
        end

        local ok, err, cleanDef = L.validateDef(def, self.config, warnFn)
        if not ok then
            return false, err, nil
        end

        local key = owner .. '/' .. cleanDef.id
        local existing = self.elements[key]
        local maxEl = L.resolveMaxElements(self.config.maxElements)
        if not existing and self.count >= maxEl then
            local limitErr = 'maxElements: max ' .. tostring(maxEl)
            emitWarn(warnFn, 'layout maxElements reached', { owner = owner, id = cleanDef.id, max = maxEl })
            return false, limitErr, nil
        end

        local scaleCfg = L.resolveScaleConfig(self.config.scale)
        local el = { key = key, owner = owner, id = cleanDef.id, def = cleanDef }
        if existing and self.session then
            el.place = copyPlace(existing.place)
        elseif self.session and self.session.pending[key] then
            el.place = fitPlace(self.session.pending[key], el, self.session.pending[key].hidden)
            self.session.pending[key] = nil
        else
            el.place = sanitizeSavedPlace(self.savedPlaces[key], cleanDef, scaleCfg) or defaultPlaceOf(el)
        end

        if not existing then
            self.count = self.count + 1
            self.order[#self.order + 1] = key
        end
        self.elements[key] = el

        if self.session and self.session.snapshot[key] == nil then
            self.session.snapshot[key] = copyPlace(el.place)
        end

        local eff = applyElement(self, el)
        return true, nil, copyPlace(eff)
    end

    function reg:remove(owner, id)
        if type(owner) ~= 'string' or not L.isValidId(id, 32) then
            return false
        end
        local key = owner .. '/' .. id
        if not self.elements[key] then
            return false
        end
        self.elements[key] = nil
        self.count = math.max(0, self.count - 1)
        for i = #self.order, 1, -1 do
            if self.order[i] == key then
                table.remove(self.order, i)
                break
            end
        end
        return true
    end

    function reg:removeByOwner(owner)
        if type(owner) ~= 'string' or owner == '' then
            return 0
        end
        local removed = 0
        for i = #self.order, 1, -1 do
            local key = self.order[i]
            local el = self.elements[key]
            if el and el.owner == owner then
                self.elements[key] = nil
                table.remove(self.order, i)
                self.count = math.max(0, self.count - 1)
                removed = removed + 1
            end
        end
        return removed
    end

    function reg:listElements()
        local out = {}
        forEachElement(self, function(el)
            local shown = el.applied or el.place
            out[#out + 1] = {
                owner = el.owner,
                id = el.id,
                label = el.def.label,
                w = el.def.w,
                h = el.def.h,
                x = shown.x,
                y = shown.y,
                ax = shown.ax,
                ay = shown.ay,
                scale = shown.scale,
                hidden = shown.hidden,
                scalable = el.def.scalable,
                hideable = el.def.hideable,
                defaultPlace = defaultPlaceOf(el),
            }
        end)
        return out
    end

    function reg:beginSession()
        local snap = {}
        forEachElement(self, function(el, key)
            snap[key] = copyPlace(el.place)
        end)
        -- pending: places for elements not registered now (preset or import); replace: Done starts from an
        -- empty saved map (import replaces the session's places).
        self.session = {
            snapshot = snap,
            pending = {},
            replace = false,
        }
        return self:listElements()
    end

    function reg:move(payload)
        local ok, err, clean = L.validateMoved(payload, self.config, warnFn)
        if not ok then
            return false, err, nil
        end
        local key = clean.owner .. '/' .. clean.id
        local el = self.elements[key]
        if not el then
            local notFoundErr = 'element: not found'
            emitWarn(warnFn, 'moved element not in registry', { owner = clean.owner, id = clean.id })
            return false, notFoundErr, nil
        end

        el.place.x = clean.x
        el.place.y = clean.y
        el.place.ax = clean.ax
        el.place.ay = clean.ay
        if el.def.scalable then
            el.place.scale = clean.scale
        else
            el.place.scale = 1.0
        end

        local eff, clamped = applyElement(self, el)
        if clamped then
            onClamp(el.owner, el.id, copyPlace(eff))
        end
        return true, nil, copyPlace(eff)
    end

    function reg:hide(payload)
        local ok, err, clean = L.validateHide(payload, warnFn)
        if not ok then
            return false, err, nil
        end
        local key = clean.owner .. '/' .. clean.id
        local el = self.elements[key]
        if not el then
            local notFoundErr = 'element: not found'
            emitWarn(warnFn, 'hide element not in registry', { owner = clean.owner, id = clean.id })
            return false, notFoundErr, nil
        end
        if not el.def.hideable then
            local hideErr = 'hideable: false'
            emitWarn(warnFn, 'element is not hideable', { owner = clean.owner, id = clean.id })
            return false, hideErr, nil
        end

        el.place.hidden = clean.hidden
        local eff = applyElement(self, el)
        return true, nil, copyPlace(eff)
    end

    function reg:reset(payload)
        local ok, err, clean = L.validateReset(payload, warnFn)
        if not ok then
            return false, err, nil
        end

        if clean.owner and clean.id then
            local key = clean.owner .. '/' .. clean.id
            local el = self.elements[key]
            if not el then
                local notFoundErr = 'element: not found'
                emitWarn(warnFn, 'reset element not in registry', { owner = clean.owner, id = clean.id })
                return false, notFoundErr, nil
            end
            el.place = defaultPlaceOf(el)
            local eff = applyElement(self, el)
            return true, nil, copyPlace(eff)
        end

        -- Reset all registered elements inside the editor session; Done persists the result.
        if self.session then
            self.session.pending = {}
            self.session.replace = false
        end
        forEachElement(self, function(el)
            el.place = defaultPlaceOf(el)
            applyElement(self, el)
        end)
        return true, nil, copyPlacesMap(self.savedPlaces)
    end

    -- Preset (clean map from L.validatePresets): session only. Named elements take the preset place, the others
    -- their default; `hidden` stays as it is. Entries for unregistered elements wait in the session.
    function reg:applyPreset(places)
        if not self.session then
            return false, 'session: none'
        end
        if type(places) ~= 'table' then
            return false, 'preset: type'
        end
        local pending = {}
        for key, p in pairs(places) do
            if not self.elements[key] then
                local saved = self.savedPlaces[key]
                local hidden = type(saved) == 'table' and saved.hidden == true
                pending[key] = { x = p.x, y = p.y, ax = p.ax, ay = p.ay, scale = p.scale or 1.0, hidden = hidden }
            end
        end
        self.session.pending = pending
        self.session.replace = false
        forEachElement(self, function(el, key)
            local hidden = el.place.hidden == true
            el.place = places[key] and fitPlace(places[key], el, hidden) or defaultPlaceOf(el)
            el.place.hidden = el.def.hideable and hidden or false
            applyElement(self, el)
        end)
        return true
    end

    -- Import (clean map from L.decodeImport): session only. Replaces the session's places: elements the text does
    -- not name go to default, and Done saves exactly the text's places.
    function reg:importPlaces(places)
        if not self.session then
            return false, 'session: none'
        end
        if type(places) ~= 'table' then
            return false, 'places: type'
        end
        local pending = {}
        for key, p in pairs(places) do
            if not self.elements[key] then
                pending[key] = copyPlace(p)
            end
        end
        self.session.pending = pending
        self.session.replace = true
        forEachElement(self, function(el, key)
            local p = places[key]
            el.place = p and fitPlace(p, el, p.hidden) or defaultPlaceOf(el)
            applyElement(self, el)
        end)
        return true
    end

    -- Reset all from the menu panel (outside the editor): clears every saved place and saves at once.
    function reg:resetAllSaved()
        if self.session then
            return false, 'session: open'
        end
        self.savedPlaces = {}
        forEachElement(self, function(el)
            el.place = defaultPlaceOf(el)
            applyElement(self, el)
        end)
        savePlacesFn({})
        return true
    end

    function reg:commitSession()
        local session = self.session
        local base = (session and session.replace) and {} or self.savedPlaces
        if session then
            for key, p in pairs(session.pending) do
                if not self.elements[key] then
                    base[key] = copyPlace(p)
                end
            end
        end
        -- Saves what the editor shows (the effective place), only where it differs from the default.
        forEachElement(self, function(el, key)
            local shown = el.applied or el.place
            if placesMatch(shown, defaultPlaceOf(el)) then
                base[key] = nil
            else
                base[key] = copyPlace(shown)
            end
        end)
        self.savedPlaces = base
        self.session = nil
        local snapshotToSave = copyPlacesMap(self.savedPlaces)
        savePlacesFn(snapshotToSave)
        return true, snapshotToSave
    end

    function reg:cancelSession()
        if self.session and type(self.session.snapshot) == 'table' then
            forEachElement(self, function(el, key)
                local snap = self.session.snapshot[key]
                if snap then
                    el.place = copyPlace(snap)
                    applyElement(self, el)
                end
            end)
        end
        self.session = nil
        return true
    end

    return reg
end

return L
