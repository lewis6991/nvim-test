local inspect = vim.inspect

local M = {}

function M.write(value, opts)
  if type(value) == 'string' then
    return value
  end
  return inspect(value, opts)
end

return M
