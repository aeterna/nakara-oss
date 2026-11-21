-- exitkeys.lua -- Pure logic for aeterna_phonekit exit contract key decisions.
-- Natives-free so stock Lua 5.1+ can test it.

ExitKeysLogic = {}
local E = ExitKeysLogic

function E.isFKey(code)
    return type(code) == 'string' and code:match('^F%d+$') ~= nil
end

function E.decide(state, input)
    state = state or {}
    local code, isHomeBar, isRMB, isF
    if type(input) == 'table' then
        code = input.code or input.key
        isHomeBar, isRMB = input.isHomeBar == true, input.isRMB == true
        isF = input.isFKey or E.isFKey(code)
    else
        code = tostring(input or '')
        isHomeBar = (code == 'HomeBar' or code == 'homebar')
        isRMB = (code == 'RightMouse' or code == 'rmb')
        isF = E.isFKey(code)
    end

    if code == 'Escape' or code == 'ESC' then return 'close' end

    if isHomeBar then
        if state.screen == 'cc' then return 'close_cc' end
        if state.screen == 'lock' or state.screen == 'home' then return 'close' end
        return state.screen == 'app' and 'home' or 'close'
    end

    if code == 'Backspace' or code == 'backspace' then
        if state.isFieldFocused then return 'edit' end
        if state.screen == 'cc' then return 'close_cc' end
        if (state.model == 'keypad' or state.model == 'burner') and state.screen == 'home' then return 'close' end
        return 'back'
    end

    if isRMB then
        return state.screen == 'cc' and 'close_cc' or 'back'
    end

    if state.openKeyCode and code == state.openKeyCode then
        return (state.isFieldFocused and not isF) and 'edit' or 'close'
    end

    return 'none'
end

return ExitKeysLogic
