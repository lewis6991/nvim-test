local create_printer = require('cliargs.printer')

--- @generic T
--- @param t T[]
--- @param k string
--- @param v any
--- @return T[]
local function filter(t, k, v)
  --- @cast t table[]
  local out = {} --- @type table[]

  for _, item in ipairs(t) do
    if item[k] == v then
      out[#out + 1] = item
    end
  end

  return out
end

-- Used internally to lookup an entry using either its short or expanded keys
--- @param k? string
--- @param ek? string
--- @param ... cliargs.Entry[]
--- @return cliargs.Entry?
local function lookup(k, ek, ...)
  for _, t in ipairs({ ... }) do
    for _, entry in ipairs(t) do
      if k and entry.key == k then
        return entry
      end

      if ek then
        if entry.expanded_key == ek then
          return entry
        end

        if entry.negatable and ('no-' .. entry.expanded_key) == ek then
          return entry
        end
      end
    end
  end
end

--- @param str string
--- @return string? symbol
--- @return string? key
--- @return string|boolean? value
--- @return boolean negated
local function disect_argument(str)
  local value --- @type string?
  local negated = false

  --- @type integer?, integer?, string?, string?
  local _, _, symbol, key = str:find('^([%-]*)(.*)')

  if key then
    local actual_key

    -- split value and key
    --- @type integer?, integer?, string?, string?
    _, _, actual_key, value = key:find('([^%=]+)[%=]?(.*)')

    if value then
      --- @cast actual_key -?
      key = actual_key
    end

    if key:sub(1, 3) == 'no-' then
      key = key:sub(4, -1)
      negated = true
    end
  end

  -- no leading symbol means the sole fragment is the value.
  if #symbol == 0 then
    value = str
    key = nil
  end

  return #symbol > 0 and symbol or nil,
    key and #key > 0 and key or nil,
    value and #value > 0 and value or nil,
    negated and true or false
end

--- @param args string[]
--- @param options cliargs.Entry[]
--- @return {entry:cliargs.Entry, value:string}[]? values
--- @return integer? arg_count
--- @return string? err
local function process_arguments(args, options)
  local values = {} --- @type [cliargs.Entry, string|boolean][]
  local cursor = 0
  local argument_cursor = 1
  local argument_delimiter_found = false

  local function consume()
    cursor = cursor + 1
    return args[cursor]
  end

  local required = filter(options, 'type', 'argument')

  while cursor < #args do
    local curr_opt = consume()
    local symbol, key, value, flag_negated = disect_argument(curr_opt)

    if curr_opt == '--' then -- end-of-options indicator:
      argument_delimiter_found = true
    elseif not argument_delimiter_found and symbol then -- an option:
      local entry = lookup(key, key, options)

      if not key or not entry then
        local option_type = value and 'option' or 'flag'
        return nil, nil, 'unknown/bad ' .. option_type .. ': ' .. curr_opt
      end

      if flag_negated and not entry.negatable then
        return nil, nil, "flag '" .. curr_opt .. "' may not be negated using --no-"
      end

      -- a flag and a value specified? that's an error
      if entry.flag and value then
        return nil, nil, 'flag ' .. curr_opt .. ' does not take a value'
      end

      if entry.flag then
        value = not flag_negated
      elseif not value then -- an option:
        --- @cast entry cliargs.Entry.Option
        -- the value might be in the next argument, e.g:
        --
        --     --compress lzma

        -- if the option contained a = and there's no value, it means they
        -- want to nullify an option's default value. eg:
        --
        --    --compress=
        if curr_opt:find('=') then
          value = '__CLIARGS_NULL__'
        else
          -- NOTE: this has the potential to be buggy and swallow the next
          -- entry as this entry's value even though that entry may be an
          -- actual argument/option
          --
          -- this would be a user error and there is no determinate way to
          -- figure it out because if there's no leading symbol (- or --)
          -- in that entry it can be an actual argument. :shrug:
          value = consume()

          if not value then
            return nil, nil, 'option ' .. curr_opt .. ' requires a value to be set'
          end
        end
      end

      values[#values + 1] = { entry = entry, value = value }

      local ecallback = entry.callback
      if ecallback then
        local altkey = entry.key

        if key == entry.key then
          altkey = entry.expanded_key
        else
          key = entry.expanded_key
        end

        local status, err = ecallback(key, value, altkey, curr_opt)

        if status == nil and err then
          return nil, nil, err
        end
      end
    elseif argument_cursor <= #required then -- a regular argument:
      local entry = required[argument_cursor]
      values[#values + 1] = { entry = entry, value = curr_opt }

      local ecallback = entry.callback
      if ecallback then
        local status, err = ecallback(entry.key, curr_opt)

        if status == nil and err then
          return nil, nil, err
        end
      end

      argument_cursor = argument_cursor + 1
    else -- a splat argument:
      local entry = filter(options, 'type', 'splat')[1]

      if entry then
        table.insert(values, { entry = entry, value = curr_opt })

        local ecallback = entry.callback
        if ecallback then
          local status, err = ecallback(entry.key, curr_opt)

          if status == nil and err then
            return nil, nil, err
          end
        end
      end

      argument_cursor = argument_cursor + 1
    end
  end

  return values, argument_cursor - 1
end

--- @param options cliargs.Entry[]
--- @param arg_count integer
--- @return string? err
local function validate(options, arg_count)
  local required = filter(options, 'type', 'argument')
  local splatarg = filter(options, 'type', 'splat')[1] or { maxcount = 0 }

  local min_arg_count = #required
  local max_arg_count = #required + splatarg.maxcount

  -- missing any required arguments, or too many?
  if arg_count < min_arg_count or arg_count > max_arg_count then
    if splatarg.maxcount > 0 then
      return ('bad number of arguments: %d-%d argument(s) must be specified, not %d'):format(
        min_arg_count,
        max_arg_count,
        arg_count
      )
    else
      return ('bad number of arguments: %d argument(s) must be specified, not %d'):format(
        min_arg_count,
        arg_count
      )
    end
  end
end

--- @param cli_values {entry:cliargs.Entry, value:string}[]
--- @param entry cliargs.Entry
--- @return string[]
local function collect_with_default(cli_values, entry)
  local entry_values = {} --- @type string[]

  for _, item in ipairs(cli_values) do
    if item.entry == entry then
      entry_values[#entry_values + 1] = item.value
    end
  end

  if #entry_values == 0 then
    local edefault = entry.default
    if type(edefault) == 'table' then
      return edefault
    else
      return { edefault }
    end
  else
    return entry_values
  end
end

--- @param cli_values {entry:cliargs.Entry, value:string}[]
--- @param options cliargs.Entry[]
--- @return table<string, string|string[]>
local function collect_results(cli_values, options)
  local results = {} --- @type table<string, string|string[]>

  for _, entry in pairs(options) do
    local entry_cli_values = collect_with_default(cli_values, entry)
    local maxcount = entry.maxcount

    if maxcount == nil then
      maxcount = type(entry.default) == 'table' and 999 or 1
    end

    local entry_value --- @type string|string[]?

    if maxcount == 1 and type(entry_cli_values) == 'table' then
      -- take the last value
      entry_value = entry_cli_values[#entry_cli_values]

      if entry_value == '__CLIARGS_NULL__' then
        entry_value = nil
      end
    else
      entry_value = entry_cli_values
    end

    if entry.key then
      results[entry.key] = entry_value
    end
    local ekey = entry.expanded_key
    if ekey then
      results[ekey] = entry_value
    end
  end

  return results
end

--- @param fn any
--- @return boolean
local function is_callable(fn)
  return type(fn) == 'function' or (getmetatable(fn) or {}).__call
end

--- @param v any
--- @return boolean?
local function cast_to_boolean(v)
  if v == nil then
    return v
  end
  return v and true or false
end

local RE_ADD_COMMA = '^%-([%a%d]+)[%s]%-%-'
local RE_ADJUST_DELIMITER = '(%-%-?)([%a%d]+)[%s]'

-- parameterize the key if needed, possible variations:
--
--     -key
--     -key VALUE
--     -key=VALUE
--
--     -key, --expanded
--     -key, --expanded VALUE
--     -key, --expanded=VALUE
--
--     -key --expanded
--     -key --expanded VALUE
--     -key --expanded=VALUE
--
--     --expanded
--     --expanded VALUE
--     --expanded=VALUE
--- @param key string
--- @return string, string, string
local function disect(key)
  do
    -- if there is no comma, between short and extended, add one
    local _, _, dummy = key:find(RE_ADD_COMMA)
    if dummy then
      key = key:gsub(RE_ADD_COMMA, '-' .. dummy .. ', --', 1)
    end
  end

  -- replace space delimiting the value indicator by "="
  --
  --     -key VALUE => -key=VALUE
  --     --expanded-key VALUE => --expanded-key=VALUE
  local _, _, prefix, dummy = key:find(RE_ADJUST_DELIMITER)
  if prefix and dummy then
    key = key:gsub(RE_ADJUST_DELIMITER, prefix .. dummy .. '=', 1)
  end

  -- if there is no "=", then append one
  if not key:find('=') then
    key = key .. '='
  end

  -- get value
  local _, _, v = key:find('.-%=(.+)')

  -- get key(s), remove spaces
  key = vim.split(key, '=')[1]:gsub(' ', '')

  -- get short key & extended key
  local _, _, k = key:find('^%-([^-][^%s,]*)')
  local _, _, ek = key:find('%-%-(.+)$')

  if v == '' then
    v = nil
  end

  return k, ek, v
end

--- @alias cliargs.Entry
--- | cliargs.Entry.Option
--- | cliargs.Entry.Argument
--- | cliargs.Entry.Splat

--- @class cliargs.Entry.Base
--- @field key string
--- @field desc string
--- @field callback? fun(key: string, value: string|boolean, altkey?: string, curr_opt?: string): boolean?, string?

--- @class cliargs.Entry.Splat: cliargs.Entry.Base
--- @field type 'splat'
--- @field default? string|table
--- @field maxcount integer

--- @class cliargs.Entry.Argument:cliargs.Entry.Base
--- @field type 'argument'

--- @class cliargs.Entry.Option:cliargs.Entry.Base
--- @field type 'option'
--- @field expanded_key string
--- @field negatable? boolean
--- @field label? string
--- @field flag? boolean
--- @field default? string|table

--- @class cliargs.Command
--- @field name string
--- @field description string
--- @field colsz [integer, integer] column width, help text. Set to 0 for auto detect
--- @field printer cliargs.Printer
--- @field options cliargs.Entry[]
local CLI = {}
CLI.__index = CLI

--- @return cliargs.Command
local function create_core()
  --- The primary export you receive when you require the library. For example:
  ---
  ---     local cli = require 'cliargs'

  local self = setmetatable({
    name = '',
    description = '',
    options = {},
    colsz = { 0, 0 },
  }, CLI)

  self.printer = create_printer(self)

  return self
end

--- Assigns the name of the program which will be used for logging.
--- @param in_name string
--- @return cliargs.Command
function CLI:set_name(in_name)
  self.name = in_name
  return self
end

--- Write down a brief, 1-liner description of what the program does.
--- @param description string
--- @return cliargs.Command
function CLI:set_description(description)
  self.description = description
  return self
end

--- Sets the amount of space allocated to the argument keys and descriptions
--- in the help listing.
---
--- The sizes are used for wrapping long argument keys and descriptions.
---
--- @param key_cols integer
---        The number of columns assigned to the argument keys, set to 0 to
---        auto detect.
---
--- @param desc_cols integer
---        The number of columns assigned to the argument descriptions, set to
---        0 to auto set the total width to 72.
function CLI:set_colsz(key_cols, desc_cols)
  self.colsz = { key_cols or self.colsz[1], desc_cols or self.colsz[2] }
end

--- @param key string
--- @param new_default any
--- @return true?
function CLI:redefine_default(key, new_default)
  local entry = lookup(key, key, self.options)

  if not entry then
    return nil
  end

  if entry.flag then
    new_default = cast_to_boolean(new_default)
  end

  entry.default = vim.deepcopy(new_default)

  return true
end

--- Load default values from a table.
---
--- @param config table<string,any>
---        Your new set of defaults. The keys could either point to the short
---        or expanded option keys, and their values are the new defaults.
---
--- @param strict? boolean
---        Turn this on to return nil and an error message if a key in the
---        config table could not be mapped to any CLI option.
---
--- @return true?
---         When the new defaults were loaded successfully, or strict was not
---         set.
---
--- @return string?
---         When strict was set and there was an error.
function CLI:load_defaults(config, strict)
  for k, v in pairs(config) do
    local success = self:redefine_default(k, v)

    if strict and not success then
      return nil, "Unrecognized option with the key '" .. k .. "'"
    end
  end

  return true
end

--- Define a required argument.
---
---
--- Required arguments do not take a symbol like `-` or `--`, may not have a
--- default value, and are parsed in the order they are defined.
---
---
--- For example:
---
--- ```lua
--- cli:argument('INPUT', 'path to the input file')
--- cli:argument('OUTPUT', 'path to the output file')
--- ```
---
--- At run-time, the arguments have to be specified using the following
--- notation:
---
--- ```bash
--- $ ./script.lua ./main.c ./a.out
--- ```
---
--- If the user does not pass a value to _every_ argument, the parser will
--- raise an error.
---
--- @param key string
---        The argument identifier that will be displayed to the user and
---        be used to reference the run-time value.
---
--- @param desc string A description for this argument to display in usage help.
--- @param callback? fun() Callback to invoke when this argument is parsed.
--- @return cliargs.Command
function CLI:argument(key, desc, callback)
  assert(
    type(key) == 'string' and type(desc) == 'string',
    'Key and description are mandatory arguments (Strings)'
  )

  assert(callback == nil or is_callable(callback), 'Callback argument must be a function')

  if lookup(key, key, self.options) then
    error('Duplicate argument: ' .. key .. ', please rename one of them.')
  end

  self.options[#self.options + 1] = {
    type = 'argument',
    key = key,
    desc = desc,
    callback = callback,
  }

  return self
end

--- Defines a "splat" (or catch-all) argument.
---
--- This is a special kind of argument that may be specified 0 or more times,
--- the values being appended to a list.
---
--- For example, let's assume our program takes a single output file and works
--- on multiple source files:
---
--- ```lua
--- cli:argument('OUTPUT', 'path to the output file')
--- cli:splat('INPUTS', 'the sources to compile', nil, 10) -- up to 10 source files
--- ```
---
--- At run-time, it could be invoked as such:
---
--- ```bash
--- $ ./script.lua ./a.out file1.c file2.c main.c
--- ```
---
--- If you want to make the output optional, you could do something like this:
---
--- ```lua
--- cli:option('-o, --output=FILE', 'path to the output file', './a.out')
--- cli:splat('INPUTS', 'the sources to compile', nil, 10)
--- ```
---
--- And now we may omit the output file path:
---
--- ```bash
--- $ ./script.lua file1.c file2.c main.c
--- ```
---
--- @param key string The argument's "name" that will be displayed to the user.
--- @param desc string A description of the argument.
--- @param default? any A default value.
--- @param maxcount? integer The maximum number of occurrences allowed.
--- @param callback? fun() A function to call **everytime** a value for this argument is parsed.
--- @return cliargs.Command
function CLI:splat(key, desc, default, maxcount, callback)
  assert(#filter(self.options, 'type', 'splat') == 0, 'Only one splat argument may be defined.')

  assert(
    type(key) == 'string' and type(desc) == 'string',
    'Key and description are mandatory arguments (Strings)'
  )

  assert(
    type(default) == 'string' or default == nil,
    'Default value must either be omitted or be a string'
  )

  maxcount = tonumber(maxcount or 1) --[[@as integer]]

  assert(maxcount > 0 and maxcount < 1000, 'Maxcount must be a number from 1 to 999')
  assert(is_callable(callback) or callback == nil, 'Callback argument: expected a function or nil')

  local typed_default = default or {}

  if type(typed_default) ~= 'table' then
    typed_default = { typed_default }
  end

  self.options[#self.options + 1] = {
    type = 'splat',
    key = key,
    desc = desc,
    default = typed_default,
    maxcount = maxcount,
    callback = callback,
  }

  return self
end

-- Used internally to add an option
--- @private
--- @param k string
--- @param ek string
--- @param v? string
--- @param label string
--- @param desc string
--- @param default any
--- @param callback? fun()
function CLI:_define_option(k, ek, v, label, desc, default, callback)
  local flag = (v == nil) -- no value, so it's a flag
  local negatable = flag and (ek and ek:find('^%[no%-]') ~= nil)

  if negatable then
    --- @type string
    ek = ek:sub(6)
  end

  -- guard against duplicates
  if lookup(k, ek, self.options) then
    error('Duplicate option: ' .. (k or ek) .. ', please rename one of them.')
  end

  if negatable and lookup(nil, 'no-' .. ek, self.options) then
    error('Duplicate option: ' .. ('no-' .. ek) .. ', please rename one of them.')
  end

  self.options[#self.options + 1] = {
    type = 'option',
    key = k,
    expanded_key = ek,
    desc = desc,
    default = default,
    label = label,
    flag = flag,
    negatable = negatable,
    callback = callback,
  }
end

--- Defines an optional argument.
---
--- Optional arguments can use 3 different notations, and can accept a value.
---
--- @param key string
---        The argument identifier. This can either be `-key`, or
---        `-key, --expanded-key`.
---        Values can be specified either by appending a space after the
---        identifier (e.g. `-key value` or `--expanded-key value`) or by
---        separating them with a `=` (e.g. `-key=value` or
---        `--expanded-key=value`).
---
--- @param desc string A description for the argument to be shown in --help.
---
--- @param default? any
---
---         A default value to use in case the option was not specified at
---         run-time (the default value is nil if you leave this blank.)
---
--- @param callback? fun() A callback to invoke when this option is parsed.
---
--- @example
---
--- The following option will be stored in `args["i"]` and `args["input"]`
--- with a default value of `file.txt`:
---
---     cli:option("-i, --input=FILE", "path to the input file", "file.txt")
--- @return cliargs.Command
function CLI:option(key, desc, default, callback)
  assert(
    type(key) == 'string' and type(desc) == 'string',
    'Key and description are mandatory arguments (Strings)'
  )

  assert(is_callable(callback) or callback == nil, 'Callback argument: expected a function or nil')

  local k, ek, v = disect(key)

  -- if there's no VALUE indicator anywhere, what they want really is a flag.
  -- e.g:
  --
  --     cli:option('-q, --quiet', '...')
  if v == nil then
    return self:flag(key, desc, default, callback)
  end

  self:_define_option(k, ek, v, key, desc, default, callback)

  return self
end

--- Define an optional "flag" argument.
---
--- Flags are a special subset of options that can either be `true` or `false`.
---
--- For example:
--- ```lua
--- cli:flag('-q, --quiet', 'Suppress output.', true)
--- ```
---
--- At run-time:
---
--- ```bash
--- $ ./script.lua --quiet
--- $ ./script.lua -q
--- ```
---
--- Passing a value to a flag raises an error:
---
--- ```bash
--- $ ./script.lua --quiet=foo
--- $ echo $? # => 1
--- ```
---
--- Flags may be _negatable_ by prepending `[no-]` to their key:
---
--- ```lua
--- cli:flag('-c, --[no-]compress', 'whether to compress or not', true)
--- ```
---
--- Now the user gets to pass `--no-compress` if they want to skip
--- compression, or either specify `--compress` explicitly or leave it
--- unspecified to use compression.
---
--- @param key string
--- @param desc string
--- @param default any
--- @param callback? fun() A callback to invoke when this option is parsed.
--- @return cliargs.Command
function CLI:flag(key, desc, default, callback)
  if type(default) == 'function' then
    callback = default
    default = nil
  end

  assert(
    type(key) == 'string' and type(desc) == 'string',
    'Key and description are mandatory arguments (Strings)'
  )

  local k, ek, v = disect(key)

  if v ~= nil then
    error('A flag type option cannot have a value set: ' .. key)
  end

  self:_define_option(k, ek, nil, key, desc, cast_to_boolean(default), callback)

  return self
end

--- Parse the process arguments table.
---
--- @param arguments? string[] (default _G.arg)
--- The list of arguments to parse. Defaults to the global `arg` table
--- which contains the arguments the process was started with.
---
--- @return table<string, string|string[]>?
--- A table containing all the arguments, options, flags,
--- and splat arguments that were specified or had a default
--- (where applicable).
---
--- @return string? err
--- If a parsing error has occured, note that the --help option is
--- also considered an error.
function CLI:parse(arguments)
  assert(
    arguments == nil or type(arguments) == 'table',
    'expected an argument table to be passed in, got something of type ' .. type(arguments)
  )

  --- @type string[]
  local args = arguments or _G.arg or {}

  -- has --help or -h ? display the help listing and abort!
  for _, v in ipairs(args) do
    if v == '--help' or v == '-h' then
      return nil, self.printer:generate_help_and_usage()
    end
  end

  local values, arg_count, err = process_arguments(args, self.options)
  if not values or not arg_count then
    return nil, err
  end

  local err2 = validate(self.options, arg_count)
  if err2 then
    return nil, err2
  end

  return collect_results(values, self.options)
end

return create_core
