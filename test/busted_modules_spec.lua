local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs

local test_file_loader_factory = require('busted.modules.test_file_loader')
local fixtures = require('busted.fixtures')

local function mktempdir()
  local template = fs.joinpath(uv.os_tmpdir(), 'nvim-test-XXXXXX')
  local dir = uv.fs_mkdtemp(template)
  assert(dir, 'failed to create temp directory')
  return fs.normalize(dir)
end

local function write_file(root, rel, content)
  local full = fs.joinpath(root, rel)
  local parent = fs.dirname(full)
  local function ensure(dir)
    if not dir or dir == '' then
      return
    end
    local stat = uv.fs_stat(dir)
    if stat and stat.type == 'directory' then
      return
    end
    ensure(fs.dirname(dir))
    uv.fs_mkdir(dir, 493)
  end
  ensure(parent)
  local fd = assert(uv.fs_open(full, 'w', 420))
  assert(uv.fs_write(fd, content, -1))
  uv.fs_close(fd)
end

local function rm_rf(path)
  local iter = uv.fs_scandir(path)
  if iter then
    while true do
      local name, type = uv.fs_scandir_next(iter)
      if not name then
        break
      end
      local full = fs.joinpath(path, name)
      if type == 'directory' then
        rm_rf(full)
      else
        uv.fs_unlink(full)
      end
    end
  end
  uv.fs_rmdir(path)
end

describe('busted.modules.test_file_loader', function()
  local tmp
  local loader
  local published
  local stub_busted

  before_each(function()
    tmp = mktempdir()
    write_file(tmp, 'alpha_spec.lua', 'return function() end')
    write_file(tmp, 'nested/beta_spec.lua', 'return function() end')
    write_file(tmp, 'skip_this_spec.lua', 'return function() end')
    write_file(tmp, 'helper.lua', 'return function() end')

    published = {}
    stub_busted = {
      executors = {
        file = function(name)
          table.insert(published, name)
        end,
      },
      publish = function(subjects, element, _, message)
        table.insert(published, { subjects = subjects, element = element, message = message })
      end,
    }

    loader = test_file_loader_factory(stub_busted, { 'lua' })
  end)

  after_each(function()
    if tmp then
      rm_rf(tmp)
      tmp = nil
    end
  end)

  it('collects spec files recursively and honors excludes', function()
    local results = loader({ tmp }, { '_spec' }, {
      recursive = true,
      excludes = { 'skip_this' },
    })

    table.sort(results)
    table.sort(published)
    local expected = {
      fs.joinpath(tmp, 'alpha_spec.lua'),
      fs.joinpath(tmp, 'nested/beta_spec.lua'),
    }

    assert.are.same(expected, results)
    assert.are.same(expected, published)
  end)

  it('returns a single file when root is a file path', function()
    local root_file = fs.joinpath(tmp, 'alpha_spec.lua')
    local results = loader({ root_file }, { '_spec' }, { recursive = false, excludes = {} })
    assert.are.same({ root_file }, results)
    assert.are.same({ root_file }, published)
  end)

  it('publishes an error when the root does not exist', function()
    local missing = fs.joinpath(tmp, 'missing_dir')
    local results = loader({ missing }, { '_spec' }, { recursive = true, excludes = {} })
    assert.are.same({}, results)
    assert.are.same('Cannot find file or directory: ' .. missing, published[1].message)
  end)
end)

describe('busted.fixtures', function()
  it('resolves and reads files relative to the caller', function()
    local content = fixtures.read('fixtures/sample.txt')
    assert.are.same('hello fixture\n', content)

    local src = debug.getinfo(1, 'S').source:gsub('^@', '')
    local expected = fs.normalize(fs.joinpath(fs.dirname(src), 'fixtures'))
    assert.are.same(expected, fixtures.path('fixtures'))
  end)

  it('loads Lua files relative to the caller', function()
    local module = fixtures.load('fixtures/sample_module')
    assert.are.same('hello module', module.greeting)
  end)
end)
