--- Lua operators available as functions.
--
-- (similar to the Python module of the same name)
--
-- There is a module field `optable` which maps the operator strings
-- onto these functions, e.g. `operator.optable['()']==operator.call`
--
-- Operator strings like '>' and '{}' can be passed to most Penlight functions
-- expecting a function argument.
--
--- @module pl.operator

local strfind = string.find

local operator = {}

--- apply function to some arguments **()**
--- @param fn a function or callable object
--- @param ... arguments
--- @return any
function operator.call(fn, ...)
  return fn(...)
end

--- get the indexed value from a table **[]**
--- @param t a table or any indexable object
--- @param k the key
--- @return any
function operator.index(t, k)
  return t[k]
end

--- returns true if arguments are equal **==**
--- @param a value

--- @param b any
--- @return any
function operator.eq(a, b)
  return a == b
end

--- returns true if arguments are not equal **~=**
--- @param a value

--- @param b any
--- @return any
function operator.neq(a, b)
  return a ~= b
end

--- returns true if a is less than b **<**
--- @param a value

--- @param b any
--- @return any
function operator.lt(a, b)
  return a < b
end

--- returns true if a is less or equal to b **<=**
--- @param a value

--- @param b any
--- @return any
function operator.le(a, b)
  return a <= b
end

--- returns true if a is greater than b **>**
--- @param a value

--- @param b any
--- @return any
function operator.gt(a, b)
  return a > b
end

--- returns true if a is greater or equal to b **>=**
--- @param a value

--- @param b any
--- @return any
function operator.ge(a, b)
  return a >= b
end

--- returns length of string or table **#**
--- @param a a string or a table
--- @return any
function operator.len(a)
  return #a
end

--- add two values **+**
--- @param a value

--- @param b any
--- @return any
function operator.add(a, b)
  return a + b
end

--- subtract b from a **-**
--- @param a value

--- @param b any
--- @return any
function operator.sub(a, b)
  return a - b
end

--- multiply two values __*__
--- @param a value

--- @param b any
--- @return any
function operator.mul(a, b)
  return a * b
end

--- divide first value by second **/**
--- @param a value

--- @param b any
--- @return any
function operator.div(a, b)
  return a / b
end

--- raise first to the power of second **^**
--- @param a value

--- @param b any
--- @return any
function operator.pow(a, b)
  return a ^ b
end

--- modulo; remainder of a divided by b **%**
--- @param a value

--- @param b any
--- @return any
function operator.mod(a, b)
  return a % b
end

--- concatenate two values (either strings or `__concat` defined) **..**
--- @param a value

--- @param b any
--- @return any
function operator.concat(a, b)
  return a .. b
end

--- return the negative of a value **-**
--- @param a value
--- @return any
function operator.unm(a)
  return -a
end

--- false if value evaluates as true **not**
--- @param a value
--- @return any
function operator.lnot(a)
  return not a
end

--- true if both values evaluate as true **and**
--- @param a value

--- @param b any
--- @return any
function operator.land(a, b)
  return a and b
end

--- true if either value evaluate as true **or**
--- @param a value

--- @param b any
--- @return any
function operator.lor(a, b)
  return a or b
end

--- make a table from the arguments **{}**
--- @param ... non-nil arguments
--- @return a table
function operator.table(...)
  return { ... }
end

--- match two strings **~**.
-- uses @{string.find}
--- @param a any

--- @return any
--- @param b any
function operator.match(a, b)
  return strfind(a, b) ~= nil
end

--- the null operation.
--- @param ... arguments
--- @return the arguments
function operator.nop(...)
  return ...
end

---- Map from operator symbol to function.
-- Most of these map directly from operators;
-- But note these extras
--
--  * __'()'__  `call`
--  * __'[]'__  `index`
--  * __'{}'__ `table`
--  * __'~'__   `match`
--
--- @table optable
--- @field operator
operator.optable = {
  ['+'] = operator.add,
  ['-'] = operator.sub,
  ['*'] = operator.mul,
  ['/'] = operator.div,
  ['%'] = operator.mod,
  ['^'] = operator.pow,
  ['..'] = operator.concat,
  ['()'] = operator.call,
  ['[]'] = operator.index,
  ['<'] = operator.lt,
  ['<='] = operator.le,
  ['>'] = operator.gt,
  ['>='] = operator.ge,
  ['=='] = operator.eq,
  ['~='] = operator.neq,
  ['#'] = operator.len,
  ['and'] = operator.land,
  ['or'] = operator.lor,
  ['{}'] = operator.table,
  ['~'] = operator.match,
  [''] = operator.nop,
}

return operator
