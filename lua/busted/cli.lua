local utils = require('busted.utils')
local argparse = require('argparse')

local is_windows = vim.uv.os_uname().sysname:match('Windows')

--- @class busted.cli.Options
--- @field output? string

--- @param pathname string?
--- @return string?
local function normalize(pathname)
  if not pathname or pathname == '' then
    return pathname
  end
  return vim.fs.normalize(pathname)
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
  return normalize(vim.fs.joinpath(base, relative))
end

--- @param pathname string?
--- @return boolean
local function isfile(pathname)
  if not pathname or pathname == '' then
    return false
  end
  local stat = vim.uv.fs_stat(pathname)
  return stat ~= nil and stat.type == 'file'
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

--- @class busted.cli.Arguments
--- @field ROOT string[]
--- @field version boolean
--- @field pattern string[]
--- @field exclude-pattern string[]
--- @field exec string[]
--- @field output string
--- @field directory string
--- @field config-file string?
--- @field coverage-config-file string?
--- @field tags string[]
--- @field exclude-tags string[]
--- @field filter string[]
--- @field filter-out string[]
--- @field exclude-names-file string?
--- @field lpath string
--- @field m string
--- @field cpath string
--- @field run? string
--- @field r? string
--- @field helper? string
--- @field repeat integer
--- @field coverage boolean
--- @field verbose boolean
--- @field v boolean
--- @field list boolean
--- @field l boolean
--- @field lazy boolean
--- @field suppress-pending boolean
--- @field quit-on-error boolean

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

local function merge_tables(base, overrides)
  return vim.deep_extend('force', base, overrides or {})
end

local function config_loader(config_file, config, defaults)
  if type(config_file) ~= 'table' then
    return nil, '.busted file does not return a table.'
  end

  defaults = defaults or {}
  local run = config.run or defaults.run

  if run and run ~= '' then
    local runConfig = config_file[run]

    if type(runConfig) == 'table' then
      config = merge_tables(runConfig, config)
    else
      return nil, 'Task `' .. run .. '` not found, or not a table.'
    end
  elseif type(config_file.default) == 'table' then
    config = merge_tables(config_file.default, config)
  end

  if type(config_file._all) == 'table' then
    config = merge_tables(config_file._all, config)
  end

  config = merge_tables(defaults, config)

  return config
end

