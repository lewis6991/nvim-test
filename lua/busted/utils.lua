local ntutils = require('nvim-test.utils')

local M = {}

function M.copy_interpreter_args(arguments)
  -- copy non-positive command-line args auto-inserted by Lua interpreter
  if arguments and _G.arg then
    local i = 0
    while _G.arg[i] do
      arguments[i] = _G.arg[i]
      i = i - 1
    end
  end
end

function M.shuffle(t, seed)
  if seed then
    math.randomseed(seed)
  end
  local n = #t
  while n >= 2 do
    local k = math.random(n)
    t[n], t[k] = t[k], t[n]
    n = n - 1
  end
  return t
end

--- return a list of all files in a directory which match a shell pattern.
--- @param dirname? string A directory.
--- @param recursive? boolean If true, the function will search recursively in subdirectories.
--- @return string[] list of files
function M.getfiles(dirname, recursive)
  dirname = dirname or '.'
  assert(ntutils.isdir(dirname), 'not a directory')

  local files = {} --- @type string[]
  for f, ty in vim.fs.dir(dirname, { depth = recursive and math.huge or nil }) do
    if ty == 'file' then
      files[#files + 1] = vim.fs.joinpath(dirname, f)
    end
  end
  return files
end

return M
