local function merge_tables(base, overrides)
  return vim.deep_extend('force', base or {}, overrides or {})
end

return function()
  -- Function to load the .busted configuration file if available
  local loadBustedConfigurationFile = function(configFile, config, defaults)
    if type(configFile) ~= 'table' then
      return nil, '.busted file does not return a table.'
    end

    defaults = defaults or {}
    local run = config.run or defaults.run

    if run and run ~= '' then
      local runConfig = configFile[run]

      if type(runConfig) == 'table' then
        config = merge_tables(runConfig, config)
      else
        return nil, 'Task `' .. run .. '` not found, or not a table.'
      end
    elseif type(configFile.default) == 'table' then
      config = merge_tables(configFile.default, config)
    end

    if type(configFile._all) == 'table' then
      config = merge_tables(configFile._all, config)
    end

    config = merge_tables(defaults, config)

    return config
  end

  return loadBustedConfigurationFile
end
