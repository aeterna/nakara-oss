-- shared/logic/compass.lua -- natives-free compass tape maths (spec aeterna_hudkit.md § Compass tape).
-- html/app.js renderCompass() draws the tape with the same formulas; keep the two in step.

CompassLogic = CompassLogic or {}

CompassLogic.SPAN_MIN = 60
CompassLogic.SPAN_MAX = 180
CompassLogic.SPAN_DEFAULT = 120
CompassLogic.TICK_STEP = 15

local LABELS = { [0] = 'N', [45] = 'NE', [90] = 'E', [135] = 'SE', [180] = 'S', [225] = 'SW', [270] = 'W', [315] = 'NW' }

--- Whole degrees in 0-359 (0 = N, growing clockwise). Non-numbers read as 0.
function CompassLogic.normalize(deg)
    local d = tonumber(deg) or 0
    return math.floor(d + 0.5) % 360
end

--- GetGameplayCamRot z grows counter-clockwise; the tape wants clockwise degrees.
function CompassLogic.fromCamRot(z)
    return CompassLogic.normalize(360 - (tonumber(z) or 0))
end

--- Span clamped to 60-180; a non-number is the default 120.
function CompassLogic.clampSpan(span)
    local s = tonumber(span)
    if not s then return CompassLogic.SPAN_DEFAULT end
    if s < CompassLogic.SPAN_MIN then return CompassLogic.SPAN_MIN end
    if s > CompassLogic.SPAN_MAX then return CompassLogic.SPAN_MAX end
    return s
end

--- Signed position of `tickDeg` on a tape centred on `heading`, as a fraction of the tape width:
--- 0 = centre mark, -0.5 = left edge, 0.5 = right edge. Uses the shortest way round.
function CompassLogic.offset(tickDeg, heading, span)
    local s = CompassLogic.clampSpan(span)
    local delta = ((tonumber(tickDeg) or 0) - (tonumber(heading) or 0) + 540) % 360 - 180
    return delta / s
end

--- Direction code ('N' … 'NW') for a multiple of 45 degrees, else nil.
function CompassLogic.label(deg)
    return LABELS[math.floor(tonumber(deg) or -1) % 360]
end

--- Locale key (hudkit.dir.*) for a multiple of 45 degrees, else nil.
function CompassLogic.labelKey(deg)
    local code = CompassLogic.label(deg)
    return code and ('hudkit.dir.' .. code:lower()) or nil
end

--- Ticks on the visible tape, left to right: { deg = 0-359, offset = -0.5..0.5, label = code|nil }.
function CompassLogic.visibleTicks(heading, span)
    local s = CompassLogic.clampSpan(span)
    local h = tonumber(heading) or 0
    local step = CompassLogic.TICK_STEP
    local first = math.ceil((h - s / 2) / step) * step
    local list = {}
    local t = first
    while t <= h + s / 2 do
        local d = t % 360
        list[#list + 1] = { deg = d, offset = (t - h) / s, label = LABELS[d] }
        t = t + step
    end
    return list
end

return CompassLogic
