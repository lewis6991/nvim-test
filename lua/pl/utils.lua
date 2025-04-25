local M = { _VERSION = '1.14.0' }

--- pack an argument list into a table.
-- @param ... any arguments
-- @return a table with field `n` set to the length
-- @function utils.pack
-- @see compat.pack
-- @see utils.unpack
function M.pack(...)
  return { n = select('#', ...), ... }
end

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
  return unpack(t, i or 1, j or t.n or #t)
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
  return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]', '%%%1'))
end

return M
