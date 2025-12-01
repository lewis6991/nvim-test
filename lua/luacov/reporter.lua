------------------------
-- Report module, will transform statistics file into a report.
-- @class module
-- @name luacov.reporter
local reporter = {}

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local LineScanner = require('luacov.linescanner')
local luacov = require('luacov.runner')
local util = require('luacov.util')

----------------------------------------------------------------
local dir_sep = package.config:sub(1, 1)
if not dir_sep:find('[/\\]') then
  dir_sep = '/'
end

--- returns all files inside dir
--- @param dir string directory to be listed
--- @return fun(): string, { mode: string? } iterator yielding file info
local function dirtree(dir)
  assert(dir and dir ~= '', 'Please pass directory parameter')
  if dir:sub(-1):match('[/\\]') then
    dir = string.sub(dir, 1, -2)
  end

  dir = dir:gsub('[/\\]', dir_sep)

  --- @async
  local function scan(directory)
    local req = uv.fs_scandir(directory)
    if not req then
      return
    end

    while true do
      local entry, kind = uv.fs_scandir_next(req)
      if not entry then
        break
      end

      local full_path = directory .. dir_sep .. entry
      local attr = { mode = kind or 'file' }
      coroutine.yield(full_path, attr)
      if attr.mode == 'directory' then
        scan(full_path)
      end
    end
  end

  return coroutine.wrap(function()
    scan(dir)
  end)
end

---@class luacov.ReportWriter
---@field write fun(self, ...: string): integer
---@field close fun(self)

local function open_writer(path)
  local fd, err = uv.fs_open(path, 'w', 420)
  if not fd then
    return nil, err
  end

  local writer = {}

  function writer.write(_, ...)
    local chunk = table.concat({ ... })
    local bytes, werr = uv.fs_write(fd, chunk, -1)
    if not bytes then
      error(werr)
    end
    return bytes
  end

  function writer.close(_)
    if fd then
      uv.fs_close(fd)
      fd = nil
    end
  end

  ---@cast writer luacov.ReportWriter
  return writer
end

----------------------------------------------------------------
--- checks if string 'filename' has pattern 'pattern'
--- @param filename string
--- @param pattern string
--- @return boolean
local function fileMatches(filename, pattern)
  return string.find(filename, pattern) ~= nil
end

