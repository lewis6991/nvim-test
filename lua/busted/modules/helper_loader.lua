local utils = require('busted.utils')

return function(busted, helper, options)
  local old_arg = _G.arg
  local success, err = pcall(function()
    utils.copy_interpreter_args(options.arguments)
    _G.arg = options.arguments

    local fn
    if helper:match('%.lua$') then
      fn = dofile(vim.fs.normalize(helper))
    else
      fn = require(helper)
    end

    if type(fn) == 'function' then
      assert(fn(busted, helper, options))
    end
  end)

  arg = old_arg

  if not success then
    return nil, err
  end
  return true
end
