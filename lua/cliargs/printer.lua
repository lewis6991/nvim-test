local MAX_COLS = 72

---@param words string[]
---@param size integer
---@return string
---@return string[]
local function buildline(words, size)
  -- if overflow is set, a word longer than size, will overflow the size
  -- otherwise it will be chopped in line-length pieces
  local line = {} --- @type string[]
  if #words[1] > size then
    -- word longer than line
    line[1] = words[1]:sub(1, size)
    words[1] = words[1]:sub(size + 1, -1)
  else
    local len = 0
    while words[1] and (len + #words[1] + 1 <= size) or (len == 0 and #words[1] == size) do
      line[#line + 1] = words[1]
      len = len + #words[1] + 1
      table.remove(words, 1)
    end
  end
  return table.concat(line, ' '), words
end

---@param str string
---@param size integer
---@return string[]
local function wordwrap(str, size)
  -- if overflow is set, then words longer than a line will overflow
  -- otherwise, they'll be chopped in pieces
  local out = {} --- @type string[]
  local words = vim.split(str, ' ')
  while words[1] do
    out[#out + 1], words = buildline(words, size)
  end
  return out
end

--- @generic T: cliargs.Entry
--- @param t T[]
--- @param k string
--- @param v any
--- @return T[]
local function filter(t, k, v)
  --- @cast t table[]
  local out = {} --- @type table[]

  for _, item in ipairs(t) do
    if item[k] == v then
      table.insert(out, item)
    end
  end

  return out
end

--- @class cliargs.Printer
--- @field state cliargs.Command
local Printer = {}
Printer.__index = Printer

function Printer:get_max_label_length()
  local state = self.state
  local maxsz = 0
  --- @type cliargs.Entry
  local optargument = filter(state.options, 'type', 'splat')[1]
  --- @type cliargs.Entry.Command[]
  local commands = filter(state.options, 'type', 'command')

  for _, entry in ipairs(commands) do
    if #entry.__key__ > maxsz then
      maxsz = #entry.__key__
    end
  end

  for _, entry in ipairs(state.options) do
    local key = entry.label or entry.key or entry.__key__
    if #key > maxsz then
      maxsz = #key
    end
  end

  if optargument and #optargument.key > maxsz then
    maxsz = #optargument.key
  end

  return maxsz
end

-- Generate the USAGE heading message.
function Printer:generate_usage()
  local state = self.state
  local msg = 'Usage:'

  --- @type cliargs.Entry[]
  local required = filter(state.options, 'type', 'argument')
  --- @type cliargs.Entry[]
  local optional = filter(state.options, 'type', 'option')
  local optargument = filter(state.options, 'type', 'splat')[1] --[[@as cliargs.Entry]]

  if #state.name > 0 then
    msg = msg .. ' ' .. tostring(state.name)
  end

  if #optional > 0 then
    msg = msg .. ' [OPTIONS]'
  end

  if #required > 0 or optargument then
    msg = msg .. ' [--]'
  end

  if #required > 0 then
    for _, entry in ipairs(required) do
      msg = msg .. ' ' .. entry.key
    end
  end

  if optargument then
    if optargument.maxcount == 1 then
      msg = msg .. ' [' .. optargument.key .. ']'
    elseif optargument.maxcount == 2 then
      msg = msg .. ' [' .. optargument.key .. '-1 [' .. optargument.key .. '-2]]'
    elseif optargument.maxcount > 2 then
      msg = msg .. ' [' .. optargument.key .. '-1 [' .. optargument.key .. '-2 [...]]]'
    end
  end

  return msg
end

function Printer:generate_help()
  local state = self.state
  local msg = ''
  local col1 = state.colsz[1]
  local col2 = state.colsz[2]
  local required = filter(state.options, 'type', 'argument')
  local optional = filter(state.options, 'type', 'option')
  local commands = filter(state.options, 'type', 'command')
  local optargument = filter(state.options, 'type', 'splat')[1]

  --- @param label string
  --- @param desc string
  local function append(label, desc)
    label = '  ' .. label .. (' '):rep(col1 - (#label + 2))
    desc = table.concat(wordwrap(desc, col2), '\n') -- word-wrap
    desc = desc:gsub('\n', '\n' .. (' '):rep(col1)) -- add padding

    msg = ('%s%s%s\n'):format(msg, label, desc)
  end

  if col1 == 0 then
    col1 = self:get_max_label_length()
  end

  -- add margins
  col1 = col1 + 3

  if col2 == 0 then
    col2 = MAX_COLS - col1
  end

  col2 = math.max(col2, 10)

  if #commands > 0 then
    msg = msg .. '\nCOMMANDS: \n'

    for _, entry in ipairs(commands) do
      append(entry.__key__, entry.description or '')
    end
  end

  if required[1] or optargument then
    msg = msg .. '\nARGUMENTS: \n'

    for _, entry in ipairs(required) do
      append(entry.key, entry.desc .. ' (required)')
    end
  end

  if optargument then
    local optarg_desc = ' ' .. optargument.desc
    local default_value = optargument.maxcount > 1 and optargument.default[1] or optargument.default

    if #optargument.default > 0 then
      optarg_desc = optarg_desc .. ' (optional, default: ' .. tostring(default_value[1]) .. ')'
    else
      optarg_desc = optarg_desc .. ' (optional)'
    end

    append(optargument.key, optarg_desc)
  end

  if #optional > 0 then
    msg = msg .. '\nOPTIONS: \n'

    for _, entry in ipairs(optional) do
      local desc = entry.desc
      if not entry.flag and entry.default and #tostring(entry.default) > 0 then
        local readable_default = type(entry.default) == 'table' and '[]' or tostring(entry.default)
        desc = desc .. ' (default: ' .. readable_default .. ')'
      elseif entry.flag and entry.negatable then
        local readable_default = entry.default and 'on' or 'off'
        desc = desc .. ' (default: ' .. readable_default .. ')'
      end
      append(entry.label, desc)
    end
  end

  return msg
end

function Printer:generate_help_and_usage()
  return self:generate_usage() .. '\n' .. self:generate_help()
end

--- @param state cliargs.Command
--- @return cliargs.Printer
local function create_printer(state)
  return setmetatable({ state = state }, Printer)
end

return create_printer
