local M = {}

function M.isatty(_)
  return vim.uv.guess_handle(1) == 'tty'
end

return M
