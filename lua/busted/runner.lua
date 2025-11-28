-- Busted command-line runner

local uv = vim.uv or vim.loop
local fs = vim.fs
local utils = require('busted.utils')
local exit = require('busted.exit')
local loadstring = _G.loadstring or load
local loaded = false

return function(options)
  if loaded then
    return function() end
  else
    loaded = true
  end

  local defaultOptions = require('busted.options')
  if options then
    for k, v in pairs(options) do
      defaultOptions[k] = v
    end
  end
  options = defaultOptions
  options.output = options.output or 'nvim-test.busted.output_handler'

  local busted = require('busted.core')()

  local cli = require('busted.modules.cli')(options)
  local filterLoader = require('busted.modules.filter_loader')()
  local helperLoader = require('busted.modules.helper_loader')()
  local outputHandlerLoader = require('busted.modules.output_handler_loader')()

  local luacov = require('busted.modules.luacov')()

  require('busted')(busted)

  local level = 2
  local info = debug.getinfo(level, 'Sf')
  local source = info.source
  local fileName = source:sub(1, 1) == '@' and source:sub(2) or nil
  local forceExit = fileName == nil

  -- Parse the cli arguments
  local appName = fs.basename(fileName or 'busted')
  cli:set_name(appName)
  local cliArgs, err = cli:parse(arg)
  if not cliArgs then
    io.stderr:write(err .. '\n')
    exit(1, forceExit)
  end

  if cliArgs.version then
    -- Return early if asked for the version
    print(busted.version)
    exit(0, forceExit)
  end

  -- Load current working directory
  local target_dir = fs.normalize(cliArgs.directory)
  local ok, err1 = pcall(uv.chdir, target_dir)
  if not ok then
    io.stderr:write(appName .. ': error: ' .. err1 .. '\n')
    exit(1, forceExit)
  end

  -- If coverage arg is passed in, load LuaCovsupport
  if cliArgs.coverage then
    local ok, err2 = luacov(cliArgs['coverage-config-file'])
    if not ok then
      io.stderr:write(appName .. ': error: ' .. err2 .. '\n')
      exit(1, forceExit)
    elseif err2 then
      io.stderr:write(appName .. ': warning: ' .. err2 .. '\n')
    end
  end

  -- If auto-insulate is disabled, re-register file without insulation
  if not cliArgs['auto-insulate'] then
    busted.register('file', 'file', {})
  end

  -- If lazy is enabled, make lazy setup/teardown the default
  if cliArgs.lazy then
    busted.register('setup', 'lazy_setup')
    busted.register('teardown', 'lazy_teardown')
  end

  -- Add additional package paths based on lpath and cpath cliArgs
  if #cliArgs.lpath > 0 then
    package.path = (cliArgs.lpath .. ';' .. package.path):gsub(';;', ';')
  end

  if #cliArgs.cpath > 0 then
    package.cpath = (cliArgs.cpath .. ';' .. package.cpath):gsub(';;', ';')
  end

  -- Load and execute commands given on the command-line
  if cliArgs.e then
    for _, v in ipairs(cliArgs.e) do
      loadstring(v)()
    end
  end

  -- watch for test errors and failures
  local failures = 0
  local errors = 0
  local quitOnError = not cliArgs['keep-going']

  busted.subscribe({ 'error', 'output' }, function(element, _parent, message)
    io.stderr:write(
      appName .. ': error: Cannot load output library: ' .. element.name .. '\n' .. message .. '\n'
    )
    return nil, true
  end)

  busted.subscribe({ 'error', 'helper' }, function(element, _parent, message)
    io.stderr:write(
      appName .. ': error: Cannot load helper script: ' .. element.name .. '\n' .. message .. '\n'
    )
    return nil, true
  end)

  busted.subscribe({ 'error' }, function(_element, _parent, _message)
    errors = errors + 1
    busted.skipAll = quitOnError
    return nil, true
  end)

  busted.subscribe({ 'failure' }, function(element, _parent, _message)
    if element.descriptor == 'it' then
      failures = failures + 1
    else
      errors = errors + 1
    end
    busted.skipAll = quitOnError
    return nil, true
  end)

  -- Set up randomization options
  busted.sort = cliArgs['sort-tests']
  busted.randomize = cliArgs['shuffle-tests']
  busted.randomseed = tonumber(cliArgs.seed) or utils.urandom() or os.time()

  -- Set up output handler to listen to events
  outputHandlerLoader(busted, cliArgs.output, {
    defaultOutput = options.output,
    verbose = cliArgs.verbose,
    suppressPending = cliArgs['suppress-pending'],
    deferPrint = cliArgs['defer-print'],
    arguments = cliArgs.Xoutput,
  })

  -- Pre-load the LuaJIT 'ffi' module if applicable
  require('busted.luajit')()

  -- Set up helper script, must succeed to even start tests
  if cliArgs.helper and cliArgs.helper ~= '' then
    local ok, err2 = helperLoader(busted, cliArgs.helper, {
      verbose = cliArgs.verbose,
      arguments = cliArgs.Xhelper,
    })
    if not ok then
      io.stderr:write(
        appName
          .. ': failed running the specified helper ('
          .. cliArgs.helper
          .. '), error: '
          .. err2
          .. '\n'
      )
      exit(1, forceExit)
    end
  end

  local getFullName = function(name)
    local parent = busted.context.get()
    local names = { name }

    while parent and (parent.name or parent.descriptor) and parent.descriptor ~= 'file' do
      table.insert(names, 1, parent.name or parent.descriptor)
      parent = busted.context.parent(parent)
    end

    return table.concat(names, ' ')
  end

  if cliArgs['log-success'] then
    local logFile = assert(io.open(cliArgs['log-success'], 'a'))
    busted.subscribe({ 'test', 'end' }, function(_test, _parent, status)
      if status == 'success' then
        logFile:write(getFullName() .. '\n')
      end
    end)
  end

  -- Load tag and test filters
  filterLoader(busted, {
    tags = cliArgs.tags,
    excludeTags = cliArgs['exclude-tags'],
    filter = cliArgs.filter,
    name = cliArgs.name,
    filterOut = cliArgs['filter-out'],
    excludeNamesFile = cliArgs['exclude-names-file'],
    list = cliArgs.list,
    nokeepgoing = not cliArgs['keep-going'],
    suppressPending = cliArgs['suppress-pending'],
  })

  if cliArgs.ROOT then
    -- Load test directories/files
    local rootFiles = cliArgs.ROOT
    local patterns = cliArgs.pattern
    local testFileLoader = require('busted.modules.test_file_loader')(busted, cliArgs.loaders)
    testFileLoader(rootFiles, patterns, {
      excludes = cliArgs['exclude-pattern'],
      verbose = cliArgs.verbose,
      recursive = cliArgs['recursive'],
    })
  else
    -- Running standalone, use standalone loader
    local testFileLoader = require('busted.modules.standalone_loader')(busted)
    testFileLoader(info, { verbose = cliArgs.verbose })
  end

  local runs = cliArgs['repeat']
  local execute = require('busted.execute')(busted)
  execute(runs, {
    seed = cliArgs.seed,
    shuffle = cliArgs['shuffle-files'],
    sort = cliArgs['sort-files'],
  })

  busted.publish({ 'exit' })

  if options.standalone or failures > 0 or errors > 0 then
    exit(failures + errors, forceExit)
  end
end
