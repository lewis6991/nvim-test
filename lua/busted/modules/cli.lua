local utils = require('busted.utils')
local exit = require('busted.exit')

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs
local is_windows = uv.os_uname().sysname:match('Windows')

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

--- @param pathname string?
--- @return string?
local function normalize(pathname)
  if not pathname or pathname == '' then
    return pathname
  end
  return fs.normalize(pathname)
end

--- @param base string?
--- @param relative string?
--- @return string?
local function join(base, relative)
  if not base or base == '' then
    return normalize(relative)
  end
  if not relative or relative == '' then
    return normalize(base)
  end
  return normalize(fs.joinpath(base, relative))
end

--- @param pathname string?
--- @return boolean
local function isfile(pathname)
  if not pathname or pathname == '' then
    return false
  end
  local stat = uv.fs_stat(pathname)
  return stat ~= nil and stat.type == 'file'
end

--- @param command string
--- @param script string
--- @param args table
local function run_lua_interpreter(command, script, args)
  local cmd = { command, script, '--ignore-lua' }
  for _, value in ipairs(args) do
    cmd[#cmd + 1] = value
  end
  local result = vim.system(cmd):wait()
  exit(result.code)
end

--- @param values string|string[]?
--- @return string[]
local function makeList(values)
  return type(values) == 'table' and values or { values }
end

--- @param values string|string[]
--- @return string[]
local function fixupList(values)
  local list = type(values) == 'table' and values or { values }
  local ret = {}
  for _, v in ipairs(list) do
    vim.list_extend(ret, utils.split(v, ','))
  end
  return ret
end

--- @param current string?
--- @param value string?
--- @param sep string
--- @return string
local function append_value(current, value, sep)
  value = value or ''
  if not current or current == '' then
    return value
  end
  return current .. sep .. value
end

--- @param appName string
--- @param help_entries { arguments: { name: string, description: string }[], options: { display: string, description: string }[] }
--- @return string
local function format_help_entries(appName, help_entries)
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

local lpathprefix = './src/?.lua;./src/?/?.lua;./src/?/init.lua'
local cpathprefix = is_windows and './csrc/?.dll;./csrc/?/?.dll;' or './csrc/?.so;./csrc/?/?.so;'

--- @param options busted.cli.Options
--- @return table<string, any>
local function make_defaults(options)
  local defaultOutput = options.output or 'busted.outputHandlers.output_handler'
  local pattern = { '_spec' }
  local tags = {}
  local roots = { 'spec' }
  return {
    ROOT = roots,
    pattern = pattern,
    p = pattern,
    ['exclude-pattern'] = {},
    e = {},
    directory = './',
    C = './',
    lpath = lpathprefix,
    m = lpathprefix,
    cpath = cpathprefix,
    output = defaultOutput,
    o = defaultOutput,
    tags = tags,
    t = tags,
    name = {},
    filter = {},
    ['filter-out'] = {},
    ['exclude-tags'] = {},
    loaders = { 'lua' },
    helper = nil,
    lua = nil,
    run = nil,
    f = nil,
    ['config-file'] = nil,
    ['coverage-config-file'] = nil,
    ['log-success'] = nil,
    ['exclude-names-file'] = nil,
    Xoutput = {},
    Xhelper = {},
    ['repeat'] = 1,
    coverage = false,
    c = false,
    verbose = false,
    v = false,
    list = false,
    l = false,
    lazy = false,
    ['auto-insulate'] = true,
    ['keep-going'] = true,
    k = true,
    recursive = true,
    R = true,
    ['ignore-lua'] = false,
    ['suppress-pending'] = false,
    ['defer-print'] = false,
    version = false,
  }
end

--- @param options busted.cli.Options
--- @return busted.cli.State
local function new_state(options)
  return {
    args = make_defaults(options),
    overrides = {},
  }
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

--- @param state busted.cli.State
--- @param key string
--- @param value any
--- @param altkey string?
--- @return boolean, string?
local function processOption(state, key, value, altkey)
  assign(state, key, value, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @return boolean, string?
local function processArgList(state, key, value)
  value = value or ''
  local list = state.overrides[key]
  if not list then
    list = {}
  end
  vim.list_extend(list, utils.split(value, ','))
  assign(state, key, list)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @param opt string
--- @return boolean, string?
local function processNumber(state, key, value, altkey, opt)
  local number = tonumber(value)
  if not number then
    return false, 'argument to ' .. opt .. ' must be a number'
  end
  assign(state, key, number, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @return boolean, string?
local function processList(state, key, value, altkey)
  value = value or ''
  local list = state.overrides[key] or {}
  vim.list_extend(list, utils.split(value, ','))
  assign(state, key, list, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @return boolean, string?
local function processMultiOption(state, key, value, altkey)
  value = value or ''
  local list = state.overrides[key] or {}
  table.insert(list, value)
  assign(state, key, list, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @return boolean, string?
local function processLoaders(state, key, value, altkey)
  value = value or ''
  local combined = append_value(state.overrides[key], value, ',')
  assign(state, key, combined, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @return boolean, string?
local function processPath(state, key, value, altkey)
  value = value or ''
  local combined = append_value(state.overrides[key], value, ';')
  assign(state, key, combined, altkey)
  return true
end

--- @param state busted.cli.State
--- @param key string
--- @param value string?
--- @param altkey string?
--- @return boolean, string?
local function processDir(state, key, value, altkey)
  value = value or ''
  local base = state.overrides[key] or ''
  local dpath = join(base, value)
  assign(state, key, dpath, altkey)
  return true
end

--- @param state busted.cli.State
--- @param _ string
--- @param value boolean
--- @return boolean, string?
local function processSort(state, _, value)
  assign(state, 'sort-files', value)
  assign(state, 'sort-tests', value)
  return true
end

return function(options)
  local appName = ''
  options = options or {}
  local allow_roots = not options.standalone
  local configLoader = require('busted.modules.configuration_loader')()
  local help_entries = {
    arguments = {},
    options = {},
  }

  local function add_argument_help(name, description)
    table.insert(help_entries.arguments, { name = name, description = description })
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

  local option_handlers = {}

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
  local function register_option(names, spec)
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
          return processMultiOption(state, spec.key, value, spec.altkey)
        end
      else
        spec.handler = function(state, value)
          return processOption(state, spec.key, value, spec.altkey)
        end
      end
    end
    for _, name in ipairs(names) do
      option_handlers[name] = spec
    end
    help_entries.options[#help_entries.options + 1] = {
      display = spec.display,
      description = spec.description or '',
    }
  end

  --- @param positive_names string[]
  --- @param negative_names string[]
  --- @param spec busted.cli.NegatableOptionSpec
  local function register_negatable_option(positive_names, negative_names, spec)
    local key = spec.key or derive_option_key(positive_names)
    if not key or key == '' then
      error('missing key for negatable option: ' .. table.concat(positive_names, ', '))
    end
    local altkey = spec.altkey or derive_option_altkey(positive_names)
    register_option(positive_names, {
      takes_value = false,
      description = spec.description,
      key = key,
      altkey = altkey,
      handler = spec.handler or function(state)
        return processOption(state, key, true, altkey)
      end,
    })
    register_option(negative_names, {
      takes_value = false,
      description = spec.negated_description,
      key = key,
      altkey = altkey,
      handler = spec.negated_handler or function(state)
        return processOption(state, key, false, altkey)
      end,
    })
  end
  if allow_roots then
    add_argument_help(
      'ROOT',
      'Test script file or directory. Directories are traversed for files matching --pattern.'
    )
  end
  register_option({ '--version' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'version', true)
    end,
    description = 'Print the program version and exit.',
  })
  if allow_roots then
    register_option({ '-p', '--pattern' }, {
      takes_value = true,
      metavar = 'PATTERN',
      multi = true,
      description = 'Only run test files matching the Lua pattern (default: _spec).',
    })
    register_option({ '--exclude-pattern' }, {
      takes_value = true,
      metavar = 'PATTERN',
      multi = true,
      description = 'Do not run files matching the Lua pattern; takes precedence over --pattern.',
    })
  end
  register_option({ '-e' }, {
    takes_value = true,
    metavar = 'STATEMENT',
    multi = true,
    description = 'Execute Lua statement STATEMENT before running tests.',
  })
  register_option({ '-o', '--output' }, {
    takes_value = true,
    metavar = 'LIBRARY',
    description = 'Output handler module to load (default: busted.outputHandlers.output_handler).',
  })
  register_option({ '-C', '--directory' }, {
    takes_value = true,
    metavar = 'DIR',
    handler = function(state, value)
      return processDir(state, 'directory', value, 'C')
    end,
    description = 'Change to DIR before running tests; multiple directories are resolved incrementally.',
  })
  register_option({ '-f', '--config-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Load configuration options from FILE.',
  })
  register_option({ '--coverage-config-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Load LuaCov configuration options from FILE.',
  })
  register_option({ '-t', '--tags' }, {
    takes_value = true,
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'tags', value, 't')
    end,
    description = 'Only run tests with these comma-separated #tags.',
  })
  register_option({ '--exclude-tags' }, {
    takes_value = true,
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'exclude-tags', value)
    end,
    description = 'Do not run tests with these #tags; takes precedence over --tags.',
  })
  register_option({ '--filter' }, {
    takes_value = true,
    metavar = 'PATTERN',
    multi = true,
    description = 'Only run tests whose names match the Lua pattern.',
  })
  register_option({ '--name' }, {
    takes_value = true,
    metavar = 'NAME',
    multi = true,
    description = 'Run the test with the given full name.',
  })
  register_option({ '--filter-out' }, {
    takes_value = true,
    metavar = 'PATTERN',
    multi = true,
    description = 'Exclude tests whose names match the Lua pattern; takes precedence over --filter.',
  })
  register_option({ '--exclude-names-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Skip tests whose names appear in FILE; takes precedence over name filters.',
  })
  register_option({ '--log-success' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Append the name of each successful test to FILE.',
  })
  register_option({ '-m', '--lpath' }, {
    takes_value = true,
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'lpath', value, 'm')
    end,
    description = 'Prefix PATH to package.path (default: ./src/?.lua;./src/?/?.lua;./src/?/init.lua).',
  })
  register_option({ '--cpath' }, {
    takes_value = true,
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'cpath', value)
    end,
    description = 'Prefix PATH to package.cpath (default: ./csrc/?.so;./csrc/?/?.so;).',
  })
  register_option({ '-r', '--run' }, {
    takes_value = true,
    metavar = 'RUN',
    description = 'Load configuration RUN from the project .busted file.',
  })
  register_option({ '--repeat' }, {
    takes_value = true,
    metavar = 'COUNT',
    handler = function(state, value)
      return processNumber(state, 'repeat', value, nil, '--repeat')
    end,
    description = 'Run the entire test suite COUNT times (default: 1).',
  })
  register_option({ '--loaders' }, {
    takes_value = true,
    metavar = 'NAME',
    handler = function(state, value)
      return processLoaders(state, 'loaders', value)
    end,
    description = 'Comma-separated list of test file loaders (default: lua).',
  })
  register_option({ '--helper' }, {
    takes_value = true,
    metavar = 'PATH',
    description = 'Run helper script at PATH before executing tests.',
  })
  register_option({ '--lua' }, {
    takes_value = true,
    metavar = 'LUA',
    description = 'Path to the Lua interpreter busted should run under.',
  })
  register_option({ '-Xoutput' }, {
    takes_value = true,
    metavar = 'OPTION',
    handler = function(state, value)
      return processList(state, 'Xoutput', value)
    end,
    description = 'Pass OPTION (comma-separated) to the output handler.',
  })
  register_option({ '-Xhelper' }, {
    takes_value = true,
    metavar = 'OPTION',
    handler = function(state, value)
      return processList(state, 'Xhelper', value)
    end,
    description = 'Pass OPTION (comma-separated) to the helper script.',
  })
  register_negatable_option({ '-c', '--coverage' }, { '--no-coverage' }, {
    description = 'Enable code coverage analysis (requires LuaCov).',
    negated_description = 'Disable code coverage analysis.',
  })
  register_negatable_option({ '-v', '--verbose' }, { '--no-verbose' }, {
    description = 'Enable verbose output of errors.',
    negated_description = 'Disable verbose error output.',
  })
  register_option({ '-l', '--list' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'list', true, 'l')
    end,
    description = 'List the names of all tests instead of running them.',
  })
  register_option({ '--ignore-lua' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'ignore-lua', true)
    end,
    description = 'Ignore the --lua directive.',
  })
  register_negatable_option({ '--lazy' }, { '--no-lazy' }, {
    description = 'Use lazy setup/teardown as the default.',
    negated_description = 'Disable lazy setup/teardown.',
  })
  register_negatable_option({ '--auto-insulate' }, { '--no-auto-insulate' }, {
    description = 'Enable file insulation (default).',
    negated_description = 'Disable file insulation.',
  })
  register_negatable_option({ '-k', '--keep-going' }, { '--no-keep-going' }, {
    description = 'Continue after errors or failures (default).',
    negated_description = 'Stop on the first error or failure.',
  })
  register_negatable_option({ '-R', '--recursive' }, { '--no-recursive' }, {
    description = 'Recurse into subdirectories when searching for specs (default).',
    negated_description = 'Do not recurse into subdirectories.',
  })
  register_negatable_option({ '--sort-files' }, { '--no-sort-files' }, {
    description = 'Sort file execution order alphabetically.',
    negated_description = 'Run files in discovery order.',
  })
  register_negatable_option({ '--sort-tests' }, { '--no-sort-tests' }, {
    description = 'Sort test execution order within a file.',
    negated_description = 'Run tests in definition order.',
  })
  register_negatable_option({ '--suppress-pending' }, { '--no-suppress-pending' }, {
    description = 'Suppress pending test output.',
    negated_description = 'Show pending test output (default).',
  })
  register_negatable_option({ '--defer-print' }, { '--no-defer-print' }, {
    description = 'Defer printing until the suite completes.',
    negated_description = 'Print output as events occur (default).',
  })
  register_negatable_option({ '--sort' }, { '--no-sort' }, {
    description = 'Enable both --sort-files and --sort-tests.',
    negated_description = 'Disable both --sort-files and --sort-tests.',
    handler = function(state)
      return processSort(state, 'sort', true)
    end,
    negated_handler = function(state)
      return processSort(state, 'sort', false)
    end,
  })
  --- @param args table
  --- @return table<string, any>? args
  --- @return table<string, any>|string? overrides_or_err
  local function parse_cli_args(args)
    local state = new_state(options)
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
      elseif not finished and argument:sub(1, 2) == '--' then
        if argument == '--help' then
          local help = format_help_entries(appName, help_entries)
          local f = io.open('/tmp/busted_help_debug.txt', 'w')
          if f then
            f:write(help)
            f:close()
          end
          return nil, help
        end
        local name, attached = argument:match('^(%-%-[^=]+)=(.*)$')
        local key = name or argument
        local spec = option_handlers[key]
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
          local ok, err = spec.handler(state, value, spec.display)
          if not ok then
            return nil, err
          end
        else
          local ok, err = spec.handler(state)
          if not ok then
            return nil, err
          end
        end
      elseif not finished and argument:sub(1, 1) == '-' and argument ~= '-' then
        if argument == '-h' then
          local help = format_help_entries(appName, help_entries)
          local f = io.open('/tmp/busted_help_debug.txt', 'w')
          if f then
            f:write(help)
            f:close()
          end
          return nil, help
        end
        local spec = option_handlers[argument]
        if spec then
          if spec.takes_value then
            i = i + 1
            local value = args[i]
            if value == nil then
              return nil, 'Missing value for ' .. spec.display
            end
            local ok, err = spec.handler(state, value, spec.display)
            if not ok then
              return nil, err
            end
          else
            local ok, err = spec.handler(state)
            if not ok then
              return nil, err
            end
          end
        else
          local pos = 2
          while pos <= #argument do
            local short = '-' .. argument:sub(pos, pos)
            local nested = option_handlers[short]
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
              local ok, err = nested.handler(state, value, nested.display)
              if not ok then
                return nil, err
              end
              break
            else
              local ok, err = nested.handler(state)
              if not ok then
                return nil, err
              end
              pos = pos + 1
            end
          end
        end
      else
        if allow_roots then
          processArgList(state, 'ROOT', argument)
        else
          return nil, 'Unexpected positional argument ' .. argument
        end
      end
      i = i + 1
    end
    return state.args, state.overrides
  end
  --- @param args string[]
  --- @return table<string, any>? args
  --- @return string? error
  local function parse(args)
    local cliArgs, cliArgsParsedOrErr = parse_cli_args(args)
    if not cliArgs then
      return nil, appName .. ': error: ' .. cliArgsParsedOrErr .. '; re-run with --help for usage.'
    end
    local cliArgsParsed = cliArgsParsedOrErr
    --- @cast cliArgs table<string, any>
    --- @cast cliArgsParsed table<string, any>
    local bustedConfigFilePath
    if cliArgs.f then
      if not isfile(cliArgs.f) then
        return nil, ("specified config file '%s' not found"):format(cliArgs.f)
      end
      bustedConfigFilePath = cliArgs.f
    else
      bustedConfigFilePath = join(cliArgs.directory, '.busted')
      if not isfile(bustedConfigFilePath) then
        bustedConfigFilePath = nil
      end
    end
    if bustedConfigFilePath then
      local bustedConfigFile, err = loadfile(bustedConfigFilePath)
      if not bustedConfigFile then
        return nil, ('failed loading config file `%s`: %s'):format(bustedConfigFilePath, err)
      else
        local ok, config = pcall(function()
          local conf, cerr = configLoader(bustedConfigFile(), cliArgsParsed, cliArgs)
          return conf or error(cerr, 0)
        end)
        if not ok then
          return nil, appName .. ': error: ' .. config
        else
          cliArgs = config
        end
      end
    else
      cliArgs = vim.tbl_extend('force', cliArgs or {}, cliArgsParsed or {})
    end
    if cliArgs['lua'] and not cliArgs['ignore-lua'] then
      run_lua_interpreter(cliArgs['lua'], assert(args[0]), args)
    end
    cliArgs.e = makeList(cliArgs.e)
    cliArgs.pattern = makeList(cliArgs.pattern)
    cliArgs.p = cliArgs.pattern
    cliArgs['exclude-pattern'] = makeList(cliArgs['exclude-pattern'])
    cliArgs.filter = makeList(cliArgs.filter)
    cliArgs['filter-out'] = makeList(cliArgs['filter-out'])
    cliArgs.tags = fixupList(cliArgs.tags)
    cliArgs.t = cliArgs.tags
    cliArgs['exclude-tags'] = fixupList(cliArgs['exclude-tags'])
    cliArgs.loaders = fixupList(cliArgs.loaders)
    cliArgs.Xoutput = fixupList(cliArgs.Xoutput)
    cliArgs.Xhelper = fixupList(cliArgs.Xhelper)
    for _, excluded in pairs(cliArgs['exclude-tags']) do
      for _, included in pairs(cliArgs.tags) do
        if excluded == included then
          return nil, appName .. ': error: Cannot use --tags and --exclude-tags for the same tags'
        end
      end
    end
    cliArgs['repeat'] = tonumber(cliArgs['repeat'])
    return cliArgs
  end
  return {
    --- @param self table
    --- @param name string
    --- @return table
    set_name = function(self, name)
      appName = name or ''
      return self
    end,
    --- @param self table
    --- @param name string
    --- @return table
    set_silent = function(self, name)
      appName = name or ''
      return self
    end,
    --- @param _ table
    --- @param args string[]
    --- @return table<string, any>?, string?
    parse = function(_, args)
      return parse(args)
    end,
  }
end
