local M = {}

--- insert values into a table.
-- similar to `table.insert` but inserts values from given table `values`,
-- not the object itself, into table `t` at position `pos`.
-- @within Copying
-- @array t the list
-- @int[opt] position (default is at end)
-- @array values
function M.insertvalues(t, ...)
  local pos, values
  if select('#', ...) == 1 then
    pos, values = #t + 1, ...
  else
    pos, values = ...
  end
  if #values > 0 then
    for i = #t, pos, -1 do
      t[i + #values] = t[i]
    end
    local offset = 1 - pos
    for i = pos, pos + #values - 1 do
      t[i] = values[i + offset]
    end
  end
  return t
end

function M.readfile(filename, is_bin)
  local mode = is_bin and 'b' or ''
  local f = assert(io.open(filename, 'r' .. mode))
  local res = assert(f:read('*a'))
  f:close()
  return res
end

function M.tbl_copy(t)
  local res = {}
  for k, v in pairs(t) do
    res[k] = v
  end
  return res
end

M.copy_interpreter_args = function(arguments)
  -- copy non-positive command-line args auto-inserted by Lua interpreter
  if arguments and _G.arg then
    local i = 0
    while _G.arg[i] do
      arguments[i] = _G.arg[i]
      i = i - 1
    end
  end
end

M.split = require('pl.utils').split

M.shuffle = function(t, seed)
  if seed then
    math.randomseed(seed)
  end
  local n = #t
  while n >= 2 do
    local k = math.random(n)
    t[n], t[k] = t[k], t[n]
    n = n - 1
  end
  return t
end

M.urandom = function()
  local f = io.open('/dev/urandom', 'rb')
  if not f then
    return nil
  end
  local s = f:read(4)
  f:close()
  local bytes = { s:byte(1, 4) }
  local value = 0
  for _, v in ipairs(bytes) do
    value = value * 256 + v
  end
  return value
end
return M
