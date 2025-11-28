--- Listing files in directories and creating/removing directory paths.
--
-- Dependencies: `pl.utils`, `pl.path`
--
-- Soft Dependencies: `ffi` (either are used on Windows for copying/moving files)

local utils = require('pl.utils')
local path = require('pl.path')
local is_windows = path.is_windows
local sub = string.sub
local assert_arg, assert_string = utils.assert_arg, utils.assert_string

local M = {}

--- @param l any
--- @return any
local function makelist(l)
  return setmetatable(l, require('pl.List'))
end

--- @param n any
--- @param val any
--- @return any
local function assert_dir(n, val)
  assert_arg(n, val, 'string', path.isdir, 'not a directory', 4)
end

--- @param mask string
--- @return string
local function filemask(mask)
  mask = utils.escape(path.normcase(mask))
  return '^' .. mask:gsub('%%%*', '.*'):gsub('%%%?', '.') .. '$'
end

--- Test whether a file name matches a shell pattern.
--- Both parameters are case-normalized if operating system is
--- case-insensitive.
--- @param filename string
--- @param pattern string A shell pattern. The only special characters are
--- `'*'` and `'?'`: `'*'` matches any sequence of characters and
--- `'?'` matches any single character.
--- @return bool
function M.fnmatch(filename, pattern)
  assert_string(1, filename)
  assert_string(2, pattern)
  return path.normcase(filename):find(filemask(pattern)) ~= nil
end

--- Return a list of all file names within an array which match a pattern.
--- @tab filenames An array containing file names.
--- @string pattern A shell pattern (see `fnmatch`).
--- @param filenames any
--- @param pattern any
--- @return string[] : matching file names.
function M.filter(filenames, pattern)
  assert_arg(1, filenames, 'table')
  assert_string(2, pattern)
  local res = {}
  local mask = filemask(pattern)
  for _, f in ipairs(filenames) do
    if path.normcase(f):find(mask) then
      table.insert(res, f)
    end
  end
  return makelist(res)
end

--- @param dirname any
--- @param filemode any
--- @param match any
--- @return any
local function _listfiles(dirname, filemode, match)
  local res = {}
  local check = filemode and path.isfile or path.isdir
  if not dirname then
    dirname = '.'
  end
  for f in path.dir(dirname) do
    if f ~= '.' and f ~= '..' then
      local p = path.join(dirname, f)
      if check(p) and (not match or match(f)) then
        table.insert(res, p)
      end
    end
  end
  return makelist(res)
end

--- return a list of all files in a directory which match a shell pattern.
--- @param dirname any
--- @param mask any A shell pattern (see `fnmatch`). If not given, all files are returned.
--- @return string[] files
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
--- @param dirname any
--- @return string[] directories
function M.getdirectories(dirname)
  dirname = dirname or '.'
  assert_dir(1, dirname)
  return _listfiles(dirname, false)
end

local ffi --- @type ffilib?
local ffi_checked, CopyFile, MoveFile, GetLastError, win32_errors, cmd_tmpfile

--- @param cmd any
--- @param parms any
--- @return any
local function execute_command(cmd, parms)
  cmd_tmpfile = cmd_tmpfile or path.tmpname()
  local err = is_windows and ' > ' or ' 2> '
  cmd = cmd .. ' ' .. parms .. err .. utils.quote_arg(cmd_tmpfile)
  local ret = utils.execute(cmd)
  if not ret then
    local err = (utils.readfile(cmd_tmpfile):gsub('\n(.*)', ''))
    os.remove(cmd_tmpfile)
    return false, err
  else
    os.remove(cmd_tmpfile)
    return true
  end
end

--- @return any
local function find_ffi_copyfile()
  if ffi_checked then
    return
  end

  ffi_checked = true
  local ok
  --- @type boolean, ffilib?
  ok, ffi = pcall(require, 'ffi')
  if not ok then
    ffi = nil
    return
  end
  assert(ffi)

  ffi.cdef([[
          int CopyFileA(const char *src, const char *dest, int iovr);
          int MoveFileA(const char *src, const char *dest);
          int GetLastError();
      ]])
  CopyFile = ffi.C.CopyFileA
  MoveFile = ffi.C.MoveFileA
  GetLastError = ffi.C.GetLastError

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

--- @param f1 string
--- @param f2 string
--- @return any
local function two_arguments(f1, f2)
  return utils.quote_arg(f1) .. ' ' .. utils.quote_arg(f2)
end

