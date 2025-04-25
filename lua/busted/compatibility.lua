local M = {}

M.loadstring = loadstring or load
M.unpack = table.unpack or unpack

function M.exit(code, force)
  if not force and code ~= 0 then
    error()
  elseif code ~= 0 then
    code = 1
  end
  if type(jit) ~= 'table' or not jit.version or jit.version_num < 20000 then
    -- From Lua 5.1 manual:
    -- > The userdata itself is freed only in the next
    -- > garbage-collection cycle.
    -- Call collectgarbage() while collectgarbage('count')
    -- changes + 3 times, at least 3 times,
    -- at max 100 times (to prevent infinite loop).
    local times_const = 0
    for _ = 1, 100 do
      local count_before = collectgarbage('count')
      collectgarbage()
      local count_after = collectgarbage('count')
      if count_after == count_before then
        times_const = times_const + 1
        if times_const > 3 then
          break
        end
      else
        times_const = 0
      end
    end
  end
  os.exit(code, true)
end

return M
