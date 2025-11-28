--- Path manipulation and file queries.
---
--- This is modelled after Python's os.path library (10.1); see @{04-paths.md|the Guide}.
---
--- NOTE: the functions assume the paths being dealt with to originate
--- from the OS the application is running on. Windows drive letters are not
--- to be used when running on a Unix system for example. The one exception
--- is Windows paths to allow both forward and backward slashes (since Lua
--- also accepts those)
---
--- Dependencies: `pl.utils`, `vim.uv`

local utils = require('pl.utils')
local assert_string = utils.assert_string

---@class pl.path.Attributes
---@field dev? integer
---@field ino? integer
---@field mode? string
---@field nlink? integer
---@field uid? integer
---@field gid? integer
---@field rdev? integer
---@field size? integer
---@field blocks? integer
---@field blksize? integer
---@field flags? integer
---@field gen? integer
---@field access? number
---@field modification? number
---@field change? number
---@field permissions? string
---@field birthtime? number

---@alias pl.path.AttributeKey
---|'dev'
---|'ino'
---|'mode'
---|'nlink'
---|'uid'
---|'gid'
---|'rdev'
---|'size'
---|'blocks'
---|'blksize'
---|'flags'
---|'gen'
---|'access'
---|'modification'
---|'change'
---|'permissions'
---|'birthtime'

---@alias pl.path.AttributeParam pl.path.AttributeKey|pl.path.Attributes

---@alias pl.path.DirIterator fun():string?

local uv = vim.uv

local DEFAULT_DIR_MODE = 511 -- 0777
---@param err any
local function parse_uv_error(err)
  if type(err) ~= 'string' then
    return tostring(err), nil
  end
  local code = err:match('^([%u%d_]+)')
  return err, code
end
---@param ts any
local function timespec_seconds(ts)
  local sec = ts.sec or 0
  local nsec = ts.nsec or 0
  return sec + nsec / 1e9
end
---@param attr any
---@param stat any
---@param err any
---@param code any
local function fs_attributes(attr, stat, err, code)
  if not stat then
    return nil, err, code
  end
  if type(attr) == 'string' then
    if not stat[attr] then
      return nil, ("invalid attribute '%s'"):format(attr)
    end
    return stat[attr]
  end
  return stat
end
---@param path any
local function dir_iter(path)
  local handle, err, code = uv.fs_scandir(path)
  if not handle then
    return nil, err, code
  end
  local dot_state = 0
  local function iter()
    if dot_state == 0 then
      dot_state = 1
      return '.'
    elseif dot_state == 1 then
      dot_state = 2
      return '..'
    end
    local name = uv.fs_scandir_next(handle)
    return name
  end
  return iter, handle
end
---@param path any
local function chdir(path)
  local ok, err = pcall(uv.chdir, path)
  if not ok then
    return nil, parse_uv_error(err)
  end
  return true
end

---@class pl.path
local M = {}
---@param name any
---@param param any
---@param err any
---@param code any
local function err_func(name, param, err, code)
  local ret = ('%s failed'):format(tostring(name))
  if param ~= nil then
    ret = ret .. (" for '%s'"):format(tostring(param))
  end
  ret = ret .. (': %s'):format(tostring(err))
  if code ~= nil then
    ret = ret .. (' (code %s)'):format(tostring(code))
  end
  return ret
end

--- Lua iterator over the entries of a given directory.
-- Backed by `vim.uv.fs_scandir`.
---@param dir fun
---@param d string
---@return any pl.path.DirIterator?
---@return any userdata|string?
---@return any string?
M.dir = function(d)
  assert_string(1, d)
  local iter, handle, code = dir_iter(d)
  if not iter then
    return iter, err_func('dir', d, handle, code), code
  end
  return iter, handle
end

--- Creates a directory.
-- Backed by `vim.uv.fs_mkdir`.
---@param d any
function M.mkdir(d)
  assert_string(1, d)
  local ok, err, code = uv.fs_mkdir(d, DEFAULT_DIR_MODE)
  if not ok then
    return ok, err_func('mkdir', d, err, code), code
  end
  return ok, err, code
end

--- Gets attributes.
-- Backed by `vim.uv.fs_stat`.
---@param d any
---@param r any
function M.attrib(d, r)
  assert_string(1, d)
  return fs_attributes(r, uv.fs_stat(d))
end
function M.currentdir()
  return (assert(uv.cwd()))
end

--- Gets symlink attributes.
-- Backed by `vim.uv.fs_lstat`.
---@param link_attrib fun
---@param d string
---@param r? any pl.path.AttributeParam
---@return any pl.path.Attributes|number|string?
---@return any string?
---@return any string?
M.link_attrib = function(d, r)
  assert_string(1, d)
  local ok, err, code = fs_attributes(r, uv.fs_lstat(d))
  if ok == nil and err ~= nil then
    return ok, err_func('link_attrib', d, err, code), code
  end
  return ok, err, code
end