--- @param is_copy any
--- @param src any
--- @param dest any
--- @param flag any
--- @return bool success
--- @return string? error
local function file_op(is_copy, src, dest, flag)
  if flag == 1 and path.exists(dest) then
    return false, 'cannot overwrite destination'
  end
  if is_windows then
    -- if we haven't tried to load LuaJIT FFI before, then do so
    find_ffi_copyfile()
    -- fallback if there's no ffi, just use DOS commands *shudder*
    -- 'rename' involves a copy and then deleting the source.
    if not CopyFile then
      src = src:gsub('/', '\\')
      dest = dest:gsub('/', '\\')
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

--- copy a file.
--- @param src string source file
--- @param dest string destination file or directory
--- @param flag? bool flag true if you want to force the copy (default)
--- @return bool success
function M.copyfile(src, dest, flag)
  assert_string(1, src)
  assert_string(2, dest)
  flag = flag == nil or flag -- default to true
  return file_op(true, src, dest, flag and 0 or 1)
end

--- move a file.
--- @string src source file
--- @string dest destination file or directory
--- @treturn bool operation succeeded
--- @param src any
--- @param dest any
function M.movefile(src, dest)
  assert_string(1, src)
  assert_string(2, dest)
  return file_op(false, src, dest, 0)
end

--- @param dirname any
--- @param attrib any
--- @return string[]
--- @return string[]
local function _dirfiles(dirname, attrib)
  local dirs = {} --- @type string[]
  local files = {} --- @type string[]
  for f in path.dir(dirname) do
    if f ~= '.' and f ~= '..' then
      local p = path.join(dirname, f)
      if attrib(p, 'type') == 'directory' then
        table.insert(dirs, f)
      else
        table.insert(files, f)
      end
    end
  end
  return makelist(dirs), makelist(files)
end

--- return an iterator which walks through a directory tree starting at root.
--- The iterator returns (root,dirs,files)
--- Note that dirs and files are lists of names (i.e. you must say path.join(root,d)
--- to get the actual full path)
--- If bottom_up is false (or not present), then the entries at the current level are returned
--- before we go deeper. This means that you can modify the returned list of directories before
--- continuing.
--- This is a clone of os.walk from the Python libraries.
--- @return function iterator returning root,dirs,files
--- @param root string A starting directory
--- @param bottom_up? boolean False if we start listing entries immediately.
--- @param follow_links? boolean follow symbolic links
function M.walk(root, bottom_up, follow_links)
  assert_dir(1, root)
  local attrib
  if is_windows or not follow_links then
    attrib = path.attrib
  else
    attrib = path.link_attrib
  end

  local to_scan = { root }
  local to_return = {}
  local iter = function()
    while #to_scan > 0 do
      local current_root = table.remove(to_scan)
      local dirs, files = _dirfiles(current_root, attrib)
      for _, d in ipairs(dirs) do
        table.insert(to_scan, current_root .. path.sep .. d)
      end
      if not bottom_up then
        return current_root, dirs, files
      else
        table.insert(to_return, { current_root, dirs, files })
      end
    end
    if #to_return > 0 then
      return utils.unpack(table.remove(to_return))
    end
  end

  return iter
end

--- remove a whole directory tree.
--- Symlinks in the tree will be deleted without following them.
--- @param fullpath string fullpath A directory path (must be an actual directory, not a symlink)
--- @return true?
--- @return string? error if failed
function M.rmtree(fullpath)
  assert_dir(1, fullpath)
  if path.islink(fullpath) then
    return false, 'will not follow symlink'
  end
  for root, _, files in M.walk(fullpath, true) do
    if path.islink(root) then
      -- sub dir is a link, remove link, do not follow
      if is_windows then
        -- Windows requires using "rmdir". Deleting the link like a file
        -- will instead delete all files from the target directory!!
        local res, err = vim.uv.fs_rmdir(root)
        if not res then
          return nil, err .. ': ' .. root
        end
      else
        local res, err = os.remove(root)
        if not res then
          return nil, err .. ': ' .. root
        end
      end
    else
      for _, f in ipairs(files) do
        local res, err = os.remove(path.join(root, f))
        if not res then
          return nil, err .. ': ' .. path.join(root, f)
        end
      end
      local res, err = vim.uv.fs_rmdir(root)
      if not res then
        return nil, err .. ': ' .. root
      end
    end
  end
  return true
end

