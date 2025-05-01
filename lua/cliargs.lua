local M = {}

function M:parse(arguments)
  -- Clean up the entire module (unload the scripts) as it's expected to be
  -- discarded after use.
  local loaded = package.loaded --[[@as table<string,table>]]
  for k, v in pairs(loaded) do
    if (v == M) or (k:match('cliargs')) then
      loaded[k] = nil
    end
  end

  M = nil

  return require('cliargs.core')():parse(arguments)
end

return M
