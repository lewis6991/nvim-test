local utils = require('busted.utils')
local exit = require('busted.exit')

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs
local is_windows = uv.os_uname().sysname:match('Windows')

local HELP_TEMPLATE = [=[
Usage: %s [OPTIONS] [--] [ROOT-1 [ROOT-2 [...]]]

ARGUMENTS:
  ROOT                        test script file/folder. Folders will be
                              traversed for any file that matches the
                              --pattern option. (optional, default:
                              nil)

OPTIONS:
  --version                   prints the program version and exits
  -p, --pattern=PATTERN       only run test files matching the Lua
                              pattern (default: _spec)
  --exclude-pattern=PATTERN   do not run test files matching the Lua
                              pattern, takes precedence over --pattern
  -e STATEMENT                execute statement STATEMENT
  -o, --output=LIBRARY        output library to load (default:
                              busted.outputHandlers.output_handler)
  -C, --directory=DIR         change to directory DIR before running
                              tests. If multiple options are specified,
                              each is interpreted relative to the
                              previous one. (default: ./)
  -f, --config-file=FILE      load configuration options from FILE
  --coverage-config-file=FILE load luacov configuration options from
                              FILE
  -t, --tags=TAGS             only run tests with these #tags (default:
                              [])
  --exclude-tags=TAGS         do not run tests with these #tags, takes
                              precedence over --tags (default: [])
  --filter=PATTERN            only run test names matching the Lua
                              pattern (default: [])
  --name=NAME                 run test with the given full name
                              (default: [])
  --filter-out=PATTERN        do not run test names matching the Lua
                              pattern, takes precedence over --filter
                              (default: [])
  --exclude-names-file=FILE   do not run the tests with names listed in
                              the given file, takes precedence over
                              --filter
  --log-success=FILE          append the name of each successful test
                              to the given file
  -m, --lpath=PATH            optional path to be prefixed to the Lua
                              module search path (default:
                              ./src/?.lua;./src/?/?.lua;./src/?/init.lua)
  --cpath=PATH                optional path to be prefixed to the Lua C
                              module search path (default:
                              ./csrc/?.so;./csrc/?/?.so;)
  -r, --run=RUN               config to run from .busted file
  --repeat=COUNT              run the tests repeatedly (default: 1)
  --loaders=NAME              test file loaders (default: lua)
  --helper=PATH               A helper script that is run before tests
  --lua=LUA                   The path to the lua interpreter busted
                              should run under
  -Xoutput OPTION             pass `OPTION` as an option to the output
                              handler. If `OPTION` contains commas, it
                              is split into multiple options at the
                              commas. (default: [])
  -Xhelper OPTION             pass `OPTION` as an option to the helper
                              script. If `OPTION` contains commas, it
                              is split into multiple options at the
                              commas. (default: [])
  -c, --[no-]coverage         do code coverage analysis (requires
                              `LuaCov` to be installed) (default: off)
  -v, --[no-]verbose          verbose output of errors (default: off)
  -l, --list                  list the names of all tests instead of
                              running them
  --ignore-lua                Whether or not to ignore the lua
                              directive
  --[no-]lazy                 use lazy setup/teardown as the default
                              (default: off)
  --[no-]auto-insulate        enable file insulation (default: on)
  -k, --[no-]keep-going       continue as much as possible after an
                              error or failure (default: on)
  -R, --[no-]recursive        recurse into subdirectories (default: on)
  --[no-]sort                 sort file and test order (--sort-tests
                              and --sort-files) (default: off)
  --[no-]sort-files           sort file execution order (default: off)
  --[no-]sort-tests           sort test order within a file (default:
                              off)
  --[no-]suppress-pending     suppress `pending` test output (default:
                              off)
  --[no-]defer-print          defer print to when test suite is
                              complete (default: off)
]=]

