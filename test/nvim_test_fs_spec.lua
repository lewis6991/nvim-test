local helpers = require('nvim-test.helpers')
local eq = helpers.eq

local fs_util = require('nvim-test.util.fs')
local uv = assert(vim and vim.uv, 'nvim-test requires vim.uv')
local fs = vim.fs

local function rm_rf(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end
  if stat.type == 'directory' then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        rm_rf(fs.joinpath(path, name))
      end
    end
    uv.fs_rmdir(path)
  else
    uv.fs_unlink(path)
  end
end

describe('nvim-test.util.fs', function()
  local tmpdir

  local function tmpfile(name)
    return fs.joinpath(tmpdir, name)
  end

  before_each(function()
    local template = fs.joinpath(uv.os_tmpdir(), 'nvim-test-fs-XXXXXX')
    tmpdir = assert(uv.fs_mkdtemp(template))
  end)

  after_each(function()
    if tmpdir then
      rm_rf(tmpdir)
      tmpdir = nil
    end
  end)

  it('read_lines returns nil for missing files', function()
    local missing = select(1, fs_util.read_lines(tmpfile('missing.txt')))
    assert.is_nil(missing)
  end)

  it('round-trips text with blank lines', function()
    local file = tmpfile('sample.txt')
    fs_util.write_lines(file, { 'alpha', '', 'gamma' })

    local lines = assert(fs_util.read_lines(file))
    eq({ 'alpha', '', 'gamma' }, lines)
  end)

  it('appends to existing files without clobbering content', function()
    local file = tmpfile('append.txt')
    fs_util.write_lines(file, { 'alpha' })
    fs_util.append_lines(file, { 'beta', 'gamma' })

    local lines = assert(fs_util.read_lines(file))
    eq({ 'alpha', 'beta', 'gamma' }, lines)
  end)
end)
