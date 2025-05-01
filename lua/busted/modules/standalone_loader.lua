local function getTrace(_filename, info)
  local index = info.traceback:find('\n%s*%[C]')
  info.traceback = info.traceback:sub(1, index)
  return info
end

--- @param busted busted
return function(busted, info)
  local filename = 'string'
  if info.source:sub(1, 1) == '@' or info.source:sub(1, 1) == '=' then
    filename = info.source:sub(2)
  end

  -- Setup test file to be compatible with live coding
  if info.func then
    local file = setmetatable({
      getTrace = getTrace,
      rewriteMessage = nil,
    }, {
      __call = info.func,
    })

    busted.executors.file(filename, file)
  end
end
