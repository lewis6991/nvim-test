local function split(value, sep)
  if type(value) ~= 'string' then
    return {}
  end
  return vim.split(value, sep or ',', { plain = true, trimempty = true })
end

return {
  copy_interpreter_args = function(arguments)
    -- copy non-positive command-line args auto-inserted by Lua interpreter
    if arguments and _G.arg then
      local i = 0
      while _G.arg[i] do
        arguments[i] = _G.arg[i]
        i = i - 1
      end
    end
  end,

  split = split,
}