--- Changes the working directory.
-- On Windows, if a drive is specified, it also changes the current drive. If
-- only specifying the drive, it will only switch drive, but not modify the path.
-- Backed by `vim.uv.chdir`.
---@param d any
function M.chdir(d)
  assert_string(1, d)
  local ok, err, code = chdir(d)
  if not ok then
    return ok, err_func('chdir', d, err, code), code
  end
  return ok, err, code
end
---@param path any
function M.isdir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'directory' or false
end
---@param path any
function M.isfile(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'file' or false
end

-- is this a symbolic link?
---@param path any
function M.islink(path)
  local stat = uv.fs_lstat(path)
  return stat and stat.type == 'link' or false
end
---@param P any
function M.exists(P)
  return uv.fs_stat(P) and P or nil
end
---@param path any
function M.getatime(path)
  local stat = uv.fs_stat(path)
  return stat and timespec_seconds(stat.atime) or nil
end
---@param path any
function M.getmtime(path)
  local stat = uv.fs_stat(path)
  return stat and timespec_seconds(stat.mtime) or nil
end
---@param path any
function M.getctime(path)
  local stat = uv.fs_stat(path)
  return stat and timespec_seconds(stat.ctime) or nil
end
---@param s any
---@param i any
local function at(s, i)
  return s:sub(i, i)
end

M.is_windows = utils.is_windows

local sep, other_sep, seps
-- constant sep is the directory separator for this platform.
-- constant dirsep is the separator in the PATH environment variable
if M.is_windows then
  M.sep = '\\'
  other_sep = '/'
  M.dirsep = ';'
  seps = { ['/'] = true, ['\\'] = true }
else
  M.sep = '/'
  M.dirsep = ':'
  seps = { ['/'] = true }
end
sep = M.sep

--- given a path, return the directory part and a file part.
-- if there's no directory part, the first value will be empty
-- @usage
-- local dir, file = path.splitpath("some/dir/myfile.txt")
-- assert(dir == "some/dir")
-- assert(file == "myfile.txt")
--
-- local dir, file = path.splitpath("some/dir/")
-- assert(dir == "some/dir")
-- assert(file == "")
--
-- local dir, file = path.splitpath("some_dir")
-- assert(dir == "")
-- assert(file == "some_dir")
---@param P any
function M.splitpath(P)
  assert_string(1, P)
  local i = #P
  local ch = at(P, i)
  while i > 0 and ch ~= sep and ch ~= other_sep do
    i = i - 1
    ch = at(P, i)
  end
  if i == 0 then
    return '', P
  end
  return P:sub(1, i - 1), P:sub(i + 1)
end
---@param P any
---@param pwd any
function M.abspath(P, pwd)
  assert_string(1, P)
  if pwd then
    assert_string(2, pwd)
  end
  local use_pwd = pwd ~= nil
  if not use_pwd and not M.currentdir() then
    return P
  end
  P = P:gsub('[\\/]$', '')
  pwd = pwd or M.currentdir()
  if not M.isabs(P) then
    P = M.join(pwd, P)
  elseif M.is_windows and not use_pwd and at(P, 2) ~= ':' and at(P, 2) ~= '\\' then
    P = pwd:sub(1, 2) .. P -- attach current drive to path like '\\fred.txt'
  end
  return M.normpath(P)
end
---@param path any
function M.splitext(path)
  assert_string(1, path)
  local i = #path
  local ch = at(path, i)
  while i > 0 and ch ~= '.' do
    if seps[ch] then
      return path, ''
    end
    i = i - 1
    ch = at(path, i)
  end
  if i == 0 then
    return path, ''
  else
    return path:sub(1, i - 1), path:sub(i)
  end
end
---@param P any
function M.dirname(P)
  assert_string(1, P)
  return (M.splitpath(P))
end
---@param P any
function M.basename(P)
  assert_string(1, P)
  local _, p2 = M.splitpath(P)
  return p2
end
---@param P any
function M.extension(P)
  assert_string(1, P)
  local _, p2 = M.splitext(P)
  return p2
end
---@param P any
function M.isabs(P)
  assert_string(1, P)
  if M.is_windows and at(P, 2) == ':' then
    return seps[at(P, 3)] ~= nil
  end
  return seps[at(P, 1)] ~= nil
end
---@param p1 any
---@param p2 any
---@vararg any
function M.join(p1, p2, ...)
  assert_string(1, p1)
  assert_string(2, p2)
  if select('#', ...) > 0 then
    local p = M.join(p1, p2)
    local args = { ... }
    for i = 1, #args do
      assert_string(i, args[i])
      p = M.join(p, args[i])
    end
    return p
  end
  if M.isabs(p2) then
    return p2
  end
  local endc = at(p1, #p1)
  if endc ~= M.sep and endc ~= other_sep and endc ~= '' then
    p1 = p1 .. M.sep
  end
  return p1 .. p2
end

--- normalize the case of a pathname. On Unix, this returns the path unchanged,
--- for Windows it converts;
---
--- * the path to lowercase
--- * forward slashes to backward slashes
--- Usage: path.normcase("/Some/Path/File.txt")
-- -- Windows: "\some\path\file.txt"
-- -- Others : "/Some/Path/File.txt"
---@param P any
function M.normcase(P)
  assert_string(1, P)
  if M.is_windows then
    return P:gsub('/', '\\'):lower()
  else
    return P
  end
end

--- normalize a path name.
-- `A//B`, `A/./B`, and `A/foo/../B` all become `A/B`.
--
-- An empty path results in '.'.
---@param P any
function M.normpath(P)
  assert_string(1, P)
  -- Split path into anchor and relative path.
  local anchor = ''
  if M.is_windows then
    if P:match('^\\\\') then -- UNC
      anchor = '\\\\'
      P = P:sub(3)
    elseif seps[at(P, 1)] then
      anchor = '\\'
      P = P:sub(2)
    elseif at(P, 2) == ':' then
      anchor = P:sub(1, 2)
      P = P:sub(3)
      if seps[at(P, 1)] then
        anchor = anchor .. '\\'
        P = P:sub(2)
      end
    end
    P = P:gsub('/', '\\')
  else
    -- According to POSIX, in path start '//' and '/' are distinct,
    -- but '///+' is equivalent to '/'.
    if P:match('^//') and at(P, 3) ~= '/' then
      anchor = '//'
      P = P:sub(3)
    elseif at(P, 1) == '/' then
      anchor = '/'
      P = P:match('^/*(.*)$')
    end
  end
  local parts = {}
  for part in P:gmatch('[^' .. sep .. ']+') do
    if part == '..' then
      if #parts ~= 0 and parts[#parts] ~= '..' then
        table.remove(parts)
      else
        table.insert(parts, part)
      end
    elseif part ~= '.' then
      table.insert(parts, part)
    end
  end
  P = anchor .. table.concat(parts, sep)
  if P == '' then
    P = '.'
  end
  return P
end
---@param path any
---@param start any
function M.relpath(path, start)
  assert_string(1, path)
  if start then
    assert_string(2, start)
  end
  local split, min = utils.split, math.min
  path = M.abspath(path, start)
  start = start or M.currentdir()
  local compare
  if M.is_windows then
    path = path:gsub('/', '\\')
    start = start:gsub('/', '\\')
    compare = function(v)
      return v:lower()
    end
  else
    compare = function(v)
      return v
    end
  end
  local startl, Pl = split(start, sep), split(path, sep)
  local n = min(#startl, #Pl)
  if M.is_windows and n > 0 and at(Pl[1], 2) == ':' and Pl[1] ~= startl[1] then
    return path
  end
  local k = n + 1 -- default value if this loop doesn't bail out!
  for i = 1, n do
    if compare(startl[i]) ~= compare(Pl[i]) then
      k = i
      break
    end
  end
  local rell = {}
  for i = 1, #startl - k + 1 do
    rell[i] = '..'
  end
  if k <= #Pl then
    for i = k, #Pl do
      table.insert(rell, Pl[i])
    end
  end
  return table.concat(rell, sep)
end
---@param path any
function M.expanduser(path)
  assert_string(1, path)
  if path:sub(1, 1) ~= '~' then
    return path
  end

  local home = os.getenv('HOME')

  if not home then
    if not M.is_windows then
      -- no more options to try on Nix
      return nil, "failed to expand '~' (HOME not set)"
    end

    -- try alternatives on Windows
    home = os.getenv('USERPROFILE')
    if not home then
      local hd = os.getenv('HOMEDRIVE')
      local hp = os.getenv('HOMEPATH')
      if not (hd and hp) then
        return nil,
          "failed to expand '~' (HOME, USERPROFILE, and HOMEDRIVE and/or HOMEPATH not set)"
      end
      home = hd .. hp
    end
  end

  return home .. path:sub(2)
end

---Return a suitable full path to a new temporary file name.
-- unlike os.tmpname(), it always gives you a writeable path (uses TEMP environment variable on Windows)
function M.tmpname()
  local res = os.tmpname()
  -- On Windows if Lua is compiled using MSVC14 os.tmpname
  -- already returns an absolute path within TEMP env variable directory,
  -- no need to prepend it.
  if M.is_windows and not res:find(':') then
    res = os.getenv('TEMP') .. res
  end
  return res
end
---@param path1 any
---@param path2 any
function M.common_prefix(path1, path2)
  assert_string(1, path1)
  assert_string(2, path2)
  -- get them in order!
  if #path1 > #path2 then
    path2, path1 = path1, path2
  end
  local compare
  if M.is_windows then
    path1 = path1:gsub('/', '\\')
    path2 = path2:gsub('/', '\\')
    compare = function(v)
      return v:lower()
    end
  else
    compare = function(v)
      return v
    end
  end
  for i = 1, #path1 do
    if compare(at(path1, i)) ~= compare(at(path2, i)) then
      local cp = path1:sub(1, i - 1)
      if at(path1, i - 1) ~= sep then
        cp = M.dirname(cp)
      end
      return cp
    end
  end
  if at(path2, #path1 + 1) ~= sep then
    path1 = M.dirname(path1)
  end
  return path1
end

return M
