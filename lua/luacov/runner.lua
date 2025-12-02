--- @class luacov.runner
local M = {}

local stats = require('luacov.stats')
local util = require('luacov.util')

--- Default values for configuration options.
--- For project specific configuration create '.luacov' file in your project
--- folder. It should be a Lua script setting various options as globals
--- or returning table of options.
M.defaults = {

  --- Filename to store collected stats. Default: "luacov.stats.out".
  statsfile = 'luacov.stats.out',

  --- Filename to store report. Default: "luacov.report.out".
  reportfile = 'luacov.report.out',

  --- Enable saving coverage data after every `savestepsize` lines?
  -- Setting this flag to `true` in config is equivalent to running LuaCov
  -- using `luacov.tick` module. Default: false.
  tick = false,

  --- Stats file updating frequency for `luacov.tick`.
  -- The lower this value - the more frequently results will be written out to the stats file.
  -- You may want to reduce this value (to, for example, 2) to avoid losing coverage data in
  -- case your program may terminate without triggering luacov exit hooks that are supposed
  -- to save the data. Default: 100.
  savestepsize = 100,

  --- Run reporter on completion? Default: false.
  runreport = false,

  --- Delete stats file after reporting? Default: false.
  deletestats = false,

  --- Process Lua code loaded from raw strings?
  -- That is, when the 'source' field in the debug info
  -- does not start with '@'. Default: false.
  codefromstrings = false,

  --- Lua patterns for files to include when reporting.
  -- All will be included if nothing is listed.
  -- Do not include the '.lua' extension. Path separator is always '/'.
  -- Overruled by `exclude`.
  -- @usage
  -- include = {
  --    "mymodule$",      -- the main module
  --    "mymodule%/.+$",  -- and everything namespaced underneath it
  -- }
  include = {},

  --- Lua patterns for files to exclude when reporting.
  -- Nothing will be excluded if nothing is listed.
  -- Do not include the '.lua' extension. Path separator is always '/'.
  -- Overrules `include`.
  exclude = {},

  --- Table mapping names of modules to be included to their filenames.
  -- Has no effect if empty.
  -- Real filenames mentioned here will be used for reporting
  -- even if the modules have been installed elsewhere.
  -- Module name can contain '*' wildcard to match groups of modules,
  -- in this case corresponding path will be used as a prefix directory
  -- where modules from the group are located.
  -- @usage
  -- modules = {
  --    ["some_rock"] = "src/some_rock.lua",
  --    ["some_rock.*"] = "src"
  -- }
  modules = {},

  --- Enable including untested files in report.
  -- If `true`, all untested files in "." will be included.
  -- If it is a table with directory and file paths, all untested files in these paths will be included.
  -- Note that you are not allowed to use patterns in these paths.
  -- Default: false.
  includeuntestedfiles = false,
}

--- @class luacov.Configuration
--- @field include string[]?
--- @field exclude string[]?
--- @field statsfile string?
--- @field reportfile string?
--- @field runreport boolean?
--- @field reporter string?
--- @field modules table<string, string>?
--- @field tick boolean?
--- @field savestepsize integer?
--- @field deletestats boolean?
--- @field codefromstrings boolean?
--- @field includeuntestedfiles boolean|table?

local debug = require('debug')
local raw_os_exit = os.exit

--- @return table
local new_anchor = newproxy or function()
  return {}
end -- luacheck: compat

--- Returns an anchor that runs fn when collected.
--- @param fn fun(anchor?: table)
--- @return table
local function on_exit_wrap(fn)
  local anchor = new_anchor(false)
  debug.setmetatable(anchor, { __gc = fn })
  return anchor
end

--- @type table<string, luacov.file_stats>
M.data = {}
M.paused = true
M.initialized = false
M.tick = false

--- @param patterns string[]?
--- @param str string
--- @param on_empty boolean?
--- @return boolean
local function match_any(patterns, str, on_empty)
  if not patterns or not patterns[1] then
    return not not on_empty
  end

  for _, pattern in ipairs(patterns) do
    if string.match(str, pattern) then
      return true
    end
  end

  return false
