local utils = require('busted.utils')

local fs = vim.fs

local function resolve_handler(output)
  if output:match('%.lua$') then
    return dofile(fs.normalize(output))
  end

  local ok, handler = pcall(require, output)
  if ok then
    return handler
  end

  ok, handler = pcall(require, 'busted.outputHandlers.' .. output)
  if ok then
    return handler
  end

  error(handler, 0)
end

return function()
  local loadOutputHandler = function(busted, output, options)
    utils.copy_interpreter_args(options.arguments)

    local handler
    local ok, err = pcall(function()
      handler = resolve_handler(output)
    end)

    if not ok then
      busted.publish({ 'error', 'output' }, { descriptor = 'output', name = output }, nil, err, {})
      ok, err = pcall(function()
        handler = resolve_handler(options.defaultOutput)
      end)
      if not ok then
        error(err, 0)
      end
    end

    handler(options):subscribe(options)
  end

  return loadOutputHandler
end