return function(options)
  local appName = ''
  options = options or {}
  local allow_roots = not options.standalone

  local configLoader = require('busted.modules.configuration_loader')()

  local defaultOutput = options.output or 'busted.outputHandlers.output_handler'
  local defaultLoaders = 'lua'
  local defaultPattern = '_spec'
  local lpathprefix = './src/?.lua;./src/?/?.lua;./src/?/init.lua'
  local cpathprefix = is_windows and './csrc/?.dll;./csrc/?/?.dll;' or './csrc/?.so;./csrc/?/?.so;'

  local function normalize(pathname)
    if not pathname or pathname == '' then
      return pathname
    end
    return fs.normalize(pathname)
  end

  local function join(base, relative)
    if not base or base == '' then
      return normalize(relative)
    end
    if not relative or relative == '' then
      return normalize(base)
    end
    return normalize(fs.joinpath(base, relative))
  end

  local function isfile(pathname)
    local stat = uv.fs_stat(pathname)
    return stat and stat.type == 'file'
  end

  local function run_lua_interpreter(command, script, args)
    local cmd = { command, script, '--ignore-lua' }
    for _, value in ipairs(args) do
      cmd[#cmd + 1] = value
    end
    local result = vim.system(cmd):wait()
    exit(result.code)
  end

  local function makeList(values)
    return type(values) == 'table' and values or { values }
  end

  local function fixupList(values, sep)
    sep = sep or ','
    local list = type(values) == 'table' and values or { values }
    local olist = {}
    for _, v in ipairs(list) do
      vim.list_extend(olist, utils.split(v, sep))
    end
    return olist
  end

  local function make_defaults()
    local pattern = { defaultPattern }
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
      loaders = { defaultLoaders },
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

  local function new_state()
    return {
      args = make_defaults(),
      overrides = {},
    }
  end

  local function assign(state, key, value, altkey)
    state.args[key] = value
    state.overrides[key] = value
    if altkey then
      state.args[altkey] = value
      state.overrides[altkey] = value
    end
  end

  local function processOption(state, key, value, altkey)
    assign(state, key, value, altkey)
    return true
  end

  local function processArgList(state, key, value)
    local list = state.overrides[key]
    if not list then
      list = {}
    end
    vim.list_extend(list, utils.split(value, ','))
    assign(state, key, list)
    return true
  end

  local function processNumber(state, key, value, altkey, opt)
    local number = tonumber(value)
    if not number then
      return nil, 'argument to ' .. opt .. ' must be a number'
    end
    assign(state, key, number, altkey)
    return true
  end

  local function processList(state, key, value, altkey)
    local list = state.overrides[key] or {}
    vim.list_extend(list, utils.split(value, ','))
    assign(state, key, list, altkey)
    return true
  end

  local function processMultiOption(state, key, value, altkey)
    local list = state.overrides[key] or {}
    table.insert(list, value)
    assign(state, key, list, altkey)
    return true
  end

  local function append_value(current, value, sep)
    if not current or current == '' then
      return value
    end
    return current .. sep .. value
  end

  local function processLoaders(state, key, value, altkey)
    local combined = append_value(state.overrides[key], value, ',')
    assign(state, key, combined, altkey)
    return true
  end

  local function processPath(state, key, value, altkey)
    local combined = append_value(state.overrides[key], value, ';')
    assign(state, key, combined, altkey)
    return true
  end

  local function processDir(state, key, value, altkey)
    local base = state.overrides[key] or ''
    local dpath = join(base, value)
    assign(state, key, dpath, altkey)
    return true
  end

  local function processSort(state, _, value)
    assign(state, 'sort-files', value)
    assign(state, 'sort-tests', value)
    return true
  end

  local option_handlers = {}
  local function register_option(names, spec)
    for _, name in ipairs(names) do
      option_handlers[name] = spec
    end
  end

  local function simple_flag(display, key, value, altkey)
    return {
      takes_value = false,
      display = display,
      handler = function(state)
        return processOption(state, key, value, altkey)
      end,
    }
  end

  local function value_option(display, handler)
    return {
      takes_value = true,
      display = display,
      handler = handler,
    }
  end

  register_option({ '--version' }, simple_flag('--version', 'version', true))

  if allow_roots then
    register_option({ '-p', '--pattern' }, value_option('--pattern', function(state, value)
      return processMultiOption(state, 'pattern', value, 'p')
    end))
    register_option({ '--exclude-pattern' }, value_option('--exclude-pattern', function(state, value)
      return processMultiOption(state, 'exclude-pattern', value)
    end))
  end
  register_option({ '-e' }, value_option('-e', function(state, value)
    return processMultiOption(state, 'e', value)
  end))
  register_option({ '-o', '--output' }, value_option('--output', function(state, value)
    return processOption(state, 'output', value, 'o')
  end))
  register_option({ '-C', '--directory' }, value_option('--directory', function(state, value)
    return processDir(state, 'directory', value, 'C')
  end))
  register_option({ '-f', '--config-file' }, value_option('--config-file', function(state, value)
    processOption(state, 'config-file', value)
    return processOption(state, 'f', value)
  end))
  register_option({ '--coverage-config-file' }, value_option('--coverage-config-file', function(state, value)
    return processOption(state, 'coverage-config-file', value)
  end))
  register_option({ '-t', '--tags' }, value_option('--tags', function(state, value)
    return processList(state, 'tags', value, 't')
  end))
  register_option({ '--exclude-tags' }, value_option('--exclude-tags', function(state, value)
    return processList(state, 'exclude-tags', value)
  end))
  register_option({ '--filter' }, value_option('--filter', function(state, value)
    return processMultiOption(state, 'filter', value)
  end))
  register_option({ '--name' }, value_option('--name', function(state, value)
    return processMultiOption(state, 'name', value)
  end))
  register_option({ '--filter-out' }, value_option('--filter-out', function(state, value)
    return processMultiOption(state, 'filter-out', value)
  end))
  register_option({ '--exclude-names-file' }, value_option('--exclude-names-file', function(state, value)
    return processOption(state, 'exclude-names-file', value)
  end))
  register_option({ '--log-success' }, value_option('--log-success', function(state, value)
    return processOption(state, 'log-success', value)
  end))
  register_option({ '-m', '--lpath' }, value_option('--lpath', function(state, value)
    return processPath(state, 'lpath', value, 'm')
  end))
  register_option({ '--cpath' }, value_option('--cpath', function(state, value)
    return processPath(state, 'cpath', value)
  end))
  register_option({ '-r', '--run' }, value_option('--run', function(state, value)
    return processOption(state, 'run', value)
  end))
  register_option({ '--repeat' }, value_option('--repeat', function(state, value)
    return processNumber(state, 'repeat', value, nil, '--repeat')
  end))
  register_option({ '--loaders' }, value_option('--loaders', function(state, value)
    return processLoaders(state, 'loaders', value)
  end))
  register_option({ '--helper' }, value_option('--helper', function(state, value)
    return processOption(state, 'helper', value)
  end))
  register_option({ '--lua' }, value_option('--lua', function(state, value)
    return processOption(state, 'lua', value)
  end))
  register_option({ '-Xoutput' }, value_option('-Xoutput', function(state, value)
    return processList(state, 'Xoutput', value)
  end))
  register_option({ '-Xhelper' }, value_option('-Xhelper', function(state, value)
    return processList(state, 'Xhelper', value)
  end))

  register_option({ '-c', '--coverage' }, simple_flag('--coverage', 'coverage', true, 'c'))
  register_option({ '--no-coverage' }, simple_flag('--no-coverage', 'coverage', false, 'c'))
  register_option({ '-v', '--verbose' }, simple_flag('--verbose', 'verbose', true, 'v'))
  register_option({ '--no-verbose' }, simple_flag('--no-verbose', 'verbose', false, 'v'))
  register_option({ '-l', '--list' }, simple_flag('--list', 'list', true, 'l'))
  register_option({ '--ignore-lua' }, simple_flag('--ignore-lua', 'ignore-lua', true))
  register_option({ '--lazy' }, simple_flag('--lazy', 'lazy', true))
  register_option({ '--no-lazy' }, simple_flag('--no-lazy', 'lazy', false))
  register_option({ '--auto-insulate' }, simple_flag('--auto-insulate', 'auto-insulate', true))
  register_option({ '--no-auto-insulate' }, simple_flag('--no-auto-insulate', 'auto-insulate', false))
  register_option({ '-k', '--keep-going' }, simple_flag('--keep-going', 'keep-going', true, 'k'))
  register_option({ '--no-keep-going' }, simple_flag('--no-keep-going', 'keep-going', false, 'k'))
  register_option({ '-R', '--recursive' }, simple_flag('--recursive', 'recursive', true, 'R'))
  register_option({ '--no-recursive' }, simple_flag('--no-recursive', 'recursive', false, 'R'))
  register_option({ '--sort-files' }, simple_flag('--sort-files', 'sort-files', true))
  register_option({ '--no-sort-files' }, simple_flag('--no-sort-files', 'sort-files', false))
  register_option({ '--sort-tests' }, simple_flag('--sort-tests', 'sort-tests', true))
  register_option({ '--no-sort-tests' }, simple_flag('--no-sort-tests', 'sort-tests', false))
  register_option({ '--suppress-pending' }, simple_flag('--suppress-pending', 'suppress-pending', true))
  register_option({ '--no-suppress-pending' }, simple_flag('--no-suppress-pending', 'suppress-pending', false))
  register_option({ '--defer-print' }, simple_flag('--defer-print', 'defer-print', true))
  register_option({ '--no-defer-print' }, simple_flag('--no-defer-print', 'defer-print', false))
  register_option({ '--sort' }, {
    takes_value = false,
    display = '--sort',
    handler = function(state)
      return processSort(state, 'sort', true)
    end,
  })
  register_option({ '--no-sort' }, {
    takes_value = false,
    display = '--no-sort',
    handler = function(state)
      return processSort(state, 'sort', false)
    end,
  })

  local function parse_cli_args(args)
    local state = new_state()
    args = args or {}
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
          return nil, string.format(HELP_TEMPLATE, appName)
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
          return nil, string.format(HELP_TEMPLATE, appName)
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

  local function parse(args)
    local cliArgs, cliArgsParsedOrErr = parse_cli_args(args)
    if not cliArgs then
      return nil, appName .. ': error: ' .. cliArgsParsedOrErr .. '; re-run with --help for usage.'
    end
    local cliArgsParsed = cliArgsParsedOrErr

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
      run_lua_interpreter(cliArgs['lua'], args[0], args)
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
    set_name = function(self, name)
      appName = name or ''
      return self
    end,

    set_silent = function(self, name)
      appName = name or ''
      return self
    end,

    parse = function(_, args)
      return parse(args)
    end,
  }
end
