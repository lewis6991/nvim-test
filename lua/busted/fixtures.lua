--- @class busted.fixtures
local M = {}

--- @param path? string
--- @return string?
local function normalize(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(path)
end

--- @param level integer
--- @return string?
local function source_path(level)
  local info = debug.getinfo(level, 'S')
  local src = info and info.source or ''
  if src:sub(1, 1) == '@' then
    src = src:sub(2)
  end
  return normalize(src)
end

--- returns an absolute path to where the current test file is located.
--- @param sub_path? string relative path to append
--- @return string absolute path
function M.path(sub_path)
  if type(sub_path) ~= 'string' and sub_path ~= nil then
    error(
      "bad argument to 'path' expected a string (relative filename) or nil, got: " .. type(sub_path),
      2
    )
  end

  local my_source = source_path(1)
  local level = 2
  local caller = source_path(level)
  while caller == my_source do
    level = level + 1
    caller = source_path(level)
  end

  local base_dir = caller and vim.fs.dirname(caller) or vim.uv.cwd()
  assert(type(base_dir) == 'string', 'base_dir must be resolved')
  if sub_path and #sub_path > 0 then
    local rel = sub_path
    assert(type(rel) == 'string', 'relative path must be a string')
    base_dir = vim.fs.joinpath(base_dir, rel)
  end
  return vim.fs.normalize(base_dir)
end

--- @param path string
--- @return string? data
--- @return string? err
local function read_file(path)
  local fd, err = vim.uv.fs_open(path, 'r', 438)
  if not fd then
    return nil, err
  end
  local stat, stat_err = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return nil, stat_err
  end
  local data, read_err = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  if not data then
    return nil, read_err
  end
  return data
end

--- @param rel_path string
--- @param _is_bin? boolean
--- @return string
function M.read(rel_path, _is_bin)
  if type(rel_path) ~= 'string' then
    error(
      "bad argument to 'read' expected a string (relative filename), got: " .. type(rel_path),
      2
    )
  end

  local fname = M.path(rel_path)
  local contents, err = read_file(fname)
  if not contents then
    error(("Error reading file '%s': %s"):format(tostring(fname), tostring(err)), 2)
  end

  return contents
end

--- @param rel_path string
--- @return unknown
function M.load(rel_path)
  if type(rel_path) ~= 'string' then
    error(
      "bad argument to 'load' expected a string (relative filename), got: " .. type(rel_path),
      2
    )
  end
  local extension = 'lua'
  if not rel_path:match('%.' .. extension .. '$') then
    rel_path = rel_path .. '.' .. extension
  end
  local code, err = M.read(rel_path)
  if not code then
    error(("Error loading file '%s': %s"):format(tostring(rel_path), tostring(err)), 2)
  end

  local func, err1 = (loadstring or load)(code, rel_path)
  if not func then
    error(("Error loading code from '%s': %s"):format(tostring(rel_path), tostring(err1)), 2)
  end

  return func()
end

return M
