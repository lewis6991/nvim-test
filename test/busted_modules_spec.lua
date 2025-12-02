local uv = vim.uv
local fs = vim.fs

local test_file_loader = require('busted.test_file_loader')
local FilterLoader = require('busted.filter_loader')
local fixtures = require('busted.fixtures')
local busted_core = require('busted.core')

local function mktempdir()
  local os_tmp = assert(uv.os_tmpdir(), 'uv.os_tmpdir() unavailable')
  local template = fs.joinpath(os_tmp, 'nvim-test-XXXXXX')
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
  ---@type string?
  local tmp
  ---@type (fun(root_files: string[], patterns: string[]?, options: test_file_loader.Options?): string[]?)?
  local loader_impl
  ---@type string[]
  local executed_files = {}
  ---@type { subjects: string[]?, element: any, message: string }[]
  local published_events = {}
  ---@type busted.Busted?
  local stub_busted

  local function run_loader(root_files, patterns, options)
    assert(loader_impl, 'loader not initialized')
    local results = loader_impl(root_files, patterns, options)
    assert(results, 'loader did not return results')
    return results
  end

  before_each(function()
    tmp = mktempdir()
    write_file(tmp, 'alpha_spec.lua', 'return function() end')
    write_file(tmp, 'nested/beta_spec.lua', 'return function() end')
    write_file(tmp, 'skip_this_spec.lua', 'return function() end')
    write_file(tmp, 'helper.lua', 'return function() end')

    executed_files = {}
    published_events = {}
    local stub = busted_core.new()
    stub.executors.file = function(fileName)
      table.insert(executed_files, fileName)
    end
    local base_publish = stub.publish
    ---@diagnostic disable-next-line: duplicate-set-field
    function stub:publish(channel, subjects, element, message, data)
      table.insert(published_events, {
        channel = channel,
        subjects = subjects,
        element = element,
        message = message,
        data = data,
      })
      return base_publish(self, channel, subjects, element, message, data)
    end
    stub_busted = stub

    ---@param root_files string[]
    ---@param patterns? string[]
    ---@param options? test_file_loader.Options
    ---@return string[]
    loader_impl = function(root_files, patterns, options)
      return test_file_loader(stub_busted, root_files, patterns, options)
    end
  end)

  after_each(function()
    if tmp then
      rm_rf(tmp)
      tmp = nil
    end
  end)

  it('collects spec files recursively and honors excludes', function()
    local temp_root = assert(tmp, 'temp directory unavailable')
    local results = run_loader({ temp_root }, { '_spec' }, {
      recursive = true,
      excludes = { 'skip_this' },
    })

    table.sort(results)
    table.sort(executed_files)
    local expected = {
      fs.joinpath(temp_root, 'alpha_spec.lua'),
      fs.joinpath(temp_root, 'nested/beta_spec.lua'),
    }

    assert.are.same(expected, results)
    assert.are.same(expected, executed_files)
  end)

  it('returns a single file when root is a file path', function()
    local temp_root = assert(tmp, 'temp directory unavailable')
    local root_file = fs.joinpath(temp_root, 'alpha_spec.lua')
    local results = run_loader({ root_file }, { '_spec' }, { recursive = false, excludes = {} })
    assert.are.same({ root_file }, results)
    assert.are.same({ root_file }, executed_files)
  end)

  it('publishes an error when the root does not exist', function()
    local temp_root = assert(tmp, 'temp directory unavailable')
    local missing = fs.joinpath(temp_root, 'missing_dir')
    local results = run_loader({ missing }, { '_spec' }, { recursive = true, excludes = {} })
    assert.are.same({}, results)
    local first_event = assert(published_events[1], 'expected published event')
    assert.are.same('Cannot find file or directory: ' .. missing, first_event.message)
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

---@class FilterElement: busted.Element
---@field parent? FilterElement

---@class FilterStubContext
---@field current FilterElement?

describe('busted.modules.filter_loader', function()
  ---@type busted.Busted?
  local stub_busted
  ---@type FilterStubContext
  local stub_context = { current = nil }
  ---@type { channel: string[], handler?: fun(...: any), options?: table }[]
  local subscriptions = {}
  ---@type { channel: string[], descriptor_name: string, fn: fun(...: any), args: any[] }[]
  local published = {}
  local original_print

  local function apply_filter(options)
    assert(stub_busted, 'stub_busted not initialized')
    FilterLoader.new(stub_busted, options or {}):run()
  end

  before_each(function()
    original_print = rawget(_G, 'print')
    subscriptions = {}
    published = {}
    stub_context = { current = nil }
    ---@return busted.Element?
    function stub_context:get()
      return self.current
    end
    ---@param node? FilterElement
    stub_context.parent = function(_, node)
      return node and node.parent
    end

    local busted_instance = busted_core.new()
    busted_instance.skipAll = false
    busted_instance.context = stub_context
    local base_subscribe = busted_instance.subscribe
    ---@diagnostic disable-next-line: duplicate-set-field
    function busted_instance:subscribe(channel, handler, options)
      table.insert(subscriptions, { channel = channel, handler = handler, options = options })
      return base_subscribe(self, channel, handler, options)
    end
    local base_publish = busted_instance.publish
    ---@diagnostic disable-next-line: duplicate-set-field
    function busted_instance:publish(channel, descriptor_name, fn, ...)
      table.insert(published, {
        channel = channel,
        descriptor_name = descriptor_name,
        fn = fn,
        args = { ... },
      })
      return base_publish(self, channel, descriptor_name, fn, ...)
    end
    stub_busted = busted_instance
  end)

  after_each(function()
    rawset(_G, 'print', original_print)
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

    local first_register = assert(register_subs[1], 'missing register subscription')
    local register_handler = assert(first_register.handler, 'missing register handler')
    local _, allow = register_handler()
    assert.is_true(allow)
  end)

  it('stubs helper callbacks and prints names in list mode', function()
    ---@type FilterElement
    stub_context.current = {
      name = 'example',
      descriptor = 'it',
      attributes = {},
      parent = {
        name = 'suite',
        descriptor = 'describe',
        attributes = {},
        parent = { descriptor = 'file', attributes = {} },
      },
    }

    local printed = {} ---@type string[]
    rawset(_G, 'print', function(msg)
      table.insert(printed, msg)
    end)

    apply_filter({ list = true })

    local setup_sub = assert(find_subscription({ 'register', 'setup' }), 'setup subscription missing')
    local test_end_sub = assert(find_subscription({ 'test', 'end' }), 'test end subscription missing')

    local original_fn = function() end
    local setup_handler = assert(setup_sub.handler, 'setup handler missing')
    setup_handler('setup block', original_fn)
    local setup_event = assert(published[1], 'expected setup publish')
    assert.are.same({ 'register', 'setup' }, setup_event.channel)
    assert.are.same('setup block', setup_event.descriptor_name)
    assert.are_not.equal(original_fn, setup_event.fn)

    local test_end_handler = assert(test_end_sub.handler, 'test end handler missing')
    test_end_handler(
      { trace = { what = 'Lua', short_src = 'spec.lua', currentline = 42 } },
      nil,
      'success'
    )
    assert.are.same({ 'spec.lua:42: suite example' }, printed)
  end)
end)
