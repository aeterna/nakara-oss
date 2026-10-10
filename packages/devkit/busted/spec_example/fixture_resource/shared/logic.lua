-- Pure logic: no natives, loadable by stock Lua.
CounterLogic = {}

--- Returns true when `count` pings already happened inside the current window.
function CounterLogic.overLimit(count, max)
    return count >= max
end

return CounterLogic
