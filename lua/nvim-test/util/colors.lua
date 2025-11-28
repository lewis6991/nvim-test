local ESC = string.char(27)
local RESET = ESC .. '[0m'

local function wrap(code)
  local prefix = ESC .. '[' .. code .. 'm'
  return function(text)
    text = tostring(text or '')
    if text == '' then
      return ''
    end
    return prefix .. text .. RESET
  end
end

return {
  reset = RESET,
  black = wrap('30'),
  red = wrap('31'),
  green = wrap('32'),
  yellow = wrap('33'),
  blue = wrap('34'),
  magenta = wrap('35'),
  cyan = wrap('36'),
  white = wrap('37'),
  bright = wrap('1'),
  dim = wrap('2'),
}
