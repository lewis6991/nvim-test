local helpers = require('nvim-test.helpers')
local eq = helpers.eq

local uv = vim.uv
local fs = vim.fs

local util = require('luacov.util')
local stats = require('luacov.stats')

---@param value string?
---@param message string
---@return string
local function expect_string(value, message)
  if not value then
    error(message)
  end
  return value
end

local function tmp_dir()
  local os_tmp = assert(uv.os_tmpdir(), 'uv.os_tmpdir() unavailable')
  local template = fs.joinpath(os_tmp, 'luacov-spec-XXXXXX')
  local dir = assert(uv.fs_mkdtemp(template))
  return fs.normalize(dir)
end

local function write_file(path, contents)
  local fd = assert(uv.fs_open(path, 'w', 420))
  assert(uv.fs_write(fd, contents, -1))
  uv.fs_close(fd)
end

describe('luacov.util', function()
  it('loads lua config files and reports errors', function()
    local dir = tmp_dir()
    local config_path = fs.joinpath(dir, 'config.lua')
    write_file(config_path, 'return { foo = "bar" }')

    local ok, conf = util.load_config(config_path, {})
    eq(true, ok)
    assert(conf, 'expected luacov config')
    assert(type(conf) == 'table', 'config must be a table')
    local foo = conf.foo
    assert(type(foo) == 'string', 'foo must be a string')
    eq('bar', foo)

    local missing = fs.joinpath(dir, 'missing.lua')
    local fail_ok, kind = util.load_config(missing, {})
    eq(nil, fail_ok)
    eq('read', kind)
  end)

  it('checks file existence', function()
    local dir = tmp_dir()
    local file = fs.joinpath(dir, 'file.txt')
    write_file(file, 'data')
    eq(true, util.file_exists(file))
    local missing = fs.joinpath(dir, 'missing.txt')
    eq(false, util.file_exists(missing))
  end)
end)

describe('luacov.stats', function()
  it('serializes stats to disk and reloads them', function()
    local dir = tmp_dir()
    local statsfile = fs.joinpath(dir, 'stats.out')
    ---@type luacov.file_stats
    local foo_stats = {
      max = 3,
      max_hits = 5,
      [1] = 5,
      [2] = 0,
      [3] = 1,
    }
    ---@type table<string, luacov.file_stats>
    local payload = {
      ['lua/foo.lua'] = foo_stats,
    }

    stats.save(statsfile, payload)

    local old_vim = rawget(_G, 'vim')
    rawset(_G, 'vim', nil)
    local loaded = stats.load(statsfile)
    rawset(_G, 'vim', old_vim)
    assert(loaded, 'expected stats.load to succeed')

    local reloaded_stats = loaded['lua/foo.lua']

    eq(foo_stats.max, reloaded_stats.max)
    eq(foo_stats.max_hits, reloaded_stats.max_hits)
    eq(foo_stats[1], reloaded_stats[1])
    eq(foo_stats[3], reloaded_stats[3])
  end)
end)

describe('luacov.runner helpers', function()
  it('applies include/exclude rules', function()
    local runner_mod = dofile('lua/luacov/runner.lua')
    runner_mod.configuration = {
      include = { 'lua/src' },
      exclude = { 'lua/src/excluded' },
    }
    assert(runner_mod.file_included('lua/src/module.lua'))
    assert(not runner_mod.file_included('lua/src/excluded/module.lua'))
  end)

  it('registers module mappings for real_name', function()
    local runner_mod = dofile('lua/luacov/runner.lua')
    runner_mod.configuration = nil

    local config = {
      include = {},
      exclude = {},
      modules = {
        ['demo.module'] = 'lua/demo/module.lua',
      },
      statsfile = 'luacov.stats.out',
      reportfile = 'luacov.report.out',
    }

    runner_mod.load_config(config)

    local expected = fs.normalize('lua/demo/module.lua')
    local resolved = runner_mod.real_name('demo/module.lua')
    assert.are.equal(expected, fs.normalize(resolved))
  end)

  it('adds include and exclude patterns via helpers', function()
    local runner_mod = dofile('lua/luacov/runner.lua')
    runner_mod.configuration = {
      include = {},
      exclude = {},
    }

    local exclude_pattern = runner_mod.excludefile('lua/luacov/runner.lua')
    assert.are.equal('^lua/luacov/runner$', exclude_pattern)
    assert.are.same({ exclude_pattern }, runner_mod.configuration.exclude)

    local include_pattern = runner_mod.includefile('lua/luacov/util.lua')
    assert.are.equal('^lua/luacov/util$', include_pattern)
    assert.are.same({ include_pattern }, runner_mod.configuration.include)
  end)
end)

describe('project .luacov configuration', function()
  ---@type luacov.runner?
  local project_runner

  local function load_project_config()
    local runner = assert(project_runner, 'project runner not initialized')
    local config = dofile('.luacov')
    runner.load_config(config)
    return runner
  end

  before_each(function()
    local runner = dofile('lua/luacov/runner.lua')
    ---@cast runner luacov.runner
    project_runner = runner
  end)

  after_each(function()
    project_runner = nil
  end)

  it('keeps stats and reports in the project root', function()
    local runner = load_project_config()
    local config = assert(runner.configuration, 'configuration unavailable')
    local statsfile_path = expect_string(config.statsfile, 'statsfile not configured')
    ---@cast statsfile_path string
    ---@diagnostic disable-next-line: param-type-mismatch
    assert.are.equal(fs.normalize(fs.joinpath(uv.cwd(), 'luacov.stats.out')), statsfile_path)
    local reportfile_path = expect_string(config.reportfile, 'reportfile not configured')
    ---@cast reportfile_path string
    ---@diagnostic disable-next-line: param-type-mismatch
    assert.are.equal(fs.normalize(fs.joinpath(uv.cwd(), 'luacov.report.out')), reportfile_path)
  end)

  it('includes nvim-test sources for coverage', function()
    local runner = load_project_config()
    assert(runner.file_included('lua/nvim-test/helpers.lua'))
  end)

  it('excludes tests and examples from coverage', function()
    local runner = load_project_config()
    assert.is_false(runner.file_included('test/helpers_spec.lua'))
    assert.is_false(runner.file_included('example/lua/example.lua'))
  end)
end)
