local uv = vim.uv

local M = {}

--- @generic T
--- @param t T
--- @return T
function M.tbl_copy(t)
  --- @cast t table<any,any>
  local res = {} --- @type table<any,any>
  for k, v in pairs(t) do
    res[k] = v
  end
  return res
end

--- @return integer
function M.urandom()
  local s = assert(vim.uv.random(4))
  local bytes = { s:byte(1, 4) }
  local value = 0
  for _, v in ipairs(bytes) do
    value = value * 256 + v
  end
  return value
end

--- @param path string
--- @return string
local function attrib(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type or ''
end

--- @param path string
---@return boolean? success
---@return string? err
---@return string? err_name
function M.mkdir(path)
  return uv.fs_mkdir(path, tonumber('755', 8))
end

--- @param path string
--- @return boolean
function M.isdir(path)
  return attrib(path) == 'directory'
end

--- @param path string
--- @return boolean
function M.isfile(path)
  return attrib(path) == 'file'
end

--- @param path string
--- @return boolean
function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

--- The directory separator character for the current platform.
local dir_sep = package.config:sub(1, 1)

M.is_windows = dir_sep == '\\'

return M
