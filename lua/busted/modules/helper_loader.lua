local utils = require('busted.utils')
local fs = vim.fs

return function()
  local loadHelper = function(busted, helper, options)
    local old_arg = _G.arg
    local success, err = pcall(function()
      local fn

      utils.copy_interpreter_args(options.arguments)
      ---@diagnostic disable-next-line: global-in-non-module
      _G.arg = options.arguments

      if helper:match('%.lua$') then
        fn = dofile(fs.normalize(helper))
      else
        fn = require(helper)
      end

      if type(fn) == 'function' then
        assert(fn(busted, helper, options))
      end
    end)

    ---@diagnostic disable-next-line: global-in-non-module
    _G.arg = old_arg --luacheck: ignore

    if not success then
      return nil, err
    end
    return true
  end

  return loadHelper
end
