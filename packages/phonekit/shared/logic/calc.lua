-- calc.lua -- Pure calculator logic for aeterna_phonekit.
-- Operator order as typed (no operator precedence, like a phone calculator).
-- Natives-free so stock Lua 5.1+ can test it.

CalcLogic = {}
local C = CalcLogic

--- Format a number to at most 10 significant digits.
--- Falls back to 'Error' if not a finite number.
function C.formatResult(num)
    if type(num) ~= 'number' or num ~= num or num == math.huge or num == -math.huge then
        return 'Error'
    end
    if num == 0 then
        return '0'
    end
    -- Format to 10 significant digits (%g removes trailing zeros automatically)
    local s = string.format('%.10g', num)
    if s == '-0' then
        s = '0'
    end
    return s
end

--- Perform a single binary arithmetic operation.
--- Returns result number, or nil, 'Error' if division by zero or invalid.
function C.operate(a, op, b)
    local numA = tonumber(a)
    local numB = tonumber(b)
    if not numA or not numB then
        return nil, 'Error'
    end

    if op == '+' then
        return numA + numB
    elseif op == '-' then
        return numA - numB
    elseif op == '*' or op == '×' then
        return numA * numB
    elseif op == '/' or op == '÷' then
        if numB == 0 then
            return nil, 'Error'
        end
        return numA / numB
    end

    return nil, 'Error'
end

--- Apply percent to a value, taking previous accumulator and operator into account.
--- When chained after + or -: a + b % => a + (a * b / 100).
--- Otherwise: val / 100.
function C.applyPercent(val, accumulator, op)
    local num = tonumber(val) or 0
    if accumulator ~= nil and (op == '+' or op == '-') then
        return accumulator * (num / 100)
    end
    return num / 100
end

--- Create a new stateful calculator instance.
function C.create()
    local calc = {
        display = '0',
        accumulator = nil,
        operator = nil,
        newNumber = true,
        isError = false,
    }

    function calc:reset()
        self.display = '0'
        self.accumulator = nil
        self.operator = nil
        self.newNumber = true
        self.isError = false
    end

    function calc:input(key)
        local k = tostring(key)

        -- If currently in error state, pressing C or AC or a digit resets
        if self.isError then
            if k == 'C' or k == 'AC' then
                self:reset()
                return self.display
            elseif k:match('^%d$') then
                self:reset()
                self.display = k
                self.newNumber = false
                return self.display
            else
                return self.display
            end
        end

        -- Clear keys
        if k == 'C' or k == 'AC' then
            if not self.newNumber and self.display ~= '0' and k == 'C' then
                self.display = '0'
                self.newNumber = true
            else
                self:reset()
            end
            return self.display
        end

        -- Digits
        if k:match('^%d$') then
            if self.newNumber then
                self.display = k
                self.newNumber = false
            else
                if self.display == '0' then
                    self.display = k
                else
                    if #self.display < 16 then
                        self.display = self.display .. k
                    end
                end
            end
            return self.display
        end

        -- Decimal point
        if k == '.' then
            if self.newNumber then
                self.display = '0.'
                self.newNumber = false
            else
                if not self.display:find('%.') then
                    self.display = self.display .. '.'
                end
            end
            return self.display
        end

        -- Toggle sign (+/-)
        if k == '+/-' or k == '±' then
            local n = tonumber(self.display) or 0
            n = -n
            self.display = C.formatResult(n)
            return self.display
        end

        -- Percent (%)
        if k == '%' then
            local n = tonumber(self.display) or 0
            local pct = C.applyPercent(n, self.accumulator, self.operator)
            self.display = C.formatResult(pct)
            return self.display
        end

        -- Operators (+, -, *, /, ×, ÷)
        if k == '+' or k == '-' or k == '*' or k == '/' or k == '×' or k == '÷' then
            local currentVal = tonumber(self.display) or 0
            if self.accumulator ~= nil and not self.newNumber and self.operator ~= nil then
                -- Evaluate preceding operation immediately (operator order as typed)
                local res, err = C.operate(self.accumulator, self.operator, currentVal)
                if not res then
                    self.isError = true
                    self.display = 'Error'
                    self.accumulator = nil
                    self.operator = nil
                    self.newNumber = true
                    return self.display
                end
                self.accumulator = res
                self.display = C.formatResult(res)
            else
                self.accumulator = currentVal
            end
            self.operator = k
            self.newNumber = true
            return self.display
        end

        -- Equals (=)
        if k == '=' then
            if self.operator ~= nil and self.accumulator ~= nil then
                local currentVal = tonumber(self.display) or 0
                local res, err = C.operate(self.accumulator, self.operator, currentVal)
                if not res then
                    self.isError = true
                    self.display = 'Error'
                    self.accumulator = nil
                    self.operator = nil
                    self.newNumber = true
                    return self.display
                end
                self.display = C.formatResult(res)
                self.accumulator = nil
                self.operator = nil
                self.newNumber = true
            end
            return self.display
        end

        return self.display
    end

    function calc:feed(keys)
        if type(keys) == 'table' then
            for i = 1, #keys do
                self:input(keys[i])
            end
        end
        return self.display
    end

    return calc
end

C.new = C.create

return CalcLogic
