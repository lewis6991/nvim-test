--- Generally useful routines.
-- See  @{01-introduction.md.Generally_useful_functions|the Guide}.
--
-- This module assumes a Lua 5.1 or LuaJIT runtime and inlines the few compatibility
-- helpers that Penlight used to import from `pl.compat`.

local loadstring = _G.loadstring or load

local dir_separator = package.config:sub(1, 1)
local is_windows = dir_separator == '\\'
local lua51 = _VERSION == 'Lua 5.1'
local has_jit = type(jit) == 'table'
local jit52 = has_jit and (not loadstring('local goto = 1'))

if not table.pack then
  ---@vararg any
  function table.pack(...) -- luacheck: ignore
    return { n = select('#', ...), ... }
  end
end

if not table.unpack then
  table.unpack = unpack -- luacheck: ignore
end

if not package.searchpath then
  ---@param name string module name to resolve
  ---@param path string search template such as `package.path`
  ---@param sep? string separator to replace (defaults to `.`)
  ---@param rep? string replacement for the separator (defaults to the system separator)
  ---@return string? resolved path
  ---@return string? error listing the attempted paths
  function package.searchpath(name, path, sep, rep) -- luacheck: ignore
    if type(name) ~= 'string' then
      error(("bad argument #1 to 'searchpath' (string expected, got %s)"):format(type(path)), 2)
    end
    if type(path) ~= 'string' then
      error(("bad argument #2 to 'searchpath' (string expected, got %s)"):format(type(path)), 2)
    end
    if sep ~= nil and type(sep) ~= 'string' then
      error(("bad argument #3 to 'searchpath' (string expected, got %s)"):format(type(path)), 2)
    end
    if rep ~= nil and type(rep) ~= 'string' then
      error(("bad argument #4 to 'searchpath' (string expected, got %s)"):format(type(path)), 2)
    end
    sep = sep or '.'
    rep = rep or dir_separator
    local s, e = name:find(sep, nil, true)
    while s do
      name = name:sub(1, s - 1) .. rep .. name:sub(e + 1, -1)
      s, e = name:find(sep, s + #rep + 1, true)
    end
    local tried = {}
    for m in path:gmatch('[^;]+') do
      local nm = m:gsub('?', name)
      tried[#tried + 1] = nm
      local f = io.open(nm, 'r')
      if f then
        f:close()
        return nm
      end
    end
    return nil, "\tno file '" .. table.concat(tried, "'\n\tno file '") .. "'"
  end
end

if not rawget(_G, 'warn') then
  local enabled = false
  ---@param arg1 any
  ---@vararg any
  local function warn_override(arg1, ...)
    if type(arg1) == 'string' and arg1:sub(1, 1) == '@' then
      if arg1 == '@on' then
        enabled = true
      elseif arg1 == '@off' then
        enabled = false
      end
      return
    end
    if enabled then
      io.stderr:write('Lua warning: ', arg1, ...)
      io.stderr:write('\n')
    end
  end
  rawset(_G, 'warn', warn_override)
end

---@param cmd any
---@param cmd string
---@return boolean success
---@return integer code
local function compat_execute(cmd)
  local res1, res2, res3 = os.execute(cmd)
  if res2 == 'No error' and res3 == 0 and is_windows then
    res3 = -1
  end
  if lua51 and not jit52 then
    if is_windows then
      return res1 == 0, res1
    else
      res1 = res1 > 255 and res1 / 256 or res1
      return res1 == 0, res1
    end
  else
    if is_windows then
      return res3 == 0, res3
    else
      return not not res1, res3
    end
  end
end

local function compat_load_wrapper()
  if lua51 and not has_jit then
    local lua51_load = load
    return function(str, src, mode, env)
      local chunk, err
      if type(str) == 'string' then
        if str:byte(1) == 27 and not (mode or 'bt'):find('b') then
          return nil, 'attempt to load a binary chunk'
        end
        chunk, err = loadstring(str, src)
      else
        chunk, err = lua51_load(str, src)
      end
      if chunk and env then
        setfenv(chunk, env)
      end
      return chunk, err
    end
  else
    return load
  end
end

local compat_load = compat_load_wrapper()

local err_mode = 'default'
local raise
local operators
local _function_factories = {}

local M = {
  _VERSION = '1.14.0',
  lua51 = lua51,
  jit = has_jit,
  jit52 = jit52,
  dir_separator = dir_separator,
  is_windows = is_windows,
  execute = compat_execute,
  load = compat_load,
  setfenv = setfenv,
  getfenv = getfenv,
}

---@class pl.utils.Patterns
---@field FLOAT string
---@field INTEGER string
---@field IDEN string
---@field FILE string
---@type pl.utils.Patterns
M.patterns = {
  FLOAT = '[%+%-%d]%d*%.?%d*[eE]?[%+%-]?%d*', -- floating point number
  INTEGER = '[+%-%d]%d*', -- integer number
  IDEN = '[%a_][%w_]*', -- identifier
  FILE = '[%a%.\\][:%][%w%._%-\\]*', -- file
}

---@class pl.utils.StdMetaTables
---@field List table
---@field Map table
---@field Set table
---@field MultiMap table
---@type pl.utils.StdMetaTables
M.stdmt = {
  List = { _name = 'List' },
  Map = { _name = 'Map' },
  Set = { _name = 'Set' },
  MultiMap = { _name = 'MultiMap' },
}

--- Pack an argument list into a table.
---@type fun(...: any): table
M.pack = table.pack -- added here to be symmetrical with unpack

--- unpack a table and return its contents.
--
-- NOTE: this implementation differs from the Lua implementation in the way
-- that this one DOES honor the `n` field in the table `t`, such that it is 'nil-safe'.
---@param t any
---@param i any
---@param j any
function M.unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

--- print an arbitrary number of arguments using a format.
-- Output will be sent to `stdout`.
---@param fmt any
---@vararg any
function M.printf(fmt, ...)
  M.assert_string(1, fmt)
  M.fprintf(io.stdout, fmt, ...)
end
---@param f any
---@param fmt any
---@vararg any
function M.fprintf(f, fmt, ...)
  M.assert_string(2, fmt)
  f:write(fmt:format(...))
end

do
  ---@param T any
  ---@param k any
  ---@param v any
  ---@param libname any
  local function import_symbol(T, k, v, libname)
    local key = rawget(T, k)
    -- warn about collisions!
    if key and k ~= '_M' and k ~= '_NAME' and k ~= '_PACKAGE' and k ~= '_VERSION' then
      M.fprintf(io.stderr, "warning: '%s.%s' will not override existing symbol\n", libname, k)
      return
    end
    rawset(T, k, v)
  end
  ---@param T any
  ---@param t any
  local function lookup_lib(T, t)
    for k, v in pairs(T) do
      if v == t then
        return k
      end
    end
    return '?'
  end

  local already_imported = {}
  ---@param t any
  ---@param T any
  function M.import(t, T)
    T = T or _G
    t = t or M
    if type(t) == 'string' then
      t = require(t)
    end
    local libname = lookup_lib(T, t)
    if already_imported[t] then
      return
    end
    already_imported[t] = libname
    for k, v in pairs(t) do
      import_symbol(T, k, v, libname)
    end
  end
end
---@param cond any condition tested for truthiness
---@param value1 any value returned when `cond` is truthy
---@param value2 any value returned when `cond` is falsy
---@return any
function M.choose(cond, value1, value2)
  if cond then
    return value1
  else
    return value2
  end
end
---@param t table list-like table
---@param temp? table reusable buffer
---@param tostr? fun(value:any,index:integer):string converter (defaults to `tostring`)
---@return table buffer filled with converted values
function M.array_tostring(t, temp, tostr)
  temp, tostr = temp or {}, tostr or tostring
  for i = 1, #t do
    temp[i] = tostr(t[i], i)
  end
  return temp
end

--- is the object of the specified type?
-- If the type is a string, then use type, otherwise compare with metatable
--- obj any An object to check
--- tp string of what type it should be
---@return boolean
--- Usage: utils.is_type("hello world", "string")   --> true
-- -- or check metatable
-- local my_mt = {}
-- local my_obj = setmetatable(my_obj, my_mt)
-- utils.is_type(my_obj, my_mt)  --> true
---@param obj any object to check
---@param tp string|table expected Lua type name or metatable
function M.is_type(obj, tp)
  if type(tp) == 'string' then
    return type(obj) == tp
  end
  local mt = getmetatable(obj)
  return tp == mt
end

--- an iterator with indices, similar to `ipairs`, but with a range.
-- This is a nil-safe index based iterator that will return `nil` when there
-- is a hole in a list. To be safe ensure that table `t.n` contains the length.
--- See utils.pack
--- See utils.unpack
--- Usage:
-- local t = utils.pack(nil, 123, nil)  -- adds an `n` field when packing
--
-- for i, v in utils.npairs(t, 2) do  -- start at index 2
--   t[i] = tostring(t[i])
-- end
--
-- -- t = { n = 3, [2] = "123", [3] = "nil" }
---@param t table
---@param i_start? integer
---@param i_end? integer
---@param step? integer
function M.npairs(t, i_start, i_end, step)
  step = step or 1
  if step == 0 then
    error('iterator step-size cannot be 0', 2)
  end
  local i = (i_start or 1) - step
  i_end = i_end or t.n or #t
  if step < 0 then
    return function()
      i = i + step
      if i < i_end then
        return nil
      end
      return i, t[i]
    end
  else
    return function()
      i = i + step
      if i > i_end then
        return nil
      end
      return i, t[i]
    end
  end
end

--- an iterator over all non-integer keys (inverse of `ipairs`).
-- It will skip any key that is an integer number, so negative indices or an
-- array with holes will not return those either (so it returns slightly less than
-- 'the inverse of `ipairs`').
--
-- This uses `pairs` under the hood, so any value that is iterable using `pairs`
-- will work with this function.
--- t table the table to iterate over
---@return key
---@return value
--- Usage:
-- local t = {
--   "hello",
--   "world",
--   hello = "hallo",
--   world = "Welt",
-- }
--
-- for k, v in utils.kpairs(t) do
--   print("German: ", v)
-- end
--
-- -- output;
-- -- German: hallo
-- -- German: Welt
---@param t any
function M.kpairs(t)
  local index
  return function()
    local value
    while true do
      index, value = next(t, index)
      if type(index) ~= 'number' or math.floor(index) ~= index then
        break
      end
    end
    return index, value
  end
end

--- Error handling
--- Error-handling

--- assert that the given argument is in fact of the correct type.
--- n any argument index
--- val any the value

--- verify any an optional verification function

--- lev any optional stack position for trace, default 2
---@return any the validated value
--- if `val` is not the correct type
--- Usage:
-- local param1 = assert_arg(1,"hello",'table')  --> error: argument 1 expected a 'table', got a 'string'
-- local param4 = assert_arg(4,'!@#$%^&*','string',path.isdir,'not a directory')
--      --> error: argument 4: '!@#$%^&*' not a directory
---@param n any
---@param val any
---@param tp any
---@param verify any
---@param msg any
---@param lev any
function M.assert_arg(n, val, tp, verify, msg, lev)
  if type(val) ~= tp then
    error(("argument %d expected a '%s', got a '%s'"):format(n, tp, type(val)), lev or 2)
  end
  if verify and not verify(val) then
    error(("argument %d: '%s' %s"):format(n, val, msg), lev or 2)
  end
  return val
end

--- creates an Enum or constants lookup table for improved error handling.
-- This helps prevent magic strings in code by throwing errors for accessing
-- non-existing values, and/or converting strings/identifiers to other values.
--
-- Calling on the object does the same, but returns a soft error; `nil + err`, if
-- the call is successful (the key exists), it will return the value.
--
-- When calling with varargs or an array the values will be equal to the keys.
-- The enum object is read-only.
--- ... table|vararg the input for the Enum. If varargs or an array then the
-- values in the Enum will be equal to the names (must be strings), if a hash-table
-- then values remain (any type), and the keys must be strings.
---@return any Enum object (read-only table/object)
--- Usage: -- Enum access at runtime
-- local obj = {}
-- obj.MOVEMENT = utils.enum("FORWARD", "REVERSE", "LEFT", "RIGHT")
--
-- if current_movement == obj.MOVEMENT.FORWARD then
--   -- do something
--
-- elseif current_movement == obj.MOVEMENT.REVERES then
--   -- throws error due to typo 'REVERES', so a silent mistake becomes a hard error
--   -- "'REVERES' is not a valid value (expected one of: 'FORWARD', 'REVERSE', 'LEFT', 'RIGHT')"
--
-- end
--- Usage: -- standardized error codes
-- local obj = {
--   ERR = utils.enum {
--     NOT_FOUND = "the item was not found",
--     OUT_OF_BOUNDS = "the index is outside the allowed range"
--   },
--
--   some_method = function(self)
--     return nil, self.ERR.OUT_OF_BOUNDS
--   end,
-- }
--
-- local result, err = obj:some_method()
-- if not result then
--   if err == obj.ERR.NOT_FOUND then
--     -- check on error code, not magic strings
--
--   else
--     -- return the error description, contained in the constant
--     return nil, "error: "..err  -- "error: the index is outside the allowed range"
--   end
-- end
--- Usage: -- validating/converting user-input
-- local color = "purple"
-- local ansi_colors = utils.enum {
--   black     = 30,
--   red       = 31,
--   green     = 32,
-- }
-- local color_code, err = ansi_colors(color) -- calling on the object, returns the value from the enum
-- if not color_code then
--   print("bad 'color', " .. err)
--   -- "bad 'color', 'purple' is not a valid value (expected one of: 'black', 'red', 'green')"
--   os.exit(1)
-- end
---@vararg any
function M.enum(...)
  local first = select(1, ...)
  local enum = {}
  local lst

  if type(first) ~= 'table' then
    -- vararg with strings
    lst = M.pack(...)
    for i, value in M.npairs(lst) do
      M.assert_arg(i, value, 'string')
      enum[value] = value
    end
  else
    -- table/array with values
    M.assert_arg(1, first, 'table')
    lst = {}
    -- first add array part
    for i, value in ipairs(first) do
      if type(value) ~= 'string' then
        error(("expected 'string' but got '%s' at index %d"):format(type(value), i), 2)
      end
      lst[i] = value
      enum[value] = value
    end
    -- add key-ed part
    for key, value in M.kpairs(first) do
      if type(key) ~= 'string' then
        error(("expected key to be 'string' but got '%s'"):format(type(key)), 2)
      end
      if enum[key] then
        error(("duplicate entry in array and hash part: '%s'"):format(key), 2)
      end
      enum[key] = value
      lst[#lst + 1] = key
    end
  end

  if not lst[1] then
    error('expected at least 1 entry', 2)
  end

  local valid = "(expected one of: '" .. table.concat(lst, "', '") .. "')"
  setmetatable(enum, {
    __index = function(self, key)
      error(("'%s' is not a valid value %s"):format(tostring(key), valid), 2)
    end,
    __newindex = function(self, key, value)
      error('the Enum object is read-only', 2)
    end,
    __call = function(self, key)
      if type(key) == 'string' then
        local v = rawget(self, key)
        if v ~= nil then
          return v
        end
      end
      return nil, ("'%s' is not a valid value %s"):format(tostring(key), valid)
    end,
  })

  return enum
end

--- process a function argument.
-- This is used throughout Penlight and defines what is meant by a function:
-- Something that is callable, or an operator string as defined by <code>pl.operator</code>,
-- such as '>' or '#'. If a function factory has been registered for the type, it will
-- be called to get the function.
---@param idx any
---@param f any
---@param msg any
function M.function_arg(idx, f, msg)
  M.assert_arg(1, idx, 'number')
  local tp = type(f)
  if tp == 'function' then
    return f
  end -- no worries!
  -- ok, a string can correspond to an operator (like '==')
  if tp == 'string' then
    if not operators then
      operators = require('pl.operator').optable
    end
    local fn = operators[f]
    if fn then
      return fn
    end
    local fn, err = M.string_lambda(f)
    if not fn then
      error(err .. ': ' .. f)
    end
    return fn
  elseif tp == 'table' or tp == 'userdata' then
    local mt = getmetatable(f)
    if not mt then
      error('not a callable object', 2)
    end
    local ff = _function_factories[mt]
    if not ff then
      if not mt.__call then
        error('not a callable object', 2)
      end
      return f
    else
      return ff(f) -- we have a function factory for this type!
    end
  end
  if not msg then
    msg = ' must be callable'
  end
  if idx > 0 then
    error('argument ' .. idx .. ': ' .. msg, 2)
  else
    error(msg, 2)
  end
end

--- assert the common case that the argument is a string.
--- n any argument index
--- val any a value that must be a string
---@return any the validated value
--- val must be a string
--- Usage:
-- local val = 42
-- local param2 = utils.assert_string(2, val) --> error: argument 2 expected a 'string', got a 'number'
---@param n any
---@param val any
function M.assert_string(n, val)
  return M.assert_arg(n, val, 'string', nil, nil, 3)
end

--- control the error strategy used by Penlight.
-- This is a global setting that controls how `utils.raise` behaves:
--
-- - 'default': return `nil + error` (this is the default)
-- - 'error': throw a Lua error
-- - 'quit': exit the program
--
---@param mode any
function M.on_error(mode)
  mode = tostring(mode)
  if ({ ['default'] = 1, ['quit'] = 2, ['error'] = 3 })[mode] then
    err_mode = mode
  else
    -- fail loudly
    local err = "Bad argument expected string; 'default', 'quit', or 'error'. Got '"
      .. tostring(mode)
      .. "'"
    if err_mode == 'default' then
      error(err, 2) -- even in 'default' mode fail loud in this case
    end
    raise(err)
  end
end

--- used by Penlight functions to return errors. Its global behaviour is controlled
-- by `utils.on_error`.
-- To use this function you MUST use it in conjunction with `return`, since it might
-- return `nil + error`.
--- err any the error string.
--- See utils.on_error
--- Usage:
-- if some_condition then
--   return utils.raise("some condition was not met")  -- MUST use 'return'!
-- end
---@param err any
function M.raise(err)
  if err_mode == 'default' then
    return nil, err
  elseif err_mode == 'quit' then
    return M.quit(err)
  end
  error(err, 2)
end
raise = M.raise
---@param filename any
---@param is_bin any
function M.readfile(filename, is_bin)
  local mode = is_bin and 'b' or ''
  M.assert_string(1, filename)
  local f, open_err = io.open(filename, 'r' .. mode)
  if not f then
    return raise(open_err)
  end
  local res, read_err = f:read('*a')
  f:close()
  if not res then
    -- Errors in io.open have "filename: " prefix,
    -- error in file:read don't, add it.
    return raise(filename .. ': ' .. read_err)
  end
  return res
end
---@param filename any
---@param str any
---@param is_bin any
function M.writefile(filename, str, is_bin)
  local mode = is_bin and 'b' or ''
  M.assert_string(1, filename)
  M.assert_string(2, str)
  local f, err = io.open(filename, 'w' .. mode)
  if not f then
    return raise(err)
  end
  local ok, write_err = f:write(str)
  f:close()
  if not ok then
    -- Errors in io.open have "filename: " prefix,
    -- error in file:write don't, add it.
    return raise(filename .. ': ' .. write_err)
  end
  return true
end
---@param filename any
function M.readlines(filename)
  M.assert_string(1, filename)
  local f, err = io.open(filename, 'r')
  if not f then
    return raise(err)
  end
  local res = {}
  for line in f:lines() do
    table.insert(res, line)
  end
  f:close()
  return res
end

--- OS functions
--- OS-functions

--- execute a shell command and return the output.
-- This function redirects the output to tempfiles and returns the content of those files.
---@param cmd any
---@param bin any
function M.executeex(cmd, bin)
  local outfile = os.tmpname()
  local errfile = os.tmpname()

  if is_windows and not outfile:find(':') then
    outfile = os.getenv('TEMP') .. outfile
    errfile = os.getenv('TEMP') .. errfile
  end
  cmd = cmd .. ' > ' .. M.quote_arg(outfile) .. ' 2> ' .. M.quote_arg(errfile)

  local success, retcode = M.execute(cmd)
  local outcontent = M.readfile(outfile, bin)
  local errcontent = M.readfile(errfile, bin)
  os.remove(outfile)
  os.remove(errfile)
  return success, retcode, (outcontent or ''), (errcontent or '')
end

--- Quote and escape an argument of a command.
-- Quotes a single (or list of) argument(s) of a command to be passed
-- to `os.execute`, `pl.utils.execute` or `pl.utils.executeex`.
--- argument any (string or table/list) the argument to quote. If a list then
-- all arguments in the list will be returned as a single string quoted.
---@return any quoted and escaped argument.
--- Usage:
-- local options = utils.quote_arg {
--     "-lluacov",
--     "-e",
--     "utils = print(require('pl.utils')._VERSION",
-- }
-- -- returns: -lluacov -e 'utils = print(require('\''pl.utils'\'')._VERSION'
---@param argument any
function M.quote_arg(argument)
  if type(argument) == 'table' then
    -- encode an entire table
    local r = {}
    for i, arg in ipairs(argument) do
      r[i] = M.quote_arg(arg)
    end

    return table.concat(r, ' ')
  end
  -- only a single argument
  if is_windows then
    if argument == '' or argument:find('[ \f\t\v]') then
      -- Need to quote the argument.
      -- Quotes need to be escaped with backslashes;
      -- additionally, backslashes before a quote, escaped or not,
      -- need to be doubled.
      -- See documentation for CommandLineToArgvW Windows function.
      argument = '"' .. argument:gsub([[(\*)"]], [[%1%1\"]]):gsub([[\+$]], '%0%0') .. '"'
    end

    -- os.execute() uses system() C function, which on Windows passes command
    -- to cmd.exe. Escape its special characters.
    return (argument:gsub('["^<>!|&%%]', '^%0'))
  else
    if argument == '' or argument:find('[^a-zA-Z0-9_@%+=:,./-]') then
      -- To quote arguments on posix-like systems use single quotes.
      -- To represent an embedded single quote close quoted string ('),
      -- add escaped quote (\'), open quoted string again (').
      argument = "'" .. argument:gsub("'", [['\'']]) .. "'"
    end

    return argument
  end
end

--- error out of this program gracefully.
--- code any|nil The exit code, defaults to -`1` if omitted

--- ... any extra arguments for message's format'
--- See utils.fprintf
--- Usage: utils.quit(-1, "Error '%s' happened", "42")
-- -- is equivalent to
-- utils.quit("Error '%s' happened", "42")  --> Error '42' happened
---@param code any
---@param msg any
---@vararg any
function M.quit(code, msg, ...)
  if type(code) == 'string' then
    M.fprintf(io.stderr, code, msg, ...)
    io.stderr:write('\n')
    code = -1 -- TODO: this is odd, see the test. Which returns 255 as exit code
  elseif msg then
    M.fprintf(io.stderr, msg, ...)
    io.stderr:write('\n')
  end
  os.exit(code, true)
end
---@param s any
function M.escape(s)
  M.assert_string(1, s)
  return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]', '%%%1'))
end
---@param s any
---@param re any
---@param plain any
---@param n any
function M.split(s, re, plain, n)
  M.assert_string(1, s)
  local i1, ls = 1, {}
  if not re then
    re = '%s+'
  end
  if re == '' then
    return { s }
  end
  while true do
    local i2, i3 = s:find(re, i1, plain)
    if not i2 then
      local last = s:sub(i1)
      if last ~= '' then
        table.insert(ls, last)
      end
      if #ls == 1 and ls[1] == '' then
        return {}
      else
        return ls
      end
    end
    table.insert(ls, s:sub(i1, i2 - 1))
    if n and #ls == n then
      ls[#ls] = s:sub(i1)
      return ls
    end
    i1 = i3 + 1
  end
end

--- split a string into a number of return values.
-- Identical to `split` but returns multiple sub-strings instead of
-- a single list of sub-strings.
--- s any the string
--- re any A Lua string pattern; defaults to '%s+'
--- plain any don't use Lua patterns
--- n any optional maximum number of splits
---@return any n values
--- Usage: first,next = splitv('user=jane=doe','=', false, 2)
-- assert(first == "user")
-- assert(next == "jane=doe")
---@param s any
---@param re any
---@param plain any
---@param n any
function M.splitv(s, re, plain, n)
  return unpack(M.split(s, re, plain, n))
end

--- Functional
--- functional

--- 'memoize' a function (cache returned value for next call).
-- This is useful if you have a function which is relatively expensive,
-- but you don't know in advance what values will be required, so
-- building a table upfront is wasteful/impossible.
---@param func any
function M.memoize(func)
  local cache = {}
  return function(k)
    local res = cache[k]
    if res == nil then
      res = func(k)
      cache[k] = res
    end
    return res
  end
end

--- associate a function factory with a type.
-- A function factory takes an object of the given type and
-- returns a function for evaluating it
---@param mt any
---@param fun any
function M.add_function_factory(mt, fun)
  _function_factories[mt] = fun
end
---@param f any
local function _string_lambda(f)
  if f:find('^|') or f:find('_') then
    local args, body = f:match('|([^|]*)|(.+)')
    if f:find('_') then
      args = '_'
      body = f
    else
      if not args then
        return raise('bad string lambda')
      end
    end
    local fstr = 'return function(' .. args .. ') return ' .. body .. ' end'
    local fn, err = M.load(fstr)
    if not fn then
      return raise(err)
    end
    fn = fn()
    return fn
  else
    return raise('not a string lambda')
  end
end

--- an anonymous function as a string. This string is either of the form
-- '|args| expression' or is a function of one argument, '_'
--- lf fun as a string
--- utils.string_lambda fun
--- Usage:
-- string_lambda '|x|x+1' (2) == 3
-- string_lambda '_+1' (2) == 3
M.string_lambda = M.memoize(_string_lambda)

--- bind the first argument of the function to a value.
--- fn any a function of at least two values (may be an operator string)

--- same as @{function_arg}
--- See func.bind1
--- Usage: local function f(msg, name)
--   print(msg .. " " .. name)
-- end
--
-- local hello = utils.bind1(f, "Hello")
--
-- print(hello("world"))     --> "Hello world"
-- print(hello("sunshine"))  --> "Hello sunshine"
---@param fn any
---@param p any
---@return any a function such that f(x) is fn(p,x)
function M.bind1(fn, p)
  fn = M.function_arg(1, fn)
  return function(...)
    return fn(p, ...)
  end
end

--- bind the second argument of the function to a value.
--- fn any a function of at least two values (may be an operator string)

---@return any a function such that f(x) is fn(x,p)
--- same as @{function_arg}
--- Usage: local function f(a, b, c)
--   print(a .. " " .. b .. " " .. c)
-- end
--
-- local hello = utils.bind1(f, "world")
--
-- print(hello("Hello", "!"))  --> "Hello world !"
-- print(hello("Bye", "?"))    --> "Bye world ?"
---@param fn any
---@param p any
function M.bind2(fn, p)
  fn = M.function_arg(1, fn)
  return function(x, ...)
    return fn(x, p, ...)
  end
end

--- Deprecation
--- deprecation

do
  -- the default implementation
  local deprecation_func = function(msg, trace)
    if trace then
      warn(msg, '\n', trace) -- luacheck: ignore
    else
      warn(msg) -- luacheck: ignore
    end
  end

  --- Sets a deprecation warning function.
  -- An application can override this function to support proper output of
  -- deprecation warnings. The warnings can be generated from libraries or
  -- functions by calling `utils.raise_deprecation`. The default function
  -- will write to the 'warn' system (introduced in Lua 5.4, or the compatibility
  -- function from the `compat` module for earlier versions).
  --
  -- Note: only applications should set/change this function, libraries should not.
  --- func any a callback with signature: `function(msg, trace)` both arguments are strings, the latter being optional.
  --- See utils.raise_deprecation
  --- Usage:
  -- -- write to the Nginx logs with OpenResty
  -- utils.set_deprecation_func(function(msg, trace)
  --   ngx.log(ngx.WARN, msg, (trace and (" " .. trace) or nil))
  -- end)
  --
  -- -- disable deprecation warnings
  -- utils.set_deprecation_func()
  ---@param func any
  function M.set_deprecation_func(func)
    if func == nil then
      deprecation_func = function() end
    else
      M.assert_arg(1, func, 'function')
      deprecation_func = func
    end
  end

  --- raises a deprecation warning.
  -- For options see the usage example below.
  --
  -- Note: the `opts.deprecated_after` field is the last version in which
  -- a feature or option was NOT YET deprecated! Because when writing the code it
  -- is quite often not known in what version the code will land. But the last
  -- released version is usually known.
  --- opts any options table
  --- See utils.set_deprecation_func
  --- Usage:
  -- warn("@on")   -- enable Lua warnings, they are usually off by default
  --
  -- function stringx.islower(str)
  --   raise_deprecation {
  --     source = "Penlight " .. utils._VERSION,                   -- optional
  --     message = "function 'islower' was renamed to 'is_lower'", -- required
  --     version_removed = "2.0.0",                                -- optional
  --     deprecated_after = "1.2.3",                               -- optional
  --     no_trace = true,                                          -- optional
  --   }
  --   return stringx.is_lower(str)
  -- end
  -- -- output: "[Penlight 1.9.2] function 'islower' was renamed to 'is_lower' (deprecated after 1.2.3, scheduled for removal in 2.0.0)"
  ---@param opts any
  function M.raise_deprecation(opts)
    M.assert_arg(1, opts, 'table')
    if type(opts.message) ~= 'string' then
      error("field 'message' of the options table must be a string", 2)
    end
    local trace
    if not opts.no_trace then
      trace = debug.traceback('', 2):match('[\n%s]*(.-)$')
    end
    local msg
    if opts.deprecated_after and opts.version_removed then
      msg = (' (deprecated after %s, scheduled for removal in %s)'):format(
        tostring(opts.deprecated_after),
        tostring(opts.version_removed)
      )
    elseif opts.deprecated_after then
      msg = (' (deprecated after %s)'):format(tostring(opts.deprecated_after))
    elseif opts.version_removed then
      msg = (' (scheduled for removal in %s)'):format(tostring(opts.version_removed))
    else
      msg = ''
    end

    msg = opts.message .. msg

    if opts.source then
      msg = '[' .. opts.source .. '] ' .. msg
    else
      if msg:sub(1, 1) == '@' then
        -- in Lua 5.4 "@" prefixed messages are control messages to the warn system
        error("message cannot start with '@'", 2)
      end
    end

    deprecation_func(msg, trace)
  end
end

return M