end

--- Uses LuaCov's configuration to check if a file is included for
--- coverage data collection.
--- @param filename string
--- @return boolean
function M.file_included(filename)
  -- Normalize file names before using patterns.
  filename = string.gsub(filename, '\\', '/')
  filename = string.gsub(filename, '%.lua$', '')

  -- If include list is empty, everything is included by default.
  -- If exclude list is empty, nothing is excluded by default.
  return match_any(M.configuration.include, filename, true)
    and not match_any(M.configuration.exclude, filename, false)
end

--- Adds stats to an existing file stats table.
--- @param old_stats luacov.file_stats stats to be updated.
--- @param extra_stats luacov.file_stats another stats table, will be broken during update.
function M.update_stats(old_stats, extra_stats)
  old_stats.max = math.max(old_stats.max, extra_stats.max)

  -- Remove string keys so that they do not appear when iterating
  -- over 'extra_stats'.
  extra_stats.max = nil
  extra_stats.max_hits = nil

  for line_nr, run_nr in pairs(extra_stats) do
    old_stats[line_nr] = (old_stats[line_nr] or 0) + run_nr
    old_stats.max_hits = math.max(old_stats.max_hits, old_stats[line_nr])
  end
end

--- Adds accumulated stats to existing stats file or writes a new one, then resets data.
function M.save_stats()
  local statsfile = assert(M.configuration.statsfile, 'statsfile is required')
  local loaded = stats.load(statsfile) or {}

  for name, file_data in pairs(M.data) do
    if loaded[name] then
      M.update_stats(loaded[name], file_data)
    else
      loaded[name] = file_data
    end
  end

  stats.save(statsfile, loaded)
  M.data = {}
end

local cluacov_ok = pcall(require, 'cluacov.version')

--- Debug hook set by LuaCov.
--- Acknowledges that a line is executed, but does nothing
--- if called manually before coverage gathering is started.
--- The optional 'level' argument defaults to 2. Increase it if this function is
--- called manually from another debug hook.
--- @usage
--- local function custom_hook(_, line)
---    runner.debug_hook(_, line, 3)
---    extra_processing(line)
--- end
--- @function debug_hook
--- @type fun(event: string, line_nr: integer, level?: integer)
M.debug_hook = require(cluacov_ok and 'cluacov.hook' or 'luacov.hook').new(M)

--- Runs the reporter specified in configuration.
--- @param configuration? string|table if string, filename of config file (used to call `load_config`).
--- If table then config table (see file `luacov.default.lua` for an example).
--- If `configuration.reporter` is not set, runs the default reporter;
--- otherwise, it must be a module name in 'luacov.reporter' namespace.
--- The module must contain 'report' function, which is called without arguments.
function M.run_report(configuration)
  configuration = M.load_config(configuration)
  local reporter = 'luacov.reporter'

  if configuration.reporter then
    reporter = reporter .. '.' .. configuration.reporter
  end

  require(reporter).report()
end

local on_exit_run_once = false

local function on_exit()
  -- Lua >= 5.2 could call __gc when user call os.exit
  -- so this method could be called twice
  if on_exit_run_once then
    return
  end
  on_exit_run_once = true
  -- disable hooks before aggregating stats
  debug.sethook(nil)
  M.save_stats()

  if M.configuration.runreport then
    M.run_report(M.configuration)
  end
end

local dir_sep = package.config:sub(1, 1)
local wildcard_expansion = '[^/]+'
--- @class luacov.ModuleMappings
--- @field patterns string[]
--- @field filenames string[]

if not dir_sep:find('[/\\]') then
  dir_sep = '/'
end

--- @param ch string
--- @return string
local function escape_module_punctuation(ch)
  if ch == '.' then
    return '/'
  elseif ch == '*' then
    return wildcard_expansion
  else
    return '%' .. ch
  end
end

