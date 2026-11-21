-- aeterna_radial client input: control ids and the per-frame read while the menu is open.
-- Frontend controls carry both keyboard and gamepad, so one read serves both.

RadialInput = {}
local I = RadialInput

I.STICK_X = 195   -- INPUT_FRONTEND_AXIS_X (left stick)
I.STICK_Y = 196   -- INPUT_FRONTEND_AXIS_Y (left stick, up is negative)
I.LEFT = 189      -- INPUT_FRONTEND_LEFT (arrow left, d-pad left)
I.RIGHT = 190     -- INPUT_FRONTEND_RIGHT (arrow right, d-pad right)
I.ACCEPT = 201    -- INPUT_FRONTEND_ACCEPT (Enter, A)
I.CANCEL = 194    -- INPUT_FRONTEND_RRIGHT (Backspace, B)
I.ESCAPE = 200    -- INPUT_FRONTEND_PAUSE_ALTERNATE (Esc)
I.ESCAPE_ALT = 322 -- INPUT_REPLAY_TOGGLE (Esc)
I.PAUSE = 199     -- INPUT_FRONTEND_PAUSE (P, Start)

-- Camera look, weapon fire and the controls radial reads itself. Movement and driving stay live.
I.BLOCKED = {
    1, 2, 106,                         -- look (mouse, vehicle mouse override)
    24, 25, 37, 47, 58, 257, 263,      -- attack, aim, weapon wheel, detonate, throw
    140, 141, 142, 143,                -- melee
    68, 69, 70, 91, 92,                -- vehicle and passenger weapons
    I.LEFT, I.RIGHT, I.ACCEPT, I.CANCEL, I.ESCAPE, I.ESCAPE_ALT, I.PAUSE,
}

function I.disableFrame()
    for i = 1, #I.BLOCKED do
        DisableControlAction(0, I.BLOCKED[i], true)
    end
end

function I.read()
    return {
        x = GetDisabledControlNormal(0, I.STICK_X),
        y = GetDisabledControlNormal(0, I.STICK_Y),
        left = IsDisabledControlJustReleased(0, I.LEFT),
        right = IsDisabledControlJustReleased(0, I.RIGHT),
        accept = IsDisabledControlJustReleased(0, I.ACCEPT),
        cancel = IsDisabledControlJustReleased(0, I.CANCEL),
        escape = IsDisabledControlJustReleased(0, I.ESCAPE) or IsDisabledControlJustReleased(0, I.ESCAPE_ALT),
    }
end

return RadialInput
