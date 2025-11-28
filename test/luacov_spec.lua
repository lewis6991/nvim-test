local helpers = require('nvim-test.helpers')
local eq = helpers.eq

local uv = vim.uv or vim.loop
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
    local loaded = stats.load(statsfile)
    eq(payload['lua/foo.lua'].max, loaded['lua/foo.lua'].max)
    eq(payload['lua/foo.lua'].max_hits, loaded['lua/foo.lua'].max_hits)
    eq(payload['lua/foo.lua'][1], loaded['lua/foo.lua'][1])
    eq(payload['lua/foo.lua'][3], loaded['lua/foo.lua'][3])
  end)
end)
