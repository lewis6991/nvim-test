local M = {}

--- @class busted.cli.Options
--- @field standalone? boolean
--- @field output? string

--- @class busted.cli.State
--- @field args table<string, any>
--- @field overrides table<string, any>

--- @alias busted.cli.Handler fun(state: busted.cli.State, value?: string, opt?: string): boolean, string?

--- @class busted.cli.OptionSpec
--- @field takes_value boolean
--- @field handler? busted.cli.Handler
--- @field description? string
--- @field metavar? string
--- @field multi? boolean
--- @field key? string
--- @field altkey? string
--- @field display? string

--- @class busted.cli.NegatableOptionSpec
--- @field description string
--- @field negated_description string
--- @field key? string
--- @field altkey? string
--- @field handler? busted.cli.Handler
--- @field negated_handler? busted.cli.Handler

--- @class busted.cli.framework.Parser
--- @field private option_handlers table<string, busted.cli.OptionSpec>
--- @field private help_entries { arguments: { name: string, description: string }[], options: { display: string, description: string }[] }
--- @field private state_factory fun(): busted.cli.State
--- @field private positional_handler fun(state: busted.cli.State, argument: string): boolean, string?
--- @field private app_name string
local Parser = {}
Parser.__index = Parser

--- @class busted.cli.framework.Config
--- @field state_factory fun(): busted.cli.State
--- @field positional_handler fun(state: busted.cli.State, argument: string): boolean, string?
--- @field app_name? string

--- @param config busted.cli.framework.Config
--- @return busted.cli.framework.Parser
function M.new_parser(config)
  assert(type(config.state_factory) == 'function', 'state_factory must be provided')
  --- @type busted.cli.framework.Parser
  local parser = setmetatable({
    option_handlers = {},
    help_entries = {
      arguments = {},
      options = {},
    },
    state_factory = config.state_factory,
    positional_handler = config.positional_handler or function(_, argument)
      return false, 'Unexpected positional argument ' .. tostring(argument)
    end,
    app_name = config.app_name or '',
  }, Parser)
  return parser
end

--- @param name string
--- @param description string
function Parser:add_argument_help(name, description)
  table.insert(self.help_entries.arguments, { name = name, description = description })
end

--- @param names string[]
--- @return string?
local function derive_option_key(names)
  for _, name in ipairs(names) do
    if name:sub(1, 2) == '--' then
      return name:sub(3)
    end
  end
  local first = names[1]
  if first then
    local cleaned = first:gsub('^-+', '')
    return cleaned
  end
  return nil
end

--- @param names string[]
--- @return string?
local function derive_option_altkey(names)
  for _, name in ipairs(names) do
    if name:sub(1, 1) == '-' and name:sub(2, 2) ~= '-' and #name == 2 then
      return name:sub(2)
    end
  end
  return nil
end

