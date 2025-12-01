local utils = require('busted.utils')
local exit = require('busted.exit')
local argparse = require('argparse')

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs
local is_windows = uv.os_uname().sysname:match('Windows')

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

--- @param options? busted.cli.Options
return function(options)
  local appName = ''
  options = options or {}
  local allow_roots = not options.standalone
  local configLoader = require('busted.modules.configuration_loader')()
  local parser = argparse.new_parser({
    state_factory = function()
      return new_state(options)
    end,
    positional_handler = function(state, argument)
      if allow_roots then
        return processArgList(state, 'ROOT', argument)
      end
      return false, 'Unexpected positional argument ' .. argument
    end,
    app_name = appName,
  })

  if allow_roots then
    parser:add_argument_help(
      'ROOT',
      'Test script file or directory. Directories are traversed for files matching --pattern.'
    )
  end

  parser:add_argument({ '--version' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'version', true)
    end,
    description = 'Print the program version and exit.',
  })
  if allow_roots then
    parser:add_argument({ '-p', '--pattern' }, {
      takes_value = true,
      metavar = 'PATTERN',
      multi = true,
      description = 'Only run test files matching the Lua pattern (default: _spec).',
    })
    parser:add_argument({ '--exclude-pattern' }, {
      takes_value = true,
      metavar = 'PATTERN',
      multi = true,
      description = 'Do not run files matching the Lua pattern; takes precedence over --pattern.',
    })
  end
  parser:add_argument({ '-e' }, {
    takes_value = true,
    metavar = 'STATEMENT',
    multi = true,
    description = 'Execute Lua statement STATEMENT before running tests.',
  })
  parser:add_argument({ '-o', '--output' }, {
    takes_value = true,
    metavar = 'LIBRARY',
    description = 'Output handler module to load (default: busted.outputHandlers.output_handler).',
  })
  parser:add_argument({ '-C', '--directory' }, {
    takes_value = true,
    metavar = 'DIR',
    handler = function(state, value)
      return processDir(state, 'directory', value, 'C')
    end,
    description = 'Change to DIR before running tests; multiple directories are resolved incrementally.',
  })
  parser:add_argument({ '-f', '--config-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Load configuration options from FILE.',
  })
  parser:add_argument({ '--coverage-config-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Load LuaCov configuration options from FILE.',
  })
  parser:add_argument({ '-t', '--tags' }, {
    takes_value = true,
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'tags', value, 't')
    end,
    description = 'Only run tests with these comma-separated #tags.',
  })
  parser:add_argument({ '--exclude-tags' }, {
    takes_value = true,
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'exclude-tags', value)
    end,
    description = 'Do not run tests with these #tags; takes precedence over --tags.',
  })
  parser:add_argument({ '--filter' }, {
    takes_value = true,
    metavar = 'PATTERN',
    multi = true,
    description = 'Only run tests whose names match the Lua pattern.',
  })
  parser:add_argument({ '--name' }, {
    takes_value = true,
    metavar = 'NAME',
    multi = true,
    description = 'Run the test with the given full name.',
  })
  parser:add_argument({ '--filter-out' }, {
    takes_value = true,
    metavar = 'PATTERN',
    multi = true,
    description = 'Exclude tests whose names match the Lua pattern; takes precedence over --filter.',
  })
  parser:add_argument({ '--exclude-names-file' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Skip tests whose names appear in FILE; takes precedence over name filters.',
  })
  parser:add_argument({ '--log-success' }, {
    takes_value = true,
    metavar = 'FILE',
    description = 'Append the name of each successful test to FILE.',
  })
  parser:add_argument({ '-m', '--lpath' }, {
    takes_value = true,
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'lpath', value, 'm')
    end,
    description = 'Prefix PATH to package.path (default: ./src/?.lua;./src/?/?.lua;./src/?/init.lua).',
  })
  parser:add_argument({ '--cpath' }, {
    takes_value = true,
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'cpath', value)
    end,
    description = 'Prefix PATH to package.cpath (default: ./csrc/?.so;./csrc/?/?.so;).',
  })
  parser:add_argument({ '-r', '--run' }, {
    takes_value = true,
    metavar = 'RUN',
    description = 'Load configuration RUN from the project .busted file.',
  })
  parser:add_argument({ '--repeat' }, {
    takes_value = true,
    metavar = 'COUNT',
    handler = function(state, value)
      return processNumber(state, 'repeat', value, nil, '--repeat')
    end,
    description = 'Run the entire test suite COUNT times (default: 1).',
  })
  parser:add_argument({ '--loaders' }, {
    takes_value = true,
    metavar = 'NAME',
    handler = function(state, value)
      return processLoaders(state, 'loaders', value)
    end,
    description = 'Comma-separated list of test file loaders (default: lua).',
  })
  parser:add_argument({ '--helper' }, {
    takes_value = true,
    metavar = 'PATH',
    description = 'Run helper script at PATH before executing tests.',
  })
  parser:add_argument({ '--lua' }, {
    takes_value = true,
    metavar = 'LUA',
    description = 'Path to the Lua interpreter busted should run under.',
  })
  parser:add_argument({ '-Xoutput' }, {
    takes_value = true,
    metavar = 'OPTION',
    handler = function(state, value)
      return processList(state, 'Xoutput', value)
    end,
    description = 'Pass OPTION (comma-separated) to the output handler.',
  })
  parser:add_argument({ '-Xhelper' }, {
    takes_value = true,
    metavar = 'OPTION',
    handler = function(state, value)
      return processList(state, 'Xhelper', value)
    end,
    description = 'Pass OPTION (comma-separated) to the helper script.',
  })
  parser:add_negatable_argument({ '-c', '--coverage' }, { '--no-coverage' }, {
    description = 'Enable code coverage analysis (requires LuaCov).',
    negated_description = 'Disable code coverage analysis.',
  })
  parser:add_negatable_argument({ '-v', '--verbose' }, { '--no-verbose' }, {
    description = 'Enable verbose output of errors.',
    negated_description = 'Disable verbose error output.',
  })
  parser:add_argument({ '-l', '--list' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'list', true, 'l')
    end,
    description = 'List the names of all tests instead of running them.',
  })
  parser:add_argument({ '--ignore-lua' }, {
    takes_value = false,
    handler = function(state)
      return processOption(state, 'ignore-lua', true)
    end,
    description = 'Ignore the --lua directive.',
  })
  parser:add_negatable_argument({ '--lazy' }, { '--no-lazy' }, {
    description = 'Use lazy setup/teardown as the default.',
    negated_description = 'Disable lazy setup/teardown.',
  })
  parser:add_negatable_argument({ '--auto-insulate' }, { '--no-auto-insulate' }, {
    description = 'Enable file insulation (default).',
    negated_description = 'Disable file insulation.',
  })
  parser:add_negatable_argument({ '-k', '--keep-going' }, { '--no-keep-going' }, {
    description = 'Continue after errors or failures (default).',
    negated_description = 'Stop on the first error or failure.',
  })
  parser:add_negatable_argument({ '-R', '--recursive' }, { '--no-recursive' }, {
    description = 'Recurse into subdirectories when searching for specs (default).',
    negated_description = 'Do not recurse into subdirectories.',
  })
  parser:add_negatable_argument({ '--sort-files' }, { '--no-sort-files' }, {
    description = 'Sort file execution order alphabetically.',
    negated_description = 'Run files in discovery order.',
  })
  parser:add_negatable_argument({ '--sort-tests' }, { '--no-sort-tests' }, {
    description = 'Sort test execution order within a file.',
    negated_description = 'Run tests in definition order.',
  })
  parser:add_negatable_argument({ '--suppress-pending' }, { '--no-suppress-pending' }, {
    description = 'Suppress pending test output.',
    negated_description = 'Show pending test output (default).',
  })
  parser:add_negatable_argument({ '--defer-print' }, { '--no-defer-print' }, {
    description = 'Defer printing until the suite completes.',
    negated_description = 'Print output as events occur (default).',
  })
  parser:add_negatable_argument({ '--sort' }, { '--no-sort' }, {
    description = 'Enable both --sort-files and --sort-tests.',
    negated_description = 'Disable both --sort-files and --sort-tests.',
    handler = function(state)
      return processSort(state, 'sort', true)
    end,
    negated_handler = function(state)
      return processSort(state, 'sort', false)
    end,
  })
  --- @param args string[]
  --- @return table<string, any>? args
  --- @return string? error
  local function parse(args)
    local cliArgs, cliArgsParsedOrErr = parser:parse(args)
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

  local api = {}

  --- @param name string
  --- @return table
  function api:set_name(name)
    appName = name or ''
    parser:set_name(appName)
    return self
  end

  --- @param args string[]
  --- @return table<string, any>?, string?
  function api.parse(_, args)
    return parse(args)
  end

  return api
end