----------------------------------------------------------------
--- Basic reporter class stub.
-- Implements 'new', 'run' and 'close' methods required by `report`.
-- Provides some helper methods and stubs to be overridden by child classes.
-- @usage
-- local MyReporter = setmetatable({}, ReporterBase)
-- MyReporter.__index = MyReporter
-- function MyReporter:on_hit_line(...)
--    self:write(("File %s: hit line %s %d times"):format(...))
-- end
-- @type ReporterBase
---@class ReporterBase
---@field protected _out luacov.ReportWriter?
---@field protected _cfg table
---@field protected _data table<string, any>
---@field protected _files string[]
---@field protected _mhit integer
---@field protected _private any
local ReporterBase = {}
do
  ReporterBase.__index = ReporterBase

  ---@param handler ReporterBase
  ---@param hook_name string
  ---@param ... any
  local function call_hook(handler, hook_name, ...)
    local method = handler[hook_name]
    if type(method) == 'function' then
      method(handler, ...)
    end
  end

  function ReporterBase:new(conf)
    local stats = require('luacov.stats')
    local data = stats.load(conf.statsfile)

    if not data then
      return nil, 'Could not load stats file ' .. conf.statsfile .. '.'
    end

    local files = {}
    local filtered_data = {}
    local max_hits = 0

    -- Several original paths can map to one real path,
    -- their stats should be merged in this case.
    for filename, file_stats in pairs(data) do
      if luacov.file_included(filename) then
        filename = luacov.real_name(filename)

        if filtered_data[filename] then
          luacov.update_stats(filtered_data[filename], file_stats)
        else
          table.insert(files, filename)
          filtered_data[filename] = file_stats
        end

        max_hits = math.max(max_hits, filtered_data[filename].max_hits)
      end
    end

    -- including files without tests
    -- only .lua files
    if conf.includeuntestedfiles then
      local function add_empty_file_coverage_data(file_path)
        -- Leading "./" must be trimmed from the file paths because the paths of tested
        -- files do not have a leading "./" either
        if file_path:match('^%.[/\\]') then
          file_path = file_path:sub(3)
        end

        if luacov.file_included(file_path) then
          local file_stats = {
            max = 0,
            max_hits = 0,
          }

          local filename = luacov.real_name(file_path)

          if not filtered_data[filename] then
            table.insert(files, filename)
            filtered_data[filename] = file_stats
          end
        end
      end

      local function add_empty_dir_coverage_data(directory_path)
        for filename, attr in dirtree(directory_path) do
          if attr.mode == 'file' and fileMatches(filename, '.%.lua$') then
            add_empty_file_coverage_data(filename)
          end
        end
      end

      if conf.includeuntestedfiles == true then
        add_empty_dir_coverage_data('.' .. dir_sep)
      elseif type(conf.includeuntestedfiles) == 'table' and conf.includeuntestedfiles[1] then
        for _, include_path in ipairs(conf.includeuntestedfiles) do
          if fileMatches(include_path, '.%.lua$') then
            add_empty_file_coverage_data(include_path)
          else
            add_empty_dir_coverage_data(include_path)
          end
        end
      end
    end

    table.sort(files)

    local out, err = open_writer(conf.reportfile)
    if not out then
      return nil, err
    end

    local o = setmetatable({
      _out = out,
      _cfg = conf,
      _data = filtered_data,
      _files = files,
      _mhit = max_hits,
    }, self)

    return o
  end

  --- Returns configuration table.
  -- @see luacov.defaults
  function ReporterBase:config()
    return self._cfg
  end

  --- Returns maximum number of hits per line in all coverage data.
  function ReporterBase:max_hits()
    return self._mhit
  end

  --- Writes strings to report file.
  -- @param ... strings.
  function ReporterBase:write(...)
    local out = assert(self._out, 'report output is not initialized')
    return out:write(...)
  end

  function ReporterBase:close()
    local out = self._out
    if not out then
      return
    end
    out:close()
    self._out = nil
    self._private = nil
  end

  --- Returns array of filenames to be reported.
  function ReporterBase:files()
    return self._files
  end

  --- Returns coverage data for a file.
  -- @param filename name of the file.
  -- @see luacov.stats.load
  function ReporterBase:stats(filename)
    return self._data[filename]
  end

  local cluacov_ok = pcall(require, 'cluacov.version')
  local deepactivelines

  if cluacov_ok then
    deepactivelines = require('cluacov.deepactivelines')
  end

  function ReporterBase:_run_file(filename)
    local file, open_err = io.open(filename)

    if not file then
      local err_msg = util.unprefix(tostring(open_err or ''), filename .. ': ')
      call_hook(self, 'on_file_error', filename, 'open', err_msg)
      return
    end

    local active_lines = {}

    if cluacov_ok then
      local src, read_err = file:read('*a')

      if not src then
        call_hook(
          self,
          'on_file_error',
          filename,
          'read',
          tostring(read_err or 'unknown read error')
        )
        return
      end

      src = src:gsub('^#![^\n]*', '')
      local func, load_err = util.load_string(src, nil, '@file')

      if not func then
        local load_msg = util.unprefix(tostring(load_err or ''), 'file:')
        call_hook(self, 'on_file_error', filename, 'load', 'line ' .. load_msg)
        return
      end

      local deep_lines = deepactivelines
      if not deep_lines then
        error('deepactivelines module missing')
      end
      active_lines = deep_lines.get(func) or {}
      file:seek('set', 0)
    end

    call_hook(self, 'on_new_file', filename)
    local file_hits, file_miss = 0, 0
    local filedata = self:stats(filename)

    local line_nr = 1
    local scanner = LineScanner:new()

    while true do
      local line = file:read('*l')
      if not line then
        break
      end

      local always_excluded, excluded_when_not_hit = scanner:consume(line)
      local hits = filedata[line_nr] or 0
      local included = not always_excluded and (not excluded_when_not_hit or hits ~= 0)

      if cluacov_ok then
        included = included and active_lines[line_nr]
      end

      if included then
        if hits == 0 then
          call_hook(self, 'on_mis_line', filename, line_nr, line)
          file_miss = file_miss + 1
        else
          call_hook(self, 'on_hit_line', filename, line_nr, line, hits)
          file_hits = file_hits + 1
        end
      else
        call_hook(self, 'on_empty_line', filename, line_nr, line)
      end

      line_nr = line_nr + 1
    end

    file:close()
    call_hook(self, 'on_end_file', filename, file_hits, file_miss)
  end

  function ReporterBase:run()
    call_hook(self, 'on_start')

    for _, filename in ipairs(self:files()) do
      self:_run_file(filename)
    end

    call_hook(self, 'on_end')
  end
