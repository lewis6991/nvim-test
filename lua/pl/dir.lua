--- Listing files in directories and creating/removing directory paths.
--
-- Dependencies: `pl.utils`, `pl.path`
--
-- Soft Dependencies: ``ffi` (either are used on Windows for copying/moving files)
-- @module pl.dir

local utils = require('pl.utils')
local path = require('pl.path')
local assert_string = utils.assert_string

local exists, isdir = path.exists, path.isdir
local sep = path.sep

local M = {}

local function filemask(mask)
  mask = utils.escape(path.normcase(mask))
  return '^' .. mask:gsub('%%%*', '.*'):gsub('%%%?', '.') .. '$'
end

local function listfiles(dirname, filemode, match)
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
  return res
end

--- return a list of all files in a directory which match a shell pattern.
-- @string[opt='.'] dirname A directory.
-- @string[opt] mask A shell pattern (see `fnmatch`). If not given, all files are returned.
-- @treturn {string} list of files
-- @raise dirname and mask must be strings
function M.getfiles(dirname, mask)
  dirname = dirname or '.'
  assert(path.isdir(dirname), 'not a directory')
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
  return listfiles(dirname, true, match)
end

--- return a list of all subdirectories of the directory.
-- @string[opt='.'] dirname A directory.
-- @treturn {string} a list of directories
-- @raise dir must be a valid directory
function M.getdirectories(dirname)
  dirname = dirname or '.'
  assert(path.isdir(dirname), 'not a directory')
  return listfiles(dirname, false)
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
        table.insert(iterstack, { entry, path.dir(entry) })
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

  local last = d:sub(-1)
  if last == sep or last == '/' then
    d = d:sub(1, -2)
  end

  local iterstack = { { d, path.dir(d) } }

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
  assert(path.isdir(start_path), 'not a directory')
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

  return files
end

return M
