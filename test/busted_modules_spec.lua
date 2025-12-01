local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')
local fs = vim.fs

local test_file_loader_factory = require('busted.modules.test_file_loader')
local FilterLoader = require('busted.modules.filter_loader')
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
      publish = function(_, subjects, element, _, message)
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

describe('busted.modules.filter_loader', function()
  local stub_busted
  local stub_context
  local subscriptions
  local published
  local original_print

  local function apply_filter(options)
    FilterLoader.apply(stub_busted, options or {})
  end

  before_each(function()
    original_print = _G.print
    subscriptions = {}
    published = {}
    stub_context = {}
    function stub_context:get()
      return self.current
    end
    function stub_context:parent(node)
      return node and node.parent
    end

    stub_busted = {
      skipAll = false,
      context = stub_context,
      subscribe = function(_, channel, handler, options)
        table.insert(subscriptions, { channel = channel, handler = handler, options = options })
        return handler
      end,
      publish = function(_, channel, descriptor_name, fn, ...)
        table.insert(published, {
          channel = channel,
          descriptor_name = descriptor_name,
          fn = fn,
          args = { ... },
        })
      end,
    }
  end)

  after_each(function()
    _G.print = original_print
  end)

  local function find_subscription(target)
    for _, sub in ipairs(subscriptions) do
      if sub.channel[1] == target[1] and sub.channel[2] == target[2] then
        return sub
      end
    end
  end

  it('registers skip-on-error filters when keep-going is disabled', function()
    apply_filter({ nokeepgoing = true })
    local register_subs = {}
    for _, sub in ipairs(subscriptions) do
      if sub.channel[1] == 'register' then
        table.insert(register_subs, sub)
      end
    end

    assert.are.equal(12, #register_subs)

    local _, allow = register_subs[1].handler()
    assert.is_true(allow)
  end)

  it('stubs helper callbacks and prints names in list mode', function()
    stub_context.current = {
      name = 'example',
      descriptor = 'it',
      parent = {
        name = 'suite',
        descriptor = 'describe',
        parent = { descriptor = 'file' },
      },
    }

    local printed = {}
    _G.print = function(msg)
      table.insert(printed, msg)
    end

    apply_filter({ list = true })

    local setup_sub = find_subscription({ 'register', 'setup' })
    assert.is_not_nil(setup_sub)

    local test_end_sub = find_subscription({ 'test', 'end' })
    assert.is_not_nil(test_end_sub)

    local original_fn = function() end
    setup_sub.handler('setup block', original_fn)
    assert.are.same({ 'register', 'setup' }, published[1].channel)
    assert.are.same('setup block', published[1].descriptor_name)
    assert.are_not.equal(original_fn, published[1].fn)

    test_end_sub.handler({ trace = { what = 'Lua', short_src = 'spec.lua', currentline = 42 } }, nil, 'success')
    assert.are.same({ 'spec.lua:42: suite example' }, printed)
  end)
end)
