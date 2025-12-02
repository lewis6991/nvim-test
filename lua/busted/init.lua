local Block = require('busted.block')

--- @param block busted.Block
--- @param busted busted.Busted
--- @param element busted.BlockRuntimeElement
local function file(block, busted, element)
  busted:wrap(element.run)
  if busted:safe_publish('file', { 'file', 'start' }, element) then
    block:execute('file', element)
  end
  busted:safe_publish('file', { 'file', 'end' }, element)
end

--- @param block busted.Block
--- @param busted busted.Busted
--- @param element busted.BlockRuntimeElement
local function describe(block, busted, element)
  local parent = busted.context:parent(element) or busted.context:get()
  if busted:safe_publish('describe', { 'describe', 'start' }, element, parent) then
    block:execute('describe', element)
  end
  busted:safe_publish('describe', { 'describe', 'end' }, element, parent)
end

--- @param block busted.Block
--- @param busted busted.Busted
--- @param element busted.BlockRuntimeElement
local function it(block, busted, element)
  local parent = busted.context:parent(element) or busted.context:get()

  if not block:lazySetup(parent) then
    -- skip test if any setup failed
    return
  end

  if not element.env then
    element.env = {}
  end

  block:rejectAll(element)

  --- @type busted.CallableValue? finally
  local finally

  --- @param fn busted.CallableValue
  element.env.finally = function(fn)
    finally = fn
  end

  element.env.pending = busted.pending

  local pass, ancestor = block:execAll('before_each', parent, true)

  if pass then
    local status = busted.status.new('success')
    if busted:safe_publish('test', { 'test', 'start' }, element, parent) then
      local run = element.run
      if not run then
        error('Attempt to execute spec without a body')
      end
      status:update(busted:safe('it', run, element))
      if finally then
        block:reject('pending', element)
        status:update(busted:safe('finally', finally, element))
      end
    else
      status = busted.status('error')
    end
    busted:safe_publish('test', { 'test', 'end' }, element, parent, tostring(status))
  end

  block:dexecAll('after_each', ancestor, true)
end

--- @param busted busted.Busted
--- @param element busted.Element
local function pending(busted, element)
  local parent = busted.context:parent(element)
  local status = 'pending'
  if not busted:safe_publish('it', { 'test', 'start' }, element, parent) then
    status = 'error'
  end
  busted:safe_publish('it', { 'test', 'end' }, element, parent, status)
end

--- @param busted busted.Busted
local function init(busted)
  local block = Block.new(busted)

  busted:register(
    'file',
    --- @param element busted.Element
    function(element)
      return file(block, busted, element)
    end,
    { envmode = 'insulate' }
  )

  busted:register(
    'describe',
    --- @param element busted.Element
    function(element)
      return describe(block, busted, element)
    end
  )

  busted:register('insulate', 'describe', { envmode = 'insulate' })
  busted:register('expose', 'describe', { envmode = 'expose' })

  busted:register(
    'it',
    --- @param element busted.Element
    function(element)
      return it(block, busted, element)
    end
  )

  busted:register(
    'pending',
    --- @param element busted.Element
    function(element)
      return pending(busted, element)
    end,
    { default_fn = function() end }
  )

  busted:register('before_each', { envmode = 'unwrap' })
  busted:register('after_each', { envmode = 'unwrap' })

  busted:register('lazy_setup', { envmode = 'unwrap' })
  busted:register('lazy_teardown', { envmode = 'unwrap' })
  busted:register('strict_setup', { envmode = 'unwrap' })
  busted:register('strict_teardown', { envmode = 'unwrap' })

  busted:register('setup', 'strict_setup')
  busted:register('teardown', 'strict_teardown')

  busted:register('context', 'describe')
  busted:register('spec', 'it')
  busted:register('test', 'it')

  busted:hide('file')

  local assert = require('luassert')

  require('busted.fixtures') -- just load into the environment, not exposing it

  busted:export('assert', assert)

  busted:exportApiMethod('publish', busted.publish)
  busted:exportApiMethod('subscribe', busted.subscribe)
  busted:exportApiMethod('unsubscribe', busted.unsubscribe)
  busted:exportApi('bindfenv', busted.bindfenv)
  busted:exportApi('fail', busted.fail)
  busted:exportApi('parent', busted.context.parent)
  busted:exportApi('children', busted.context.children)
  busted:exportApi('version', busted.version)
  busted.bindfenv(assert, 'error', busted.fail)
end

return setmetatable({}, {
  --- @param busted busted.Busted
  __call = function(self, busted)
    init(busted)

    return setmetatable(self, {
      __index = function(_, key)
        return busted.api[key]
      end,

      __newindex = function(_, _key, _value)
        error('Attempt to modify busted')
      end,
    })
  end,
})
