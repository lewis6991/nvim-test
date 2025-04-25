local uv = vim.uv

local M = {}

function M.monotime()
  uv.update_time()
  return uv.now() * 1e-3
end

function M.gettime()
  local sec, usec = uv.gettimeofday()
  return sec + usec * 1e-6
end

function M.sleep(sec)
  uv.sleep(sec * 1e3)
end

return M
