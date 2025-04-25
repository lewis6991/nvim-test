--- Path manipulation and file queries.
--
-- This is modelled after Python's os.path library (10.1); see @{04-paths.md|the Guide}.
--
-- NOTE: the functions assume the paths being dealt with to originate
-- from the OS the application is running on. Windows drive letters are not
-- to be used when running on a Unix system for example. The one exception
-- is Windows paths to allow both forward and backward slashes (since Lua
-- also accepts those)
--
-- @module pl.path

local uv = vim.uv
local sub = string.sub
local getenv = os.getenv
local tmpnam = os.tmpname

local M = {}

function M.attrib(path, attr)
  local stat = uv.fs_stat(path)
  if attr == 'mode' then
    return stat and stat.type or ''
  elseif attr == 'modification' then
    if not stat then
      return nil
    end
    local mtime = stat.mtime
    return mtime.sec + mtime.nsec * 1e-9
  else
    error('not implemented')
  end
end

--- Lua iterator over the entries of a given directory.
-- Implicit link to [`luafilesystem.dir`](https://keplerproject.github.io/luafilesystem/manual.html#reference)
-- @function dir
function M.dir(p)
  local fs = uv.fs_scandir(p)
  return function()
    if not fs then
      return
    end
    return uv.fs_scandir_next(fs)
  end
end

--- Creates a directory.
-- Implicit link to [`luafilesystem.mkdir`](https://keplerproject.github.io/luafilesystem/manual.html#reference)
-- @function mkdir
function M.mkdir(d)
  return uv.fs_mkdir(d, 493) -- octal 755
end

--- Get the working directory.
-- Implicit link to [`luafilesystem.currentdir`](https://keplerproject.github.io/luafilesystem/manual.html#reference)
-- @function currentdir
function M.currentdir()
  return assert(uv.cwd())
end

--- Changes the working directory.
-- On Windows, if a drive is specified, it also changes the current drive. If
-- only specifying the drive, it will only switch drive, but not modify the path.
-- Implicit link to [`luafilesystem.chdir`](https://keplerproject.github.io/luafilesystem/manual.html#reference)
-- @function chdir
function M.chdir(d)
  return uv.chdir(d)
end

--- is this a directory?
-- @string P A file path
function M.isdir(P)
  return M.attrib(P, 'mode') == 'directory'
end

--- is this a file?
-- @string P A file path
function M.isfile(P)
  return M.attrib(P, 'mode') == 'file'
end

--- return size of a file.
-- @string P A file path
function M.getsize(P)
  return M.attrib(P, 'size')
end

--- does a path exist?
-- @string P A file path
-- @return the file path if it exists (either as file, directory, socket, etc), nil otherwise
function M.exists(P)
  return M.attrib(P, 'mode') ~= nil and P
end

--- Return the time of last access as the number of seconds since the epoch.
-- @string P A file path
function M.getatime(P)
  return M.attrib(P, 'access')
end

--- Return the time of last modification as the number of seconds since the epoch.
-- @string P A file path
function M.getmtime(P)
  return M.attrib(P, 'modification')
end

---Return the system's ctime as the number of seconds since the epoch.
-- @string P A file path
function M.getctime(P)
  return M.attrib(P, 'change')
end

local function at(s, i)
  return s:sub(i, i)
end

--- the directory separator character for the current platform.
-- @field dir_separator
local dir_separator = _G.package.config:sub(1, 1)

--- boolean flag this is a Windows platform.
-- @field is_windows
M.is_windows = dir_separator == '\\'

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

--- are we running Windows?
-- @class field
-- @name path.is_windows

--- path separator for this platform.
-- @class field
-- @name path.sep

--- separator for PATH for this platform
-- @class field
-- @name path.dirsep

--- given a path, return the directory part and a file part.
-- if there's no directory part, the first value will be empty
-- @string P A file path
-- @return directory part
-- @return file part
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
function M.splitpath(P)
  local i = #P
  local ch = at(P, i)
  while i > 0 and ch ~= sep and ch ~= other_sep do
    i = i - 1
    ch = at(P, i)
  end
  if i == 0 then
    return '', P
  end
  return sub(P, 1, i - 1), sub(P, i + 1)
end

--- return an absolute path.
-- @string P A file path
-- @string[opt] pwd optional start path to use (default is current dir)
function M.abspath(P, pwd)
  local use_pwd = pwd ~= nil
  if not use_pwd and not uv.cwd() then
    return P
  end
  P = P:gsub('[\\/]$', '')
  pwd = pwd or uv.cwd()
  if not M.isabs(P) then
    P = M.join(pwd, P)
  elseif M.is_windows and not use_pwd and at(P, 2) ~= ':' and at(P, 2) ~= '\\' then
    P = pwd:sub(1, 2) .. P -- attach current drive to path like '\\fred.txt'
  end
  return vim.fs.normalize(P)
end

--- given a path, return the root part and the extension part.
-- if there's no extension part, the second value will be empty
-- @string P A file path
-- @treturn string root part (everything upto the "."", maybe empty)
-- @treturn string extension part (including the ".", maybe empty)
-- @usage
-- local file_path, ext = path.splitext("/bonzo/dog_stuff/cat.txt")
-- assert(file_path == "/bonzo/dog_stuff/cat")
-- assert(ext == ".txt")
--
-- local file_path, ext = path.splitext("")
-- assert(file_path == "")
-- assert(ext == "")
function M.splitext(P)
  local i = #P
  local ch = at(P, i)
  while i > 0 and ch ~= '.' do
    if seps[ch] then
      return P, ''
    end
    i = i - 1
    ch = at(P, i)
  end
  if i == 0 then
    return P, ''
  end
  return sub(P, 1, i - 1), sub(P, i)
end

--- get the extension part of a path.
-- @string P A file path
-- @treturn string
-- @see splitext
-- @usage
-- path.extension("/some/path/file.txt") -- ".txt"
-- path.extension("/some/path/file_txt") -- "" (empty string)
function M.extension(P)
  local _, p2 = M.splitext(P)
  return p2
end

--- is this an absolute path?
-- @string P A file path
-- @usage
-- path.isabs("hello/path")    -- false
-- path.isabs("/hello/path")   -- true
-- -- Windows;
-- path.isabs("hello\path")    -- false
-- path.isabs("\hello\path")   -- true
-- path.isabs("C:\hello\path") -- true
-- path.isabs("C:hello\path")  -- false
function M.isabs(P)
  if M.is_windows and at(P, 2) == ':' then
    return seps[at(P, 3)] ~= nil
  end
  return seps[at(P, 1)] ~= nil
end

--- return the path resulting from combining the individual paths.
-- if the second (or later) path is absolute, we return the last absolute path (joined with any non-absolute paths following).
-- empty elements (except the last) will be ignored.
-- @string p1 A file path
-- @string p2 A file path
-- @string ... more file paths
-- @treturn string the combined path
-- @usage
-- path.join("/first","second","third")   -- "/first/second/third"
-- path.join("first","second/third")      -- "first/second/third"
-- path.join("/first","/second","third")  -- "/second/third"
function M.join(p1, p2, ...)
  if select('#', ...) > 0 then
    local p = M.join(p1, p2)
    local args = { ... }
    for i = 1, #args do
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
-- for Windows it converts;
--
-- * the path to lowercase
-- * forward slashes to backward slashes
-- @string P A file path
-- @usage path.normcase("/Some/Path/File.txt")
-- -- Windows: "\some\path\file.txt"
-- -- Others : "/Some/Path/File.txt"
function M.normcase(P)
  if M.is_windows then
    return P:gsub('/', '\\'):lower()
  end
  return P
end

--- normalize a path name.
-- `A//B`, `A/./B`, and `A/foo/../B` all become `A/B`.
--
-- An empty path results in '.'.
-- @string P a file path
function M.normpath(P)
  return vim.fs.normalize(P)
end

---Return a suitable full path to a new temporary file name.
-- unlike os.tmpname(), it always gives you a writeable path (uses TEMP environment variable on Windows)
function M.tmpname()
  local res = tmpnam()
  -- On Windows if Lua is compiled using MSVC14 os.tmpname
  -- already returns an absolute path within TEMP env variable directory,
  -- no need to prepend it.
  if M.is_windows and not res:find(':') then
    res = getenv('TEMP') .. res
  end
  return res
end

return M
