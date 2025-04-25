--- Generally useful routines.
-- See  @{01-introduction.md.Generally_useful_functions|the Guide}.
--
-- Dependencies: `pl.compat`, all exported fields and functions from
-- `pl.compat` are also available in this module.
--
-- @module pl.utils
local compat = require('pl.compat')

local is_windows = compat.is_windows

local M = { _VERSION = '1.14.0' }
for k, v in pairs(compat) do
  M[k] = v
end

--- Some standard patterns
-- @table patterns
M.patterns = {
  FLOAT = '[%+%-%d]%d*%.?%d*[eE]?[%+%-]?%d*', -- floating point number
  INTEGER = '[+%-%d]%d*', -- integer number
  IDEN = '[%a_][%w_]*', -- identifier
  FILE = '[%a%.\\][:%][%w%._%-\\]*', -- file
}

--- Standard meta-tables as used by other Penlight modules
-- @table stdmt
-- @field List the List metatable
-- @field Map the Map metatable
-- @field Set the Set metatable
-- @field MultiMap the MultiMap metatable
M.stdmt = {
  List = { _name = 'List' },
  Map = { _name = 'Map' },
  Set = { _name = 'Set' },
  MultiMap = { _name = 'MultiMap' },
}

--- pack an argument list into a table.
-- @param ... any arguments
-- @return a table with field `n` set to the length
-- @function utils.pack
-- @see compat.pack
-- @see utils.unpack
M.pack = table.pack -- added here to be symmetrical with unpack

--- unpack a table and return its contents.
--
-- NOTE: this implementation differs from the Lua implementation in the way
-- that this one DOES honor the `n` field in the table `t`, such that it is 'nil-safe'.
-- @param t table to unpack
-- @param[opt] i index from which to start unpacking, defaults to 1
-- @param[opt] j index of the last element to unpack, defaults to `t.n` or else `#t`
-- @return multiple return values from the table
-- @function utils.unpack
-- @see compat.unpack
-- @see utils.pack
-- @usage
-- local t = table.pack(nil, nil, nil, 4)
-- local a, b, c, d = table.unpack(t)   -- this `unpack` is NOT nil-safe, so d == nil
--
-- local a, b, c, d = utils.unpack(t)   -- this is nil-safe, so d == 4
function M.unpack(t, i, j)
  return table.unpack(t, i or 1, j or t.n or #t)
end

--- print an arbitrary number of arguments using a format.
-- Output will be sent to `stdout`.
-- @param fmt The format (see `string.format`)
-- @param ... Extra arguments for format
function M.printf(fmt, ...)
  M.fprintf(io.stdout, fmt, ...)
end

--- write an arbitrary number of arguments to a file using a format.
-- @param f File handle to write to.
-- @param fmt The format (see `string.format`).
-- @param ... Extra arguments for format
function M.fprintf(f, fmt, ...)
  f:write(fmt:format(...))
end

--- an iterator over all non-integer keys (inverse of `ipairs`).
-- It will skip any key that is an integer number, so negative indices or an
-- array with holes will not return those either (so it returns slightly less than
-- 'the inverse of `ipairs`').
--
-- This uses `pairs` under the hood, so any value that is iterable using `pairs`
-- will work with this function.
-- @tparam table t the table to iterate over
-- @treturn key
-- @treturn value
-- @usage
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
-- @section Error-handling

--- assert that the given argument is in fact of the correct type.
-- @param n argument index
-- @param val the value
-- @param tp the type
-- @param verify an optional verification function
-- @param msg an optional custom message
-- @param lev optional stack position for trace, default 2
-- @return the validated value
-- @raise if `val` is not the correct type
-- @usage
-- local param1 = assert_arg(1,"hello",'table')  --> error: argument 1 expected a 'table', got a 'string'
-- local param4 = assert_arg(4,'!@#$%^&*','string',path.isdir,'not a directory')
--      --> error: argument 4: '!@#$%^&*' not a directory
function M.assert_arg(n, val, tp, verify, msg, lev)
  if type(val) ~= tp then
    error(("argument %d expected a '%s', got a '%s'"):format(n, tp, type(val)), lev or 2)
  end
  if verify and not verify(val) then
    error(("argument %d: '%s' %s"):format(n, val, msg), lev or 2)
  end
  return val
end

--- assert the common case that the argument is a string.
-- @param n argument index
-- @param val a value that must be a string
-- @return the validated value
-- @raise val must be a string
-- @usage
-- local val = 42
-- local param2 = utils.assert_string(2, val) --> error: argument 2 expected a 'string', got a 'number'
function M.assert_string(n, val)
  return M.assert_arg(n, val, 'string', nil, nil, 3)
end

--- used by Penlight functions to return errors. Its global behaviour is controlled
-- by `utils.on_error`.
-- To use this function you MUST use it in conjunction with `return`, since it might
-- return `nil + error`.
-- @param err the error string.
-- @see utils.on_error
-- @usage
-- if some_condition then
--   return utils.raise("some condition was not met")  -- MUST use 'return'!
-- end
function M.raise(err)
  return nil, err
end

--- File handling
-- @section files

--- return the contents of a file as a string
-- @param filename The file path
-- @param is_bin open in binary mode
-- @return file contents
function M.readfile(filename, is_bin)
  local mode = is_bin and 'b' or ''
  local f = assert(io.open(filename, 'r' .. mode))
  local res = assert(f:read('*a'))
  f:close()
  return res
end

--- write a string to a file
-- @param filename The file path
-- @param str The string
-- @param is_bin open in binary mode
-- @return true or nil
-- @return error message
-- @raise error if filename or str aren't strings
function M.writefile(filename, str, is_bin)
  local mode = is_bin and 'b' or ''
  local f = assert(io.open(filename, 'w' .. mode))
  assert(f:write(str))
  f:close()
end

--- Quote and escape an argument of a command.
-- Quotes a single (or list of) argument(s) of a command to be passed
-- to `os.execute`, `pl.utils.execute` or `pl.utils.executeex`.
-- @param argument (string or table/list) the argument to quote. If a list then
-- all arguments in the list will be returned as a single string quoted.
-- @return quoted and escaped argument.
-- @usage
-- local options = utils.quote_arg {
--     "-lluacov",
--     "-e",
--     "utils = print(require('pl.utils')._VERSION",
-- }
-- -- returns: -lluacov -e 'utils = print(require('\''pl.utils'\'')._VERSION'
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
-- @param[opt] code The exit code, defaults to -`1` if omitted
-- @param msg The exit message will be sent to `stderr` (will be formatted with the extra parameters)
-- @param ... extra arguments for message's format'
-- @see utils.fprintf
-- @usage utils.quit(-1, "Error '%s' happened", "42")
-- -- is equivalent to
-- utils.quit("Error '%s' happened", "42")  --> Error '42' happened
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

--- String functions
-- @section string-functions

--- escape any Lua 'magic' characters in a string
-- @param s The input string
function M.escape(s)
  M.assert_string(1, s)
  return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]', '%%%1'))
end

--- split a string into a list of strings separated by a delimiter.
-- @param s The input string
-- @param re optional A Lua string pattern; defaults to '%s+'
-- @param plain optional If truthy don't use Lua patterns
-- @param n optional maximum number of elements (if there are more, the last will remain un-split)
-- @return a list-like table
-- @raise error if s is not a string
-- @see splitv
function M.split(s, re, plain, n)
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

return M
