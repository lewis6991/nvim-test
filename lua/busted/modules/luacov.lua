--- @return fun(config?: string|table): (boolean, string?)
return function()
  --- Function to initialize luacov if available
  --- @param config? string|table configuration passed to luacov
  --- @return boolean, string?
  local loadLuaCov = function(config)
    local result, luacov = pcall(require, 'luacov.runner')

    if not result then
      return true, 'LuaCov not found; skipping coverage setup.'
    end

    --- @cast luacov luacov.runner
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