end
--- @section end
----------------------------------------------------------------

----------------------------------------------------------------
local DefaultReporter = setmetatable({}, { __index = ReporterBase })
do
  DefaultReporter.__index = DefaultReporter

  function DefaultReporter:on_start()
    local most_hits = self:max_hits()
    local most_hits_length = #('%d'):format(most_hits)

    self._summary = {}
    self._empty_format = (' '):rep(most_hits_length + 1)
    self._zero_format = ('*'):rep(most_hits_length) .. '0'
    self._count_format = ('%% %dd'):format(most_hits_length + 1)
    self._printed_first_header = false
  end

  function DefaultReporter:on_new_file(filename)
    self:write(('='):rep(78), '\n')
    self:write(filename, '\n')
    self:write(('='):rep(78), '\n')
  end

  function DefaultReporter.on_file_error(_self, filename, error_type, message)
    io.stderr:write(("Couldn't %s %s: %s\n"):format(error_type, filename, message))
  end

  function DefaultReporter:on_empty_line(_, _, line)
    if line == '' then
      self:write('\n')
    else
      self:write(self._empty_format, ' ', line, '\n')
    end
  end

  function DefaultReporter:on_mis_line(_, _, line)
    self:write(self._zero_format, ' ', line, '\n')
  end

  function DefaultReporter:on_hit_line(_, _, line, hits)
    self:write(self._count_format:format(hits), ' ', line, '\n')
  end

  function DefaultReporter:on_end_file(filename, hits, miss)
    self._summary[filename] = { hits = hits, miss = miss }
    self:write('\n')
  end

  local function coverage_to_string(hits, missed)
    local total = hits + missed

    if total == 0 then
      total = 1
    end

    return ('%.2f%%'):format(hits / total * 100.0)
  end

  function DefaultReporter:on_end()
    self:write(('='):rep(78), '\n')
    self:write('Summary\n')
    self:write(('='):rep(78), '\n')
    self:write('\n')

    local lines = { { 'File', 'Hits', 'Missed', 'Coverage' } }
    local total_hits, total_missed = 0, 0

    for _, filename in ipairs(self:files()) do
      local summary = self._summary[filename]

      if summary then
        local hits, missed = summary.hits, summary.miss

        table.insert(lines, {
          filename,
          tostring(summary.hits),
          tostring(summary.miss),
          coverage_to_string(hits, missed),
        })

        total_hits = total_hits + hits
        total_missed = total_missed + missed
      end
    end

    table.insert(lines, {
      'Total',
      tostring(total_hits),
      tostring(total_missed),
      coverage_to_string(total_hits, total_missed),
    })

    local max_column_lengths = {}

    for _, line in ipairs(lines) do
      for column_nr, column in ipairs(line) do
        local column_length = #column
        ---@cast column_length integer
        local current = max_column_lengths[column_nr] or -1
        if column_length > current then
          max_column_lengths[column_nr] = column_length
        end
      end
    end

    local table_width = #max_column_lengths - 1 --- @type integer

    for _, column_length in ipairs(max_column_lengths) do
      ---@cast column_length integer
      table_width = table_width + column_length
    end

    for line_nr, line in ipairs(lines) do
      if line_nr == #lines or line_nr == 2 then
        self:write(('-'):rep(table_width), '\n')
      end

      for column_nr, column in ipairs(line) do
        self:write(column)

        if column_nr == #line then
          self:write('\n')
        else
          self:write((' '):rep(max_column_lengths[column_nr] - #column + 1))
        end
      end
    end
  end
end
----------------------------------------------------------------

--- Runs the report generator.
-- To load a config, use `luacov.runner.load_config` first.
-- @param reporter_class? custom reporter class. Will be
-- instantiated using 'new' method with configuration
-- (see `luacov.defaults`) as the argument. It should
-- return nil + error if something went wrong.
-- After acquiring a reporter object its 'run' and 'close'
-- methods will be called.
-- The easiest way to implement a custom reporter class is to
-- extend `ReporterBase`.
function reporter.report(reporter_class)
  local configuration = luacov.load_config()

  reporter_class = reporter_class or DefaultReporter

  local rep, err = reporter_class:new(configuration)

  if not rep then
    print(err)
    print('Run your Lua program with -lluacov and then rerun luacov.')
    os.exit(1)
  end

  rep:run()

  rep:close()

  if configuration.deletestats then
    os.remove(configuration.statsfile)
  end
end

reporter.ReporterBase = ReporterBase

reporter.DefaultReporter = DefaultReporter

return reporter
