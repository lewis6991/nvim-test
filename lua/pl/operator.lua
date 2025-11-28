--- Lua operators available as functions.
--
-- (similar to the Python module of the same name)
--
-- There is a module field `optable` which maps the operator strings
-- onto these functions, e.g. `operator.optable['()']==operator.call`
--
-- Operator strings like '>' and '{}' can be passed to most Penlight functions
-- expecting a function argument.

local M = {}

---@param fn any
---@vararg any
function M.call(fn, ...)
  return fn(...)
end
---@param t any
---@param k any
function M.index(t, k)
  return t[k]
end
---@param a any
---@param b any
function M.eq(a, b)
  return a == b
end
---@param a any
---@param b any
function M.neq(a, b)
  return a ~= b
end
---@param a any
---@param b any
function M.lt(a, b)
  return a < b
end
---@param a any
---@param b any
function M.le(a, b)
  return a <= b
end
---@param a any
---@param b any
function M.gt(a, b)
  return a > b
end
---@param a any
---@param b any
function M.ge(a, b)
  return a >= b
end
---@param a any
function M.len(a)
  return #a
end
---@param a any
---@param b any
function M.add(a, b)
  return a + b
end
---@param a any
---@param b any
function M.sub(a, b)
  return a - b
end
---@param a any
---@param b any
function M.mul(a, b)
  return a * b
end
---@param a any
---@param b any
function M.div(a, b)
  return a / b
end
---@param a any
---@param b any
function M.pow(a, b)
  return a ^ b
end
---@param a any
---@param b any
function M.mod(a, b)
  return a % b
end
---@param a any
---@param b any
function M.concat(a, b)
  return a .. b
end
---@param a any
function M.unm(a)
  return -a
end
---@param a any
function M.lnot(a)
  return not a
end
---@param a any
---@param b any
function M.land(a, b)
  return a and b
end
---@param a any
---@param b any
function M.lor(a, b)
  return a or b
end

function M.table(...)
  return { ... }
end

--- match two strings **~**.
-- uses @{string.find}
---@param a any
---@param b any
function M.match(a, b)
  return string.find(a, b) ~= nil
end
---@vararg any
function M.nop(...)
  return ...
end

--- Map from operator symbol to function.
-- Most of these map directly from operators;
-- But note these extras
--
--  * __'()'__  `call`
--  * __'[]'__  `index`
--  * __'{}'__ `table`
--  * __'~'__   `match`
--
--- optable table
M.optable = {
  ['+'] = M.add,
  ['-'] = M.sub,
  ['*'] = M.mul,
  ['/'] = M.div,
  ['%'] = M.mod,
  ['^'] = M.pow,
  ['..'] = M.concat,
  ['()'] = M.call,
  ['[]'] = M.index,
  ['<'] = M.lt,
  ['<='] = M.le,
  ['>'] = M.gt,
  ['>='] = M.ge,
  ['=='] = M.eq,
  ['~='] = M.neq,
  ['#'] = M.len,
  ['and'] = M.land,
  ['or'] = M.lor,
  ['{}'] = M.table,
  ['~'] = M.match,
  [''] = M.nop,
}

return M
