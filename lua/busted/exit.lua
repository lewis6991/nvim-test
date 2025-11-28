local function exit(code, force)
  code = code or 0

  if not force and code ~= 0 and _VERSION:match('^Lua 5%.[12]$') then
    error()
  elseif code ~= 0 then
    code = 1
  end

  if
    _VERSION == 'Lua 5.1'
    and (type(jit) ~= 'table' or not jit.version or jit.version_num < 20000)
  then
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

return exit