--- @param options? busted.cli.Options
return function(options)
  local appName = ''
  options = options or {}
  local defaultOutput = options.output or 'busted.outputHandlers.output_handler'
  local parser = argparse.new_parser({
    state_factory = function()
      return {
        args = { ROOT = { 'spec' } },
        overrides = {},
      }
    end,
    positional_handler = function(state, argument)
      local list = state.overrides['ROOT']
      if not list then
        list = {}
      end
      vim.list_extend(list, utils.split(argument or '', ','))
      assign(state, 'ROOT', list)
      return true
    end,
    app_name = appName,
  })

  parser:add_argument_help(
    'ROOT',
    'Test script file or directory. Directories are traversed for files matching --pattern.'
  )

  parser:add_argument({ '--version' }, {
    help = 'Print the program version and exit.',
    default = false,
  })
  parser:add_argument({ '-p', '--pattern' }, {
    metavar = 'PATTERN',
    multi = true,
    help = 'Only run test files matching the Lua pattern.',
    default = { '_spec' },
  })
  parser:add_argument({ '--exclude-pattern' }, {
    metavar = 'PATTERN',
    multi = true,
    help = 'Do not run files matching the Lua pattern; takes precedence over --pattern.',
    default = {},
  })
  parser:add_argument({ '-e', '--exec' }, {
    metavar = 'STATEMENT',
    multi = true,
    help = 'Execute Lua statement STATEMENT before running tests.',
    default = {},
  })
  parser:add_argument({ '-o', '--output' }, {
    metavar = 'LIBRARY',
    help = 'Output handler module to load.',
    default = defaultOutput,
  })
  parser:add_argument({ '-C', '--directory' }, {
    metavar = 'DIR',
    handler = function(state, value)
      return processDir(state, 'directory', value, 'C')
    end,
    help = 'Change to DIR before running tests; multiple directories are resolved incrementally.',
    default = './',
  })
  parser:add_argument({ '-f', '--config-file' }, {
    metavar = 'FILE',
    help = 'Load configuration options from FILE.',
  })
  parser:add_argument({ '--coverage-config-file' }, {
    metavar = 'FILE',
    help = 'Load LuaCov configuration options from FILE.',
  })
  parser:add_argument({ '-t', '--tags' }, {
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'tags', value, 't')
    end,
    help = 'Only run tests with these comma-separated #tags.',
    default = {},
  })
  parser:add_argument({ '--exclude-tags' }, {
    metavar = 'TAGS',
    handler = function(state, value)
      return processList(state, 'exclude-tags', value)
    end,
    help = 'Do not run tests with these #tags; takes precedence over --tags.',
    default = {},
  })
  parser:add_argument({ '--filter' }, {
    metavar = 'PATTERN',
    multi = true,
    help = 'Only run tests whose names match the Lua pattern.',
    default = {},
  })
  parser:add_argument({ '--filter-out' }, {
    metavar = 'PATTERN',
    multi = true,
    help = 'Exclude tests whose names match the Lua pattern; takes precedence over --filter.',
    default = {},
  })
  parser:add_argument({ '--exclude-names-file' }, {
    metavar = 'FILE',
    help = 'Skip tests whose names appear in FILE; takes precedence over name filters.',
  })
  parser:add_argument({ '-m', '--lpath' }, {
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'lpath', value, 'm')
    end,
    help = 'Prefix PATH to package.path.',
    default = lpathprefix,
  })
  parser:add_argument({ '--cpath' }, {
    metavar = 'PATH',
    handler = function(state, value)
      return processPath(state, 'cpath', value)
    end,
    help = 'Prefix PATH to package.cpath.',
    default = cpathprefix,
  })
  parser:add_argument({ '-r', '--run' }, {
    metavar = 'RUN',
    help = 'Load configuration RUN from the project .busted file.',
  })
  parser:add_argument({ '--repeat' }, {
    metavar = 'COUNT',
    handler = function(state, value)
      return processNumber(state, 'repeat', value, nil, '--repeat')
    end,
    help = 'Run the entire test suite COUNT times.',
    default = 1,
  })
  parser:add_argument({ '--helper' }, {
    metavar = 'PATH',
    help = 'Run helper script at PATH before executing tests.',
  })
  parser:add_argument({ '--coverage' }, {
    help = 'Enable code coverage analysis (requires LuaCov).',
    default = false,
  })
  parser:add_argument({ '-v', '--verbose' }, {
    help = 'Enable verbose output of errors.',
    default = false,
  })
  parser:add_argument({ '-l', '--list' }, {
    help = 'List the names of all tests instead of running them.',
    default = false,
  })
  parser:add_argument({ '--lazy' }, {
    help = 'Use lazy setup/teardown as the default.',
    default = false,
  })
  parser:add_argument({ '--suppress-pending' }, {
    help = 'Suppress pending test output.',
    default = false,
  })
  parser:add_argument({ '--quit-on-error' }, {
    help = 'Quit the test run on the first error or failure.',
    default = false,
  })

  --- @param args string[]
  --- @return busted.cli.Arguments? args
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
          local conf, cerr = config_loader(bustedConfigFile(), cliArgsParsed, cliArgs)
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
    cliArgs.e = makeList(cliArgs.e)
    cliArgs.pattern = makeList(cliArgs.pattern)
    cliArgs.p = cliArgs.pattern
    cliArgs['exclude-pattern'] = makeList(cliArgs['exclude-pattern'])
    cliArgs.filter = makeList(cliArgs.filter)
    cliArgs['filter-out'] = makeList(cliArgs['filter-out'])
    cliArgs.tags = fixupList(cliArgs.tags)
    cliArgs.t = cliArgs.tags
    cliArgs['exclude-tags'] = fixupList(cliArgs['exclude-tags'])
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
  --- @return busted.cli.Arguments? args
  --- @return string? error
  function api.parse(_, args)
    return parse(args)
  end

  return api
end
