-- Pure logic for aeterna_layout: coordinate math, anchor selection, clamping, grid snapping,
-- schema validation, element registry and session/KVP persistence. Natives-free for stock Lua 5.1+.

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

function L.createRegistry(opts)
    opts = type(opts) == 'table' and opts or {}
    local cfg = type(opts.config) == 'table' and opts.config or {}
    local warnFn = opts.warn
    local onApply = type(opts.onApply) == 'function' and opts.onApply or function() end
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
    }

    function reg:setSavedPlaces(places)
        self.savedPlaces = copyPlacesMap(places)
    end

    function reg:getSavedPlaces()
        return copyPlacesMap(self.savedPlaces)
    end

    function reg:countElements()
        return self.count
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
        }
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
        local defaultPlace = {
            x = cleanDef.x,
            y = cleanDef.y,
            ax = cleanDef.ax,
            ay = cleanDef.ay,
            scale = cleanDef.scale or 1.0,
            hidden = false,
        }
        local place
        if existing and self.session then
            place = copyPlace(existing.place)
        else
            place = sanitizeSavedPlace(self.savedPlaces[key], cleanDef, scaleCfg) or defaultPlace
        end

        if not existing then
            self.count = self.count + 1
            self.order[#self.order + 1] = key
        end

        self.elements[key] = {
            key = key,
            owner = owner,
            id = cleanDef.id,
            def = cleanDef,
            place = copyPlace(place),
        }

        if self.session and self.session.snapshot[key] == nil then
            self.session.snapshot[key] = copyPlace(place)
        end

        onApply(owner, cleanDef.id, copyPlace(place))
        return true, nil, copyPlace(place)
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
        for i = 1, #self.order do
            local key = self.order[i]
            local el = self.elements[key]
            if el then
                out[#out + 1] = {
                    owner = el.owner,
                    id = el.id,
                    label = el.def.label,
                    w = el.def.w,
                    h = el.def.h,
                    x = el.place.x,
                    y = el.place.y,
                    ax = el.place.ax,
                    ay = el.place.ay,
                    scale = el.place.scale,
                    hidden = el.place.hidden,
                    scalable = el.def.scalable,
                    hideable = el.def.hideable,
                    defaultPlace = {
                        x = el.def.x,
                        y = el.def.y,
                        ax = el.def.ax,
                        ay = el.def.ay,
                        scale = el.def.scale or 1.0,
                        hidden = false,
                    },
                }
            end
        end
        return out
    end

    function reg:beginSession()
        local snap = {}
        for i = 1, #self.order do
            local key = self.order[i]
            local el = self.elements[key]
            if el then
                snap[key] = copyPlace(el.place)
            end
        end
        self.session = {
            snapshot = snap,
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

        local applied = copyPlace(el.place)
        onApply(el.owner, el.id, applied)
        return true, nil, copyPlace(applied)
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
        local applied = copyPlace(el.place)
        onApply(el.owner, el.id, applied)
        return true, nil, copyPlace(applied)
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
            el.place = {
                x = el.def.x,
                y = el.def.y,
                ax = el.def.ax,
                ay = el.def.ay,
                scale = el.def.scale or 1.0,
                hidden = false,
            }
            local applied = copyPlace(el.place)
            onApply(el.owner, el.id, applied)
            return true, nil, copyPlace(applied)
        end

        -- Reset all registered elements inside the editor session; Done persists the result.
        for i = 1, #self.order do
            local key = self.order[i]
            local el = self.elements[key]
            if el then
                el.place = {
                    x = el.def.x,
                    y = el.def.y,
                    ax = el.def.ax,
                    ay = el.def.ay,
                    scale = el.def.scale or 1.0,
                    hidden = false,
                }
                onApply(el.owner, el.id, copyPlace(el.place))
            end
        end
        return true, nil, copyPlacesMap(self.savedPlaces)
    end

    function reg:commitSession()
        for i = 1, #self.order do
            local key = self.order[i]
            local el = self.elements[key]
            if el then
                local defaultPlace = {
                    x = el.def.x,
                    y = el.def.y,
                    ax = el.def.ax,
                    ay = el.def.ay,
                    scale = el.def.scale or 1.0,
                    hidden = false,
                }
                if placesMatch(el.place, defaultPlace) then
                    self.savedPlaces[key] = nil
                else
                    self.savedPlaces[key] = copyPlace(el.place)
                end
            end
        end
        self.session = nil
        local snapshotToSave = copyPlacesMap(self.savedPlaces)
        savePlacesFn(snapshotToSave)
        return true, snapshotToSave
    end

    function reg:cancelSession()
        if self.session and type(self.session.snapshot) == 'table' then
            for i = 1, #self.order do
                local key = self.order[i]
                local el = self.elements[key]
                local snap = self.session.snapshot[key]
                if el and snap then
                    el.place = copyPlace(snap)
                    onApply(el.owner, el.id, copyPlace(el.place))
                end
            end
        end
        self.session = nil
        return true
    end

    return reg
end

return L
