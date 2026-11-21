-- aeterna_camera client: the base-game phone camera. Native names and control ids are constants here.
-- Which of them work on FXServer Enhanced is not verified yet (spec smoke step 1).

CameraViewfinder = {}
local V = CameraViewfinder

V.PHONE_TYPE = 0           -- CreateMobilePhone model
V.CONTROL_SELECT = 176     -- INPUT_CELLPHONE_SELECT: shutter
V.CONTROL_SELFIE = 184     -- INPUT_CELLPHONE_CAMERA_SELFIE: switch camera
V.CONTROL_CANCEL = 177     -- INPUT_CELLPHONE_CANCEL: close
V.CONTROL_PAUSE = 200      -- INPUT_FRONTEND_PAUSE_ALTERNATE (ESC): close instead of the pause menu

-- CELL_CAM_ACTIVATE_SELFIE_MODE (0x2491A93618B7D838); older runtimes name it CellFrontCamActivate.
function V.setSelfie(on)
    if type(CellCamActivateSelfieMode) == 'function' then
        CellCamActivateSelfieMode(on == true)
    elseif type(CellFrontCamActivate) == 'function' then
        CellFrontCamActivate(on == true)
    end
end

function V.start()
    CreateMobilePhone(V.PHONE_TYPE)
    CellCamActivate(true, true)
    V.setSelfie(false)
end

function V.stop()
    V.setSelfie(false)
    CellCamActivate(false, false)
    DestroyMobilePhone()
end

-- Called every frame while the viewfinder is up.
function V.frame()
    DisableControlAction(0, V.CONTROL_PAUSE, true)
end

function V.read()
    return {
        shutter = IsControlJustPressed(0, V.CONTROL_SELECT),
        switch = IsControlJustPressed(0, V.CONTROL_SELFIE),
        close = IsControlJustPressed(0, V.CONTROL_CANCEL) or IsDisabledControlJustPressed(0, V.CONTROL_PAUSE),
    }
end

-- Key text for a hint: the player's binding of `command` (optional) when set, else the base-game control's button.
function V.keyText(command, control)
    local function text(hash)
        local ok, raw = pcall(GetControlInstructionalButton, 0, hash, true)
        if not ok or type(raw) ~= 'string' then return nil end
        local key = raw:gsub('^[tb]_', '')
        if key == '' or key == '-1' or key == 'NULL' then return nil end
        return key
    end
    return (command and text(GetHashKey(command) | 0x80000000)) or text(control) or ''
end