--- @param names string[]
--- @param spec busted.cli.OptionSpec
--- @return string
local function format_option_display(names, spec)
  if not spec.takes_value then
    return table.concat(names, ', ')
  end
  local metavar = spec.metavar or 'VALUE'
  local formatted = {}
  for _, name in ipairs(names) do
    if name:sub(1, 2) == '--' then
      formatted[#formatted + 1] = name .. '=' .. metavar
    else
      formatted[#formatted + 1] = name .. ' ' .. metavar
    end
  end
  return table.concat(formatted, ', ')
end

--- @param state busted.cli.State
--- @param key string
--- @param value any
--- @param altkey string?
local function assign(state, key, value, altkey)
  state.args[key] = value
  state.overrides[key] = value
  if altkey then
    state.args[altkey] = value
    state.overrides[altkey] = value
  end
end

--- @param names string[]
--- @param spec busted.cli.OptionSpec
function Parser:add_argument(names, spec)
  spec.display = spec.display or format_option_display(names, spec)
  spec.key = spec.key or derive_option_key(names)
  spec.altkey = spec.altkey or derive_option_altkey(names)
  if not spec.handler then
    if not spec.takes_value then
      error('missing handler for option without value: ' .. table.concat(names, ', '))
    end
    if not spec.key or spec.key == '' then
      error('missing key for option: ' .. table.concat(names, ', '))
    end
    if spec.multi then
      spec.handler = function(state, value)
        value = value or ''
        local list = state.overrides[spec.key]
        if not list then
          list = {}
        end
        table.insert(list, value)
        assign(state, spec.key, list, spec.altkey)
        return true
      end
    else
      spec.handler = function(state, value)
        assign(state, spec.key, value, spec.altkey)
        return true
      end
    end
  end
  for _, name in ipairs(names) do
    self.option_handlers[name] = spec
  end
  self.help_entries.options[#self.help_entries.options + 1] = {
    display = spec.display,
    description = spec.description or '',
  }
end

--- @param positive_names string[]
--- @param negative_names string[]
--- @param spec busted.cli.NegatableOptionSpec
function Parser:add_negatable_argument(positive_names, negative_names, spec)
  local key = spec.key or derive_option_key(positive_names)
  if not key or key == '' then
    error('missing key for negatable option: ' .. table.concat(positive_names, ', '))
  end
  local altkey = spec.altkey or derive_option_altkey(positive_names)
  self:add_argument(positive_names, {
    takes_value = false,
    description = spec.description,
    key = key,
    altkey = altkey,
    handler = spec.handler or function(state)
      assign(state, key, true, altkey)
      return true
    end,
  })
  self:add_argument(negative_names, {
    takes_value = false,
    description = spec.negated_description,
    key = key,
    altkey = altkey,
    handler = spec.negated_handler or function(state)
      assign(state, key, false, altkey)
      return true
    end,
  })
end

--- @private
--- @return string
function Parser:_format_help()
  local appName = self.app_name
  local help_entries = self.help_entries
  --- @type string[]
  local lines = {
    ('Usage: %s [OPTIONS] [--] [ROOT-1 [ROOT-2 [...]]]'):format(appName),
    '',
  }
  if #help_entries.arguments > 0 then
    table.insert(lines, 'ARGUMENTS:')
    for _, entry in ipairs(help_entries.arguments) do
      local desc_lines = vim.split(entry.description, '\n', { plain = true })
      table.insert(lines, ('  %-26s %s'):format(entry.name, desc_lines[1]))
      for i = 2, #desc_lines do
        table.insert(lines, ('  %-26s %s'):format('', desc_lines[i]))
      end
    end
    table.insert(lines, '')
  end
  if #help_entries.options > 0 then
    table.insert(lines, 'OPTIONS:')
    for _, entry in ipairs(help_entries.options) do
      local desc_lines = vim.split(entry.description, '\n', { plain = true })
      table.insert(lines, ('  %-26s %s'):format(entry.display, desc_lines[1]))
      for i = 2, #desc_lines do
        table.insert(lines, ('  %-26s %s'):format('', desc_lines[i]))
      end
    end
  end
  return table.concat(lines, '\n')
end

--- @param args string[]
--- @return table<string, any>?, table<string, any>|string?
function Parser:parse(args)
  local state = self.state_factory()
  local i = 1
  local finished = false
  while i <= #args do
    local argument = args[i]
    if type(argument) ~= 'string' then
      return nil, 'Invalid argument at position ' .. tostring(i)
    end
    --- @cast argument string
    if not finished and argument == '--' then
      finished = true
    elseif not finished and argument == '--help' then
      return nil, self:_format_help()
    elseif not finished and argument:sub(1, 2) == '--' then
      local name, attached = argument:match('^(%-%-[^=]+)=(.*)$')
      local key = name or argument
      local spec = self.option_handlers[key]
      if not spec then
        return nil, 'Unknown option ' .. key
      end
      if spec.takes_value then
        local value = attached
        if not value or value == '' then
          i = i + 1
          value = args[i]
          if value == nil then
            return nil, 'Missing value for ' .. spec.display
          end
        end
        local handler = spec.handler
        if not handler then
          return nil, 'Missing handler for ' .. (spec.display or key)
        end
        local ok, err = handler(state, value, spec.display)
        if not ok then
          return nil, err
        end
      else
        local handler = spec.handler
        if not handler then
          return nil, 'Missing handler for ' .. (spec.display or key)
        end
        local ok, err = handler(state)
        if not ok then
          return nil, err
        end
      end
    elseif not finished and argument:sub(1, 1) == '-' and argument ~= '-' then
      if argument == '-h' then
        return nil, self:_format_help()
      end
      local spec = self.option_handlers[argument]
      if spec then
        if spec.takes_value then
          i = i + 1
          local value = args[i]
          if value == nil then
            return nil, 'Missing value for ' .. spec.display
          end
          local handler = spec.handler
          if not handler then
            return nil, 'Missing handler for ' .. (spec.display or argument)
          end
          local ok, err = handler(state, value, spec.display)
          if not ok then
            return nil, err
          end
        else
          local handler = spec.handler
          if not handler then
            return nil, 'Missing handler for ' .. (spec.display or argument)
          end
          local ok, err = handler(state)
          if not ok then
            return nil, err
          end
        end
      else
        local pos = 2
        while pos <= #argument do
          local short = '-' .. argument:sub(pos, pos)
          local nested = self.option_handlers[short]
          if not nested then
            return nil, 'Unknown option ' .. short
          end
          if nested.takes_value then
            local remainder = argument:sub(pos + 1)
            local value
            if remainder ~= '' then
              value = remainder
            else
              i = i + 1
              value = args[i]
            end
            if value == nil then
              return nil, 'Missing value for ' .. nested.display
            end
            local handler = nested.handler
            if not handler then
              return nil, 'Missing handler for ' .. (nested.display or short)
            end
            local ok, err = handler(state, value, nested.display)
            if not ok then
              return nil, err
            end
            break
          else
            local handler = nested.handler
            if not handler then
              return nil, 'Missing handler for ' .. (nested.display or short)
            end
            local ok, err = handler(state)
            if not ok then
              return nil, err
            end
            pos = pos + 1
          end
        end
      end
    else
      local ok, err = self.positional_handler(state, argument)
      if not ok then
        return nil, err
      end
    end
    i = i + 1
  end
  return state.args, state.overrides
end

--- @param name string
--- @return busted.cli.framework.Parser
function Parser:set_name(name)
  self.app_name = name or ''
  return self
end

return M
