local ret = {}

local getTrace = function(_filename, info)
  local index = info.traceback:find('\n%s*%[C]')
  info.traceback = info.traceback:sub(1, index)
  return info
end

ret.match = function(_busted, filename)
  return filename:match('.lua$')
end

ret.load = function(busted, filename)
  local file, err = loadfile(filename)
  if not file then
    busted.publish({ 'error', 'file' }, { descriptor = 'file', name = filename }, nil, err, {})
  end
  return file, getTrace
end

return ret
