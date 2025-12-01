-- Busted command-line runner

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs
local fs_util = require('nvim-test.util.fs')
local exit = require('busted.exit')
local load_chunk = _G.loadstring or load
if not load_chunk then
  error('load function is required')
end
---@cast load_chunk fun(code: string, chunkname?: string): function
local loaded = false

local function main(custom_options)
  local provided_options = custom_options or { standalone = false }
  if loaded then
    return function() end
  else
    loaded = true
  end

  local defaultOptions = require('busted.options')
  if provided_options then
    for k, v in pairs(provided_options) do
      defaultOptions[k] = v
    end
  end
  local options = defaultOptions
  options.output = options.output or 'busted.outputHandlers.output_handler'

  local busted = require('busted.core').new()

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
  --- @cast cliArgs table<string, any>

  io.stderr:write('coverage flag: ' .. tostring(cliArgs.coverage) .. '\n')

  if cliArgs.version then
    -- Return early if asked for the version
    print(busted.version)
    exit(0, forceExit)
  end

  -- Load current working directory
  local target_dir = fs.normalize(cliArgs.directory or './')
  local chdir_ok, chdir_err = pcall(uv.chdir, target_dir)
  if not chdir_ok then
    io.stderr:write(appName .. ': error: ' .. chdir_err .. '\n')
    exit(1, forceExit)
  end

  -- If coverage arg is passed in, load LuaCovsupport
  if cliArgs.coverage then
    local coverage_ok, coverage_err = luacov(cliArgs['coverage-config-file'])
    if not coverage_ok then
      io.stderr:write(appName .. ': error: ' .. coverage_err .. '\n')
      exit(1, forceExit)
    elseif coverage_err then
      io.stderr:write(appName .. ': warning: ' .. coverage_err .. '\n')
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
      load_chunk(v)()
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

  -- Set up ordering options
  busted.sort = cliArgs['sort-tests']

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
    local helper_ok, helper_err = helperLoader(busted, cliArgs.helper, {
      verbose = cliArgs.verbose,
      arguments = cliArgs.Xhelper,
    })
    if not helper_ok then
      io.stderr:write(
        appName
          .. ': failed running the specified helper ('
          .. cliArgs.helper
          .. '), error: '
          .. helper_err
          .. '\n'
      )
      exit(1, forceExit)
    end
  end

  local getFullName = function(name)
    local parent = busted.context:get()
    local names = { name }

    while parent and (parent.name or parent.descriptor) and parent.descriptor ~= 'file' do
      table.insert(names, 1, parent.name or parent.descriptor)
      parent = busted.context:parent(parent)
    end

    return table.concat(names, ' ')
  end

  local log_success = cliArgs['log-success']
  if log_success then
    busted.subscribe({ 'test', 'end' }, function(_test, _parent, status)
      if status == 'success' then
        fs_util.append_lines(log_success, { getFullName() })
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
    sort = cliArgs['sort-files'],
  })

  busted.publish({ 'exit' })

  if cliArgs.coverage then
    local ok_luacov, luacov_mod = pcall(require, 'luacov')
    if ok_luacov and type(luacov_mod) == 'table' and luacov_mod.shutdown then
      if luacov_mod.load_config then
        luacov_mod.configuration = nil
        local config_arg = cliArgs['coverage-config-file']
        pcall(luacov_mod.load_config, config_arg)
      end

      local ok_shutdown, err_shutdown = pcall(luacov_mod.shutdown)
      if not ok_shutdown then
        io.stderr:write('luacov: shutdown failed: ' .. tostring(err_shutdown) .. '\n')
      end
    end
  end

  if options.standalone or failures > 0 or errors > 0 then
    exit(failures + errors, forceExit)
  end
end

main({ standalone = false })
