local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')

--- @class nvim_test.util.fs
local M = {}

local DEFAULT_MODE = 420 -- 0644

--- @param path string
--- @return string? contents
--- @return string? err
function M.read_file(path)
  local fd, err = uv.fs_open(path, 'r', DEFAULT_MODE)
  if not fd then
    return nil, tostring(err)
  end

  local stat, stat_err = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil, tostring(stat_err)
  end

  local size = stat.size or 0
  local data, read_err = uv.fs_read(fd, size, 0)
  uv.fs_close(fd)

  if not data then
    return nil, tostring(read_err)
  end

  return data
end

local function split_lines(str)
  local lines = {}
  local start = 1
  local len = #str

  while start <= len do
    local newline = str:find('\n', start, true)
    if newline then
      lines[#lines + 1] = str:sub(start, newline - 1)
      start = newline + 1
    else
      lines[#lines + 1] = str:sub(start)
      break
    end
  end

  return lines
end

--- @param path string
--- @return string[]? lines
--- @return string? err
function M.read_lines(path)
  local data, err = M.read_file(path)
  if not data then
    return nil, err
  end

  if data == '' then
    return {}
  end

  return split_lines(data)
end

local function write(path, flags, payload)
  local fd, err = uv.fs_open(path, flags, DEFAULT_MODE)
  if not fd then
    return nil, tostring(err)
  end

  local bytes, write_err = uv.fs_write(fd, payload, -1)
  uv.fs_close(fd)
  if not bytes then
    return nil, tostring(write_err)
  end

  return true
end

--- @param path string
--- @param lines string[]
--- @return boolean
function M.write_lines(path, lines)
  local payload
  if #lines == 0 then
    payload = ''
  else
    payload = table.concat(lines, '\n') .. '\n'
  end

  local ok, err = write(path, 'w', payload)
  if not ok then
    error(err)
  end

  return true
end

--- @param path string
--- @param lines string[]
--- @return boolean
function M.append_lines(path, lines)
  if #lines == 0 then
    return true
  end

  local payload = table.concat(lines, '\n') .. '\n'
  local ok, err = write(path, 'a', payload)
  if not ok then
    error(err)
  end

  return true
end

return M
