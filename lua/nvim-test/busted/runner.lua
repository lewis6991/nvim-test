if package.config:sub(1, 1) == '\\' then
  -- MSYS shells can leave `--lpath` patterns as `/d/.../?.lua` when invoking
  -- native nvim.exe, so normalize just those arguments before Busted parses `arg`.
  local function normalize_lua_path(path)
    local drive, tail = path:match('^/([A-Za-z])/(.*)$')
    if not drive then
      return path
    end

    return string.format('%s:/%s', drive:upper(), tail)
  end

  local expect_lpath
  for i, value in ipairs(arg) do
    if expect_lpath then
      arg[i] = normalize_lua_path(value)
      expect_lpath = nil
    elseif value == '--lpath' or value == '-m' then
      expect_lpath = true
    elseif value:match('^--lpath=') then
      arg[i] = '--lpath=' .. normalize_lua_path(value:sub(9))
    elseif value:match('^-m.+') then
      arg[i] = '-m' .. normalize_lua_path(value:sub(3))
    end
  end
end

require('busted.runner')({ standalone = false })
