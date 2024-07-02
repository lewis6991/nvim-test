local orig_pcall = pcall

if package.loaded['jit'] then
  local coxpcall = orig_pcall(require, 'coxpcall')
  if coxpcall then
    pcall = coxpcall.pcall
  end
end

local helpers = require('nvim-test.helpers')

return function(_busted, _helper, options)
  helpers.options = options
  return true
end