do
  local dirpat = is_windows and '(.+)\\[^\\]+$' or '(.+)/[^/]+$'

  local _makepath
  --- @param p any
  --- @return any
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
      return path.mkdir(p)
    end
    return true
  end

  --- create a directory path.
  -- This will create subdirectories as necessary!
  --- @string p A directory path
  --- @return true on success, nil + errormsg on failure
  --- @param p any
  function M.makepath(p)
    assert_string(1, p)
    if is_windows then
      p = p:gsub('/', '\\')
    end
    return _makepath(path.abspath(p))
  end
end

--- clone a directory tree. Will always try to create a new directory structure
-- if necessary.
--- @string path1 the base path of the source tree
--- @string path2 the new base path for the destination
--- @func file_fun an optional function to apply on all files
--- @bool verbose an optional boolean to control the verbosity of the output.
--  It can also be a logging function that behaves like print()
--- @param path1 any
--- @param path2 any
--- @param file_fun any
--- @param verbose any
--- @return true?
--- @return string|string[] : error message, or list of failed directory creations
--- @return string[] : failed file operations
function M.clonetree(path1, path2, file_fun, verbose)
  assert_string(1, path1)
  assert_string(2, path2)
  if verbose == true then
    verbose = print
  end
  local abspath, normcase, join = path.abspath, path.normcase, path.join
  local faildirs, failfiles = {}, {}
  if not path.isdir(path1) then
    error('source is not a valid directory')
  end
  path1 = abspath(normcase(path1))
  path2 = abspath(normcase(path2))
  if verbose then
    verbose('normalized:', path1, path2)
  end
  -- particularly NB that the new path isn't fully contained in the old path
  if path1 == path2 then
    error('paths are the same')
  end
  local _, i2 = path2:find(path1, 1, true)
  if i2 == #path1 and path2:sub(i2 + 1, i2 + 1) == path.sep then
    error('destination is a subdirectory of the source')
  end
  local cp = path.common_prefix(path1, path2)
  local idx = #cp
  if idx == 0 then -- no common path, but watch out for Windows paths!
    if path1:sub(2, 2) == ':' then
      idx = 3
    end
  end
  for root, _, files in M.walk(path1) do
    local opath = path2 .. root:sub(idx)
    if verbose then
      verbose('paths:', opath, root)
    end
    if not path.isdir(opath) then
      local ret = M.makepath(opath)
      if not ret then
        table.insert(faildirs, opath)
      end
      if verbose then
        verbose('creating:', opath, ret)
      end
    end
    if file_fun then
      for _, f in ipairs(files) do
        local p1 = join(root, f)
        local p2 = join(opath, f)
        local ret = file_fun(p1, p2)
        if not ret then
          table.insert(failfiles, p2)
        end
        if verbose then
          verbose('files:', p1, p2, ret)
        end
      end
    end
  end
  return true, faildirs, failfiles
end

-- each entry of the stack is an array with three items:
--- 1. The name of the directory
--- 2. The lfs iterator function
--- 3. The lfs iterator userdata
--- @param iterstack any
--- @return any
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
    entry = dirname .. path.sep .. entry
    if path.exists(entry) then -- Just in case a symlink is broken.
      local is_dir = path.isdir(entry)
      if is_dir then
        table.insert(iterstack, { entry, path.dir(entry) })
      end
      return entry, is_dir
    end
  end

  return treeiter(iterstack) -- tail-call to try next
end

--- return an iterator over all entries in a directory tree
--- @string d a directory
--- @return function iterator giving pathname and mode (true for dir, false otherwise)
--- @param d any
function M.dirtree(d)
  assert(d and d ~= '', 'directory parameter is missing or empty')

  local last = sub(d, -1)
  if last == path.sep or last == '/' then
    d = sub(d, 1, -2)
  end

  local iterstack = { { d, path.dir(d) } }

  return treeiter, iterstack
end

--- Recursively returns all the file starting at 'path'. It can optionally take a shell pattern and
--- only returns files that match 'shell_pattern'. If a pattern is given it will do a case insensitive search.
--- @param start_path string A directory.
--- @param shell_pattern A shell pattern (see `fnmatch`).
--- @return string[] containing all the files found recursively starting at 'path' and filtered by 'shell_pattern'.
function M.getallfiles(start_path, shell_pattern)
  start_path = start_path or '.'
  assert_dir(1, start_path)
  shell_pattern = shell_pattern or '*'

  local files = {}
  local normcase = path.normcase
  for filename, mode in M.dirtree(start_path) do
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
