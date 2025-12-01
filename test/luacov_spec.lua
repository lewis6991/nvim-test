local helpers = require('nvim-test.helpers')
local eq = helpers.eq

local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs

local util = require('luacov.util')
local stats = require('luacov.stats')

local function tmp_dir()
  local template = fs.joinpath(uv.os_tmpdir(), 'luacov-spec-XXXXXX')
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
    eq('bar', conf.foo)

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
    local payload = {
      ['lua/foo.lua'] = {
        max = 3,
        max_hits = 5,
        [1] = 5,
        [2] = 0,
        [3] = 1,
      },
    }

    stats.save(statsfile, payload)

    local old_vim = _G.vim
    _G.vim = nil
    local loaded = stats.load(statsfile)
    _G.vim = old_vim

    eq(payload['lua/foo.lua'].max, loaded['lua/foo.lua'].max)
    eq(payload['lua/foo.lua'].max_hits, loaded['lua/foo.lua'].max_hits)
    eq(payload['lua/foo.lua'][1], loaded['lua/foo.lua'][1])
    eq(payload['lua/foo.lua'][3], loaded['lua/foo.lua'][3])
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
  local project_runner

  local function load_project_config()
    local config = dofile('.luacov')
    project_runner.load_config(config)
  end

  before_each(function()
    project_runner = dofile('lua/luacov/runner.lua')
  end)

  after_each(function()
    project_runner = nil
  end)

  it('keeps stats and reports in the project root', function()
    load_project_config()
    eq(
      fs.normalize(fs.joinpath(uv.cwd(), 'luacov.stats.out')),
      project_runner.configuration.statsfile
    )
    eq(
      fs.normalize(fs.joinpath(uv.cwd(), 'luacov.report.out')),
      project_runner.configuration.reportfile
    )
  end)

  it('includes nvim-test sources for coverage', function()
    load_project_config()
    assert(project_runner.file_included('lua/nvim-test/helpers.lua'))
  end)

  it('excludes tests and examples from coverage', function()
    load_project_config()
    assert.is_false(project_runner.file_included('test/helpers_spec.lua'))
    assert.is_false(project_runner.file_included('example/lua/example.lua'))
  end)
end)
