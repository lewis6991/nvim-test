---------------------------------------------------
-- Utility helpers for LuaCov.
-- @class module
-- @name luacov.util

local uv = assert(vim and vim.uv, 'nvim-test requires vim.uv')

local READ_MODE = 'r'
local DEFAULT_PERMS = 420 -- 0644

---@class luacov.util
local util = {}

---@param str string
---@param prefix string
---@return string
function util.unprefix(str, prefix)
  if str:sub(1, #prefix) == prefix then
    return str:sub(#prefix + 1)
  else
    return str
  end
end

-- Returns contents of a file or nil + error message.
---@param name string
---@return string?, string?
local function read_file(name)
  local fd, open_err = uv.fs_open(name, READ_MODE, DEFAULT_PERMS)

  if not fd then
    return nil, util.unprefix(tostring(open_err), name .. ': ')
  end

  local stat, stat_err = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil, tostring(stat_err)
  end

  local contents, read_err = uv.fs_read(fd, stat.size or 0, 0)
  uv.fs_close(fd)

  if contents then
    return contents
  else
    return nil, tostring(read_err)
  end
end

--- Loads a string.
---@param str string
---@param[opt] env table
---@param[opt] chunkname string
---@return function?, string?
function util.load_string(str, env, chunkname)
  if _VERSION:find('5%.1') then
    local func, err = loadstring(str, chunkname) -- luacheck: compat

    if not func then
      return nil, err
    end

    if env then
      setfenv(func, env) -- luacheck: compat
    end

    return func
  else
    return load(str, chunkname, 'bt', env or _ENV) -- luacheck: compat
  end
end

--- Load a config file.
-- Reads, loads and runs a Lua file in an environment.
---@param name string file name.
---@param env table environment table.
---@return true|string|nil, string?, string?
function util.load_config(name, env)
  local src, read_err = read_file(name)

  if not src then
    return nil, 'read', read_err
  end

  local func, load_err = util.load_string(src, env, '@config')

  if not func then
    return nil, 'load', 'line ' .. util.unprefix(load_err, 'config:')
  end

  local ok, ret = pcall(func)

  if not ok then
    return nil, 'run', 'line ' .. util.unprefix(ret, 'config:')
  end

  return true, ret
end

--- Checks if a file exists.
---@param name string file name.
---@return boolean
function util.file_exists(name)
  return uv.fs_stat(name) ~= nil
end

return util
