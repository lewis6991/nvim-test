--- Listing files in directories and creating/removing directory paths.
--
-- Dependencies: `pl.utils`, `pl.path`
--
-- Soft Dependencies: ``ffi` (either are used on Windows for copying/moving files)
-- @module pl.dir

local utils = require('pl.utils')
local path = require('pl.path')
local is_windows = path.is_windows
local ldir = path.dir
local mkdir = path.mkdir
local sub = string.sub
local remove = os.remove
local append = table.insert
local assert_arg, assert_string = utils.assert_arg, utils.assert_string

local exists, isdir = path.exists, path.isdir
local sep = path.sep

local M = {}

local function makelist(l)
  return setmetatable(l, require('pl.List'))
end

local function assert_dir(n, val)
  assert_arg(n, val, 'string', path.isdir, 'not a directory', 4)
end

local function filemask(mask)
  mask = utils.escape(path.normcase(mask))
  return '^' .. mask:gsub('%%%*', '.*'):gsub('%%%?', '.') .. '$'
end

local function _listfiles(dirname, filemode, match)
  local res = {}
  local check = filemode and path.isfile or path.isdir
  if not dirname then
    dirname = '.'
  end
  for f in ldir(dirname) do
    if f ~= '.' and f ~= '..' then
      local p = path.join(dirname, f)
      if check(p) and (not match or match(f)) then
        append(res, p)
      end
    end
  end
  return makelist(res)
end

--- return a list of all files in a directory which match a shell pattern.
-- @string[opt='.'] dirname A directory.
-- @string[opt] mask A shell pattern (see `fnmatch`). If not given, all files are returned.
-- @treturn {string} list of files
-- @raise dirname and mask must be strings
function M.getfiles(dirname, mask)
  dirname = dirname or '.'
  assert_dir(1, dirname)
  if mask then
    assert_string(2, mask)
  end
  local match
  if mask then
    mask = filemask(mask)
    match = function(f)
      return path.normcase(f):find(mask)
    end
  end
  return _listfiles(dirname, true, match)
end

--- return a list of all subdirectories of the directory.
-- @string[opt='.'] dirname A directory.
-- @treturn {string} a list of directories
-- @raise dir must be a valid directory
function M.getdirectories(dirname)
  dirname = dirname or '.'
  assert_dir(1, dirname)
  return _listfiles(dirname, false)
end

local ffi, ffi_checked, CopyFile, MoveFile, GetLastError, win32_errors, cmd_tmpfile

local function execute_command(cmd, parms)
  if not cmd_tmpfile then
    cmd_tmpfile = path.tmpname()
  end
  local err = path.is_windows and ' > ' or ' 2> '
  cmd = cmd .. ' ' .. parms .. err .. utils.quote_arg(cmd_tmpfile)
  local ret = utils.execute(cmd)
  if not ret then
    local err = (utils.readfile(cmd_tmpfile):gsub('\n(.*)', ''))
    remove(cmd_tmpfile)
    return false, err
  else
    remove(cmd_tmpfile)
    return true
  end
end

local function find_ffi_copyfile()
  if not ffi_checked then
    ffi_checked = true
    local res
    res, ffi = pcall(require, 'ffi')
    if not res then
      ffi = nil
      return
    end
  else
    return
  end
  if ffi then
    ffi.cdef([[
            int CopyFileA(const char *src, const char *dest, int iovr);
            int MoveFileA(const char *src, const char *dest);
            int GetLastError();
        ]])
    CopyFile = ffi.C.CopyFileA
    MoveFile = ffi.C.MoveFileA
    GetLastError = ffi.C.GetLastError
  end
  win32_errors = {
    ERROR_FILE_NOT_FOUND = 2,
    ERROR_PATH_NOT_FOUND = 3,
    ERROR_ACCESS_DENIED = 5,
    ERROR_WRITE_PROTECT = 19,
    ERROR_BAD_UNIT = 20,
    ERROR_NOT_READY = 21,
    ERROR_WRITE_FAULT = 29,
    ERROR_READ_FAULT = 30,
    ERROR_SHARING_VIOLATION = 32,
    ERROR_LOCK_VIOLATION = 33,
    ERROR_HANDLE_DISK_FULL = 39,
    ERROR_BAD_NETPATH = 53,
    ERROR_NETWORK_BUSY = 54,
    ERROR_DEV_NOT_EXIST = 55,
    ERROR_FILE_EXISTS = 80,
    ERROR_OPEN_FAILED = 110,
    ERROR_INVALID_NAME = 123,
    ERROR_BAD_PATHNAME = 161,
    ERROR_ALREADY_EXISTS = 183,
  }
end

local function two_arguments(f1, f2)
  return utils.quote_arg(f1) .. ' ' .. utils.quote_arg(f2)
end

local function file_op(is_copy, src, dest, flag)
  if flag == 1 and path.exists(dest) then
    return false, 'cannot overwrite destination'
  end
  if is_windows then
    -- if we haven't tried to load LuaJIT FFI before, then do so
    find_ffi_copyfile()
    -- fallback if there's no FFI, just use DOS commands *shudder*
    -- 'rename' involves a copy and then deleting the source.
    if not CopyFile then
      if path.is_windows then
        src = src:gsub('/', '\\')
        dest = dest:gsub('/', '\\')
      end
      local res, err = execute_command('copy', two_arguments(src, dest))
      if not res then
        return false, err
      end
      if not is_copy then
        return execute_command('del', utils.quote_arg(src))
      end
      return true
    else
      if path.isdir(dest) then
        dest = path.join(dest, path.basename(src))
      end
      local ret
      if is_copy then
        ret = CopyFile(src, dest, flag)
      else
        ret = MoveFile(src, dest)
      end
      if ret == 0 then
        local err = GetLastError()
        for name, value in pairs(win32_errors) do
          if value == err then
            return false, name
          end
        end
        return false, 'Error #' .. err
      else
        return true
      end
    end
  else -- for Unix, just use cp for now
    return execute_command(is_copy and 'cp' or 'mv', two_arguments(src, dest))
  end
end

--- move a file.
-- @string src source file
-- @string dest destination file or directory
-- @treturn bool operation succeeded
-- @raise src and dest must be strings
function M.movefile(src, dest)
  assert_string(1, src)
  assert_string(2, dest)
  return file_op(false, src, dest, 0)
end

do
  local dirpat
  if path.is_windows then
    dirpat = '(.+)\\[^\\]+$'
  else
    dirpat = '(.+)/[^/]+$'
  end

  local _makepath
  function _makepath(p)
    -- windows root drive case
    if p:find('^%a:[\\]*$') then
      return true
    end
    if not path.isdir(p) then
      local subp = p:match(dirpat)
      if subp then
        local ok, err = _makepath(subp)
        if not ok then
          return nil, err
        end
      end
      return mkdir(p)
    else
      return true
    end
  end

  --- create a directory path.
  -- This will create subdirectories as necessary!
  -- @string p A directory path
  -- @return true on success, nil + errormsg on failure
  -- @raise failure to create
  function M.makepath(p)
    assert_string(1, p)
    if path.is_windows then
      p = p:gsub('/', '\\')
    end
    return _makepath(path.abspath(p))
  end
end

-- each entry of the stack is an array with three items:
-- 1. the name of the directory
-- 2. the lfs iterator function
-- 3. the lfs iterator userdata
local function treeiter(iterstack)
  local diriter = iterstack[#iterstack]
  if not diriter then
    return -- done
  end

  local dirname = diriter[1]
  local entry = diriter[2](diriter[3])
  if not entry then
    table.remove(iterstack)
    return treeiter(iterstack) -- tail-call to try next
  end

  if entry ~= '.' and entry ~= '..' then
    entry = dirname .. sep .. entry
    if exists(entry) then -- Just in case a symlink is broken.
      local is_dir = isdir(entry)
      if is_dir then
        table.insert(iterstack, { entry, ldir(entry) })
      end
      return entry, is_dir
    end
  end

  return treeiter(iterstack) -- tail-call to try next
end

--- return an iterator over all entries in a directory tree
-- @string d a directory
-- @return an iterator giving pathname and mode (true for dir, false otherwise)
-- @raise d must be a non-empty string
local function dirtree(d)
  assert(d and d ~= '', 'directory parameter is missing or empty')

  local last = sub(d, -1)
  if last == sep or last == '/' then
    d = sub(d, 1, -2)
  end

  local iterstack = { { d, ldir(d) } }

  return treeiter, iterstack
end

--- Recursively returns all the file starting at 'path'. It can optionally take a shell pattern and
-- only returns files that match 'shell_pattern'. If a pattern is given it will do a case insensitive search.
-- @string[opt='.'] start_path  A directory.
-- @string[opt='*'] shell_pattern A shell pattern (see `fnmatch`).
-- @treturn List(string) containing all the files found recursively starting at 'path' and filtered by 'shell_pattern'.
-- @raise start_path must be a directory
function M.getallfiles(start_path, shell_pattern)
  start_path = start_path or '.'
  assert_dir(1, start_path)
  shell_pattern = shell_pattern or '*'

  local files = {}
  local normcase = path.normcase
  for filename, mode in dirtree(start_path) do
    if not mode then
      local mask = filemask(shell_pattern)
      if normcase(filename):find(mask) then
        files[#files + 1] = filename
      end
    end
  end

  return makelist(files)
end

return M
