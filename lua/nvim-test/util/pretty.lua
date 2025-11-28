local inspect = vim.inspect

local M = {}

function M.write(value)
  if type(value) == 'string' then
    return value
  end
  if value == nil then
    return 'nil'
  end
  return inspect(value)
end

return M
