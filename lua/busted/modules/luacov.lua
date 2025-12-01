return function()
  -- Function to initialize luacov if available
  local loadLuaCov = function(config)
    local result, luacov = pcall(require, 'luacov.runner')

    if not result then
      return true, 'LuaCov not found; skipping coverage setup.'
    end

    -- call it to start
    luacov(config)

    -- exclude busted files
    local configuration = luacov.configuration or {}
    luacov.configuration = configuration
    local exclude = configuration.exclude or {}
    configuration.exclude = exclude
    table.insert(exclude, 'busted_bootstrap$')
    table.insert(exclude, 'busted%.')
    table.insert(exclude, 'luassert%.')
    table.insert(exclude, 'pl%.')
    return true
  end

  return loadLuaCov
end
