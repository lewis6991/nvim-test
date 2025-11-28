local inspect = vim and vim.inspect

local function pretty(value)
  if type(value) == 'string' then
    return string.format('%q', value)
  end
  if inspect then
    local ok, result = pcall(inspect, value)
    if ok then
      return result
    end
  end
  return tostring(value)
end

local function deep_equal(a, b)
  if vim and vim.deep_equal then
    return vim.deep_equal(a, b)
  end
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return a == b
  end
  local seen = {}
  for key, value in pairs(a) do
    seen[key] = true
    if not deep_equal(value, b[key]) then
      return false
    end
  end
  for key in pairs(b) do
    if not seen[key] then
      return false
    end
  end
  return true
end

local function fail(message, level)
  error(message or 'assertion failed!', (level or 1) + 1)
end

local function ensure(condition, message, level)
  if not condition then
    fail(message, (level or 1) + 1)
  end
end

local Assert = {
  _parameters = {},
}

function Assert:set_parameter(name, value)
  self._parameters[name] = value
end

function Assert:get_parameter(name)
  return self._parameters[name]
end

function Assert:register(kind, name, fn)
  if type(fn) ~= 'function' then
    error('luassert: register expects a function', 2)
  end

  if kind == 'assertion' or kind == 'modifier' then
    self[name] = function(...)
      return fn(...)
    end
  else
    self[name] = fn
  end
end

function Assert.is_true(value, message)
  ensure(value == true, message or ('expected true, got ' .. pretty(value)), 2)
  return value
end

function Assert.is_false(value, message)
  ensure(value == false, message or ('expected false, got ' .. pretty(value)), 2)
  return value
end

function Assert.is_nil(value, message)
  ensure(value == nil, message or ('expected nil, got ' .. pretty(value)), 2)
  return value
end

function Assert.is_not_nil(value, message)
  ensure(value ~= nil, message or 'expected value to be non-nil', 2)
  return value
end

Assert.True = Assert.is_true
Assert.False = Assert.is_false

local function same(expected, actual, message)
  ensure(
    deep_equal(actual, expected),
    message or ('expected ' .. pretty(expected) .. ', got ' .. pretty(actual)),
    2
  )
  return actual
end

local function not_same(expected, actual, message)
  ensure(
    not deep_equal(actual, expected),
    message or ('did not expect ' .. pretty(actual) .. ' to equal ' .. pretty(expected)),
    2
  )
  return actual
end

local function equal(expected, actual, message)
  ensure(
    actual == expected,
    message or ('expected ' .. pretty(expected) .. ', got ' .. pretty(actual)),
    2
  )
  return actual
end

local function not_equal(expected, actual, message)
  ensure(
    actual ~= expected,
    message or ('did not expect ' .. pretty(actual) .. ' to equal ' .. pretty(expected)),
    2
  )
  return actual
end

Assert.are = {
  same = same,
  equal = equal,
}

Assert.are_not = {
  same = not_same,
  equal = not_equal,
}

function Assert.matches(pattern, actual, message)
  ensure(type(pattern) == 'string', 'matches expects a string pattern', 2)
  ensure(type(actual) == 'string', 'matches expects a string to match against', 2)
  ensure(
    actual:match(pattern) ~= nil,
    message or ('expected ' .. pretty(actual) .. ' to match ' .. pattern),
    2
  )
  return actual
end

function Assert.not_matches(pattern, actual, message)
  ensure(type(pattern) == 'string', 'not_matches expects a string pattern', 2)
  ensure(type(actual) == 'string', 'not_matches expects a string to match against', 2)
  ensure(
    actual:match(pattern) == nil,
    message or ('did not expect ' .. pretty(actual) .. ' to match ' .. pattern),
    2
  )
  return actual
end

function Assert.has_error(fn, ...)
  ensure(type(fn) == 'function', 'has_error expects a function', 2)
  local ok, err = pcall(fn, ...)
  ensure(not ok, 'expected function to raise an error', 2)
  return err
end

return setmetatable(Assert, {
  __call = function(_, value, message)
    if value then
      return value
    end
    fail(message, 2)
  end,
})