--- @param name string
--- @return string[]
local function reversed_module_name_parts(name)
  local parts = {}

  for part in name:gmatch('[^%.]+') do
    table.insert(parts, 1, part)
  end

  return parts
end

--- This function is used for sorting module names.
--- More specific names should come first.
--- E.g. rule for 'foo.bar' should override rule for 'foo.*',
--- rule for 'foo.*' should override rule for 'foo.*.*',
--- and rule for 'a.b' should override rule for 'b'.
--- To be more precise, because names become patterns that are matched
--- from the end, the name that has the first (from the end) literal part
--- (and the corresponding part for the other name is not literal)
--- is considered more specific.
--- @param name1 string
--- @param name2 string
--- @return boolean
local function compare_names(name1, name2)
  local parts1 = reversed_module_name_parts(name1)
  local parts2 = reversed_module_name_parts(name2)

  for i = 1, math.max(#parts1, #parts2) do
    if not parts1[i] then
      return false
    end
    if not parts2[i] then
      return true
    end

    local is_literal1 = not parts1[i]:find('%*')
    local is_literal2 = not parts2[i]:find('%*')

    if is_literal1 ~= is_literal2 then
      return is_literal1
    end
  end

  -- Names are at the same level of specificness,
  -- fall back to lexicographical comparison.
  return name1 < name2
end

--- Sets runner.modules using runner.configuration.modules.
--- Produces arrays of module patterns and filenames and sets
--- them as runner.modules.patterns and runner.modules.filenames.
--- Appends these patterns to the include list.
local function acknowledge_modules()
  M.modules = { patterns = {}, filenames = {} } --- @type luacov.ModuleMappings

  if not M.configuration.modules then
    return
  end

  if not M.configuration.include then
    M.configuration.include = {}
  end

  local names = {}

  for name in pairs(M.configuration.modules) do
    table.insert(names, name)
  end

  table.sort(names, compare_names)

  for _, name in ipairs(names) do
    local pattern = name:gsub('%p', escape_module_punctuation) .. '$'
    local filename = M.configuration.modules[name]:gsub('[/\\]', dir_sep)
    table.insert(M.modules.patterns, pattern)
    table.insert(M.configuration.include, pattern)
    table.insert(M.modules.filenames, filename)

    if filename:match('init%.lua$') then
      pattern = pattern:gsub('$$', '/init$')
      table.insert(M.modules.patterns, pattern)
      table.insert(M.configuration.include, pattern)
      table.insert(M.modules.filenames, filename)
    end
  end
end

--- Returns real name for a source file name
--- using `luacov.defaults.modules` option.
--- @param filename string name of the file.
--- @return string
function M.real_name(filename)
  local orig_filename = filename
  -- Normalize file names before using patterns.
  filename = filename:gsub('\\', '/'):gsub('%.lua$', '')

  for i, pattern in ipairs(M.modules.patterns) do
    local match = filename:match(pattern)

    if match then
      local new_filename = M.modules.filenames[i]
      assert(new_filename, 'missing module filename mapping')

      if pattern:find(wildcard_expansion, 1, true) then
        -- Given a prefix directory, join it
        -- with matched part of source file name.
        if not new_filename:match('/$') then
          new_filename = new_filename .. '/'
        end

        new_filename = new_filename .. match .. '.lua'
      end

      -- Switch slashes back to native.
      return (new_filename:gsub('^%.[/\\]', ''):gsub('[/\\]', dir_sep))
    end
  end

  return orig_filename
end

-- Always exclude luacov's own files.
local luacov_excludes = {
  'luacov$',
  'luacov/hook$',
  'luacov/reporter$',
  'luacov/reporter/default$',
  'luacov/defaults$',
  'luacov/runner$',
  'luacov/stats$',
  'luacov/util$',
  'cluacov/version$',
}

--- @param path string
--- @return boolean
local function is_absolute(path)
  if path:sub(1, 1) == dir_sep or path:sub(1, 1) == '/' then
    return true
  end

  if dir_sep == '\\' and path:find('^%a:') then
    return true
  end

  return false
end

--- @return string
local function get_cur_dir()
  local cur_dir = vim.uv.cwd() or '.'

  if cur_dir:sub(-1) ~= dir_sep and cur_dir:sub(-1) ~= '/' then
    cur_dir = cur_dir .. dir_sep
  end

  return cur_dir
end

--- @param configuration table<string, any>
local function set_config(configuration)
  assert(configuration ~= nil, 'configuration table is required')
  M.configuration = {} --- @type luacov.Configuration

  for option, default_value in pairs(M.defaults) do
    M.configuration[option] = default_value
  end

  for option, value in pairs(configuration) do
    M.configuration[option] = value
  end

  M.configuration.include = M.configuration.include or {}
  M.configuration.exclude = M.configuration.exclude or {}

  -- Program using LuaCov may change directory during its execution.
  -- Convert path options to absolute paths to use correct paths anyway.
  local cur_dir

  local statsfile = M.configuration.statsfile
  if type(statsfile) == 'string' and not is_absolute(statsfile) then
    cur_dir = cur_dir or get_cur_dir()
    M.configuration.statsfile = cur_dir .. statsfile
  end

  local reportfile = M.configuration.reportfile
  if type(reportfile) == 'string' and not is_absolute(reportfile) then
    cur_dir = cur_dir or get_cur_dir()
    M.configuration.reportfile = cur_dir .. reportfile
  end

  acknowledge_modules()

  for _, patt in ipairs(luacov_excludes) do
    table.insert(M.configuration.exclude, patt)
  end

  M.tick = M.tick or M.configuration.tick
end

--- @param name string
--- @param is_default? boolean
--- @return table<string, any>?
local function load_config_file(name, is_default)
  local conf = setmetatable({}, { __index = _G })

  local ok, ret, error_msg = util.load_config(name, conf)

  if ok then
    if type(ret) == 'table' then
      ---@cast ret table
      for key, value in pairs(ret) do
        if conf[key] == nil then
          conf[key] = value
        end
      end
    end

    return conf
  end

  local error_type = ret

  if error_type == 'read' and is_default then
    return nil
  end

  io.stderr:write(("Error: couldn't %s config file %s: %s\n"):format(error_type, name, error_msg))
  raw_os_exit(1)
end

local default_config_file = os.getenv('LUACOV_CONFIG') or '.luacov'

--- Loads a valid configuration.
--- @param configuration? string|table user provided config (config-table or filename)
--- @return table existing configuration if already set, otherwise loads a new config or defaults.
function M.load_config(configuration)
  if not M.configuration then
    if not configuration then
      -- Nothing provided, load from default location if possible.
      set_config(load_config_file(default_config_file, true) or M.defaults)
    elseif type(configuration) == 'string' then
      local loaded_config = load_config_file(configuration)
      assert(loaded_config, 'Failed to load LuaCov config: ' .. configuration)
      set_config(loaded_config)
    elseif type(configuration) == 'table' then
      set_config(configuration)
    else
      error('Expected filename, config table or nil. Got ' .. type(configuration))
    end
  end

  return M.configuration
end

--- Pauses saving data collected by LuaCov's runner.
--- Allows other processes to write to the same stats file.
--- Data is still collected during pause.
function M.pause()
  M.paused = true
end

--- Resumes saving data collected by LuaCov's runner.
function M.resume()
  M.paused = false
end

local hook_per_thread

-- Determines whether debug hooks are separate for each thread.
--- @return boolean
local function has_hook_per_thread()
  if hook_per_thread == nil then
    local old_hook, old_mask, old_count = debug.gethook()
    local noop = function() end
    debug.sethook(noop, 'l')
    local thread_hook = coroutine.wrap(function()
      return debug.gethook()
    end)()
    hook_per_thread = thread_hook ~= noop
    debug.sethook(old_hook, old_mask, old_count)
  end

  return hook_per_thread
end

--- Wraps a function, enabling coverage gathering in it explicitly.
--- LuaCov gathers coverage using a debug hook, and patches coroutine
--- library to set it on created threads when under standard Lua, where each
--- coroutine has its own hook. If a coroutine is created using Lua C API
--- or before the monkey-patching, this wrapper should be applied to the
--- main function of the coroutine. Under LuaJIT this function is redundant,
--- as there is only one, global debug hook.
--- @param f fun(...: any): any
--- @return fun(...: any): any
--- @usage
--- local coro = coroutine.create(runner.with_luacov(func))
function M.with_luacov(f)
  return function(...)
    if has_hook_per_thread() then
      debug.sethook(M.debug_hook, 'l')
    end

    return f(...)
  end
end

--- Initializes LuaCov runner to start collecting data.
--- @param configuration? string|table if string, filename of config file (used to call `load_config`).
--- If table then config table (see file `luacov.default.lua` for an example)
function M.init(configuration)
  M.configuration = M.load_config(configuration)

  -- metatable trick on filehandle won't work if Lua exits through
  -- os.exit() hence wrap that with exit code as well
  os.exit = function(...) -- luacheck: no global
    on_exit()
    raw_os_exit(...)
  end

  debug.sethook(M.debug_hook, 'l')

  if has_hook_per_thread() then
    -- debug must be set for each coroutine separately
    -- hence wrap coroutine function to set the hook there
    -- as well
    local rawcoroutinecreate = coroutine.create
    coroutine.create = function(...) -- luacheck: no global
      local co = rawcoroutinecreate(...)
      debug.sethook(co, M.debug_hook, 'l')
      return co
    end

    -- Version of assert which handles non-string errors properly.
    local function safeassert(ok, ...)
      if ok then
        return ...
      else
        error(..., 0)
      end
    end

    coroutine.wrap = function(...) -- luacheck: no global
      local co = rawcoroutinecreate(...)
      debug.sethook(co, M.debug_hook, 'l')
      return function(...)
        return safeassert(coroutine.resume(co, ...))
      end
    end
  end

  if not M.tick then
    M.on_exit_trick = on_exit_wrap(on_exit)
  end

  M.initialized = true
  M.paused = false
end

function M.shutdown()
  on_exit()
end

--- Gets the source filename from a function.
--- @param func fun(...: any)
--- @return string?
local function getsourcefile(func)
  assert(type(func) == 'function')
  local d = debug.getinfo(func).source
  if d and d:sub(1, 1) == '@' then
    return d:sub(2)
  end
end

--- Looks for a function inside a table.
--- @param t table
--- @param searched table<any, boolean>
--- @return fun(...: any)?
local function findfunction(t, searched)
  if searched[t] then
    return
  end

  searched[t] = true

  for _, v in pairs(t) do
    if type(v) == 'function' then
      return v
    elseif type(v) == 'table' then
      local func = findfunction(v, searched)
      if func then
        return func
      end
    end
  end
end

--- Gets source filename from a file name, module name, function or table.
--- @param name string|fun(...: any)|table filename, module name, function, or module table
--- @return string
local function getfilename(name)
  if type(name) == 'function' then
    local sourcefile = getsourcefile(name)

    if not sourcefile then
      error('Could not infer source filename')
    end

    return sourcefile
  elseif type(name) == 'table' then
    local func = findfunction(name, {})

    if not func then
      error('Could not find a function within ' .. tostring(name))
    end

    return getfilename(func)
  else
    if type(name) ~= 'string' then
      error('Bad argument: ' .. tostring(name))
    end

    if util.file_exists(name) then
      return name
    end

    local success, result = pcall(require, name)

    if not success then
      error("Module/file '" .. name .. "' was not found")
    end

    if type(result) == 'table' then
      --- @cast result table
      return getfilename(result)
    end

    if type(result) == 'function' then
      --- @cast result fun(...: any)
      return getfilename(result)
    end

    error("Module '" .. name .. "' did not return a result to lookup its file name")
  end
end

--- Escapes magic pattern characters, removes .lua extension
--- and replaces dir seps by '/'.
--- @param name string
--- @return string
local function escapefilename(name)
  local escaped = name:gsub('%.lua$', ''):gsub('[%%%^%$%.%(%)%[%]%+%*%-%?]', '%%%0'):gsub('\\', '/')
  return escaped
end

--- @param name string|fun(...: any)|table
--- @param list string[]
--- @return string
local function addfiletolist(name, list)
  local f = '^' .. escapefilename(getfilename(name)) .. '$'
  table.insert(list, f)
  return f
end

--- @param name string|fun(...: any)|table
--- @param level? boolean
--- @param list string[]
--- @return string, string
local function addtreetolist(name, level, list)
  local f = escapefilename(getfilename(name))

  if level or f:match('/init$') then
    -- chop the last backslash and everything after it
    f = f:match('^(.*)/') or f
  end

  local t = '^' .. f .. '/' -- the tree behind the file
  f = '^' .. f .. '$' -- the file
  table.insert(list, f)
  table.insert(list, t)
  return f, t
end

--- Returns a pcall result, with the initial 'true' value removed
--- and 'false' replaced with nil.
--- @param ok boolean
--- @param ... any
--- @return any ...
local function checkresult(ok, ...)
  if ok then
    return ... -- success, strip 'true' value
  else
    return nil, ... -- failure; nil + error
  end
end

--- Adds a file to the exclude list (see `luacov.defaults`).
--- If passed a function, then through debuginfo the source filename is collected. In case of a table
--- it will recursively search the table for a function, which is then resolved to a filename through debuginfo.
--- If the parameter is a string, it will first check if a file by that name exists. If it doesn't exist
--- it will call `require(name)` to load a module by that name, and the result of require (function or
--- table expected) is used as described above to get the sourcefile.
--- @param name string|fun(...: any)|table
--- * string;   literal filename,
--- * string;   modulename as passed to require(),
--- * function; where containing file is looked up,
--- * table;    module table where containing file is looked up
--- @return string? pattern the pattern as added to the list
--- @return any? err error detail when pattern is nil
function M.excludefile(name)
  local exclude = assert(M.configuration.exclude, 'exclude configuration missing')
  return checkresult(pcall(addfiletolist, name, exclude))
end

--- Adds a file to the include list (see `luacov.defaults`).
--- @param name string|fun(...: any)|table see `excludefile`
--- @return string? pattern the pattern as added to the list
--- @return any? err error detail when pattern is nil
function M.includefile(name)
  local include = assert(M.configuration.include, 'include configuration missing')
  return checkresult(pcall(addfiletolist, name, include))
end

--- Adds a tree to the exclude list (see `luacov.defaults`).
--- If `name = 'luacov'` and `level = nil` then
--- module 'luacov' (luacov.lua) and the tree 'luacov' (containing `luacov/runner.lua` etc.) is excluded.
--- If `name = 'pl.path'` and `level = true` then
--- module 'pl' (pl.lua) and the tree 'pl' (containing `pl/path.lua` etc.) is excluded.
--- NOTE: in case of an 'init.lua' file, the 'level' parameter will always be set
--- @param name string|fun(...: any)|table see `excludefile`
--- @param level? boolean if truthy then one level up is added, including the tree
--- @return string? file_pattern
--- @return string? tree_pattern_or_err tree pattern on success or error detail when file_pattern is nil
function M.excludetree(name, level)
  local exclude = assert(M.configuration.exclude, 'exclude configuration missing')
  return checkresult(pcall(addtreetolist, name, level, exclude))
end

--- Adds a tree to the include list (see `luacov.defaults`).
--- @param name string|fun(...: any)|table see `excludefile`
--- @param level? boolean see `includetree`
--- @return string? file_pattern
--- @return string? tree_pattern_or_err tree pattern on success or error detail when file_pattern is nil
function M.includetree(name, level)
  local include = assert(M.configuration.include, 'include configuration missing')
  return checkresult(pcall(addtreetolist, name, level, include))
end

setmetatable(M, {
  __call = function(_, configfile)
    M.init(configfile)
  end,
})

return M
