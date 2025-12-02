--- @class busted.DebugInfo: debuglib.DebugInfo
--- @field traceback string
--- @field message string

--- @class busted.FileRun
--- @field getTrace fun(name: string, info: busted.DebugInfo): busted.DebugInfo
--- @field rewriteMessage fun(name: string, message: string): string

--- @class busted.FileReference
--- @field name string
--- @field run busted.FileRun

--- @class busted.FileTrace
--- @field name string
--- @field getTrace fun(name: string, info: busted.DebugInfo): busted.DebugInfo
--- @field rewriteMessage fun(name: string, message: string): string

--- @class busted.Element
--- @field descriptor string
--- @field name? string
--- @field attributes table
--- @field file? busted.FileReference[]
--- @field run? busted.FileRun
--- @field starttick? number
--- @field endtick? number
--- @field starttime? number
--- @field endtime? number
--- @field duration? number

local failureMt = {
  __index = {},
  __tostring = function(e)
    return tostring(e.message)
  end,
  __type = 'failure',
}

local failureMtNoString = {
  __index = {},
  __type = 'failure',
}

local pendingMt = {
  __index = {},
  __tostring = function(p)
    return p.message
  end,
  __type = 'pending',
}

--- @param obj any
--- @return 'failure'|'pending'|'error'
local function errortype(obj)
  local mt = debug.getmetatable(obj)
  if mt == failureMt or mt == failureMtNoString then
    return 'failure'
  elseif mt == pendingMt then
    return 'pending'
  end
  return 'error'
end

--- @param obj any
--- @return boolean
local function hasToString(obj)
  return type(obj) == 'string' or (debug.getmetatable(obj) or {}).__tostring
end

--- @param obj any
--- @return TypeGuard<function>
local function isCallable(obj)
  return type(obj) == 'function' or (debug.getmetatable(obj) or {}).__call
end

--- @class busted.EventSubscriberOptions
--- @field priority? integer
--- @field predicate? fun(...: any): boolean

--- @class busted.EventSubscriber
--- @field id integer
--- @field fn fun(...: any): any
--- @field options busted.EventSubscriberOptions

--- @class busted.EventNode
--- @field parent? busted.EventNode
--- @field callbacks busted.EventSubscriber[]
--- @field children table<string, busted.EventNode>

--- @alias busted.EventChannelPath string[]
--- @alias busted.EventPublishResult any[]
--- @alias busted.EventCallback fun(...: any): any, boolean?

--- @param parent? busted.EventNode
--- @return busted.EventNode
local function new_event_node(parent)
  return {
    parent = parent,
    callbacks = {},
    children = {},
  }
end

--- @param node busted.EventNode
--- @param id integer
--- @return busted.EventNode?, integer?
local function find_subscription_owner(node, id)
  for index = 1, #node.callbacks do
    local callback = node.callbacks[index]
    if callback and callback.id == id then
      return node, index
    end
  end

  for _, child in pairs(node.children) do
    local owner, index = find_subscription_owner(child, id)
    if owner and index then
      return owner, index
    end
  end
end

--- @param node busted.EventNode
--- @param channelNamespace busted.EventChannelPath
--- @return busted.EventNode
local function resolve_node(node, channelNamespace)
  for index = 1, #channelNamespace do
    local key = channelNamespace[index]
    local child = node.children[key]
    if not child then
      child = new_event_node(node)
      node.children[key] = child
    end
    node = child
  end
  return node
end

--- @param node busted.EventNode
--- @param result busted.EventPublishResult
--- @return busted.EventPublishResult
local function dispatch(node, result, ...)
  for index = 1, #node.callbacks do
    local callback = node.callbacks[index]
    if callback then
      local predicate = callback.options.predicate
      if not predicate or predicate(...) then
        local value, continue = callback.fn(...)
        if value then
          table.insert(result, value)
        end
        if not continue then
          return result
        end
      end
    end
  end

  if node.parent then
    return dispatch(node.parent, result, ...)
  end

  return result
end

--- @param src any
--- @return string?
local function normalize_source(src)
  if type(src) ~= 'string' then
    return nil
  end
  if src:sub(1, 1) == '@' then
    src = src:sub(2)
  end
  return vim.fs.normalize(src)
end

--- @param src string?
--- @return string?
local function dirname(src)
  return vim.fs.dirname(normalize_source(src))
end

--- @param value any
--- @return string
local function pretty_write(value)
  if type(value) == 'string' then
    return value
  end
  if value == nil then
    return 'nil'
  end
  return vim.inspect(value)
end

--- @class busted.ExecutorAttributes
--- @field default_fn fun()?
--- @field envmode? 'insulate'|'unwrap'|'expose'

--- @alias busted.Executor fun(plugin: busted.Element)
--- @alias busted.CallableValue (fun(...: any): any)|{ __call: fun(...: any): any }

--- @class (partial) busted.Busted
--- @field private _executor_impl table<string, busted.Executor?>
--- @field private _executor_attributes table<string, busted.ExecutorAttributes?>
--- @field private _channel_root busted.EventNode
local M = {}
M.__index = M

--- @return busted.Busted
function M.new()
  local context = require('busted.context').new()
  --- @class (partial) busted.Busted
  local instance = {
    version = '2.2.0',
    context = context,
    --- @type table<string, any>
    api = {},
    --- @type table<string, fun(name: string|busted.CallableValue?, fn?: busted.CallableValue)>
    executors = {},
    status = require('busted.status'),
    skipAll = false,
    _channel_root = new_event_node(),
    _environment = require('busted.environment').new(context),
    _executor_impl = {},
    _executor_attributes = {},
  }

  setmetatable(instance, { __index = M })

  return instance
end

--- @param element? busted.Element
--- @param level? integer
--- @param msg any
--- @return busted.DebugInfo
function M:getTrace(element, level, msg)
  level = level or 3

  local thisdir = dirname(debug.getinfo(1, 'Sl').source) or ''
  --- @type busted.DebugInfo
  local info = debug.getinfo(level, 'Sl')
  while
    info.what == 'C'
    or info.short_src:match('luassert[/\\].*%.lua$')
    or (info.source:sub(1, 1) == '@' and thisdir == (dirname(info.source) or ''))
  do
    level = level + 1
    info = debug.getinfo(level, 'Sl')
  end

  info.traceback = debug.traceback('', level)
  info.message = tostring(msg)

  --- @type busted.FileTrace?
  local file = self:getFile(element)

  if file then
    --- @cast file busted.FileTrace
    return file.getTrace(file.name, info)
  end

  -- trim traceback
  local index = info.traceback:find('\n%s*%[C]')
  info.traceback = info.traceback:sub(1, index)
  return info
end

--- @param element? busted.Element
--- @param message any
--- @param trace? busted.DebugInfo
--- @return string
function M:rewriteMessage(element, message, trace)
  --- @type busted.FileTrace?
  local file = self:getFile(element)
  local msg = hasToString(message) and tostring(message)
  msg = msg or (message ~= nil and pretty_write(message) or 'Nil error')
  if file and file.rewriteMessage then
    --- @cast file busted.FileTrace
    msg = file.rewriteMessage(file.name, msg)
  end

  local hasFileLine = msg:match('^[^\n]-:%d+: .*')
  if not hasFileLine then
    trace = trace or self:getTrace(element, 3, message)
    local fileline = trace.short_src .. ':' .. trace.currentline .. ': '
    msg = fileline .. msg
  end

  return msg
end

--- @param channelNamespace busted.EventChannelPath
--- @param ... any
--- @return busted.EventPublishResult
function M:publish(channelNamespace, ...)
  return dispatch(resolve_node(self._channel_root, channelNamespace), {}, ...)
end

local next_subscription_id = 1

--- @param channelNamespace busted.EventChannelPath
--- @param fn busted.EventCallback
--- @param options? busted.EventSubscriberOptions
--- @return busted.EventSubscriber
function M:subscribe(channelNamespace, fn, options)
  local node = resolve_node(self._channel_root, channelNamespace)

  --- @type busted.EventSubscriber
  local subscriber = {
    id = next_subscription_id,
    fn = fn,
    options = options or {},
  }
  next_subscription_id = next_subscription_id + 1

  local insert_index = #node.callbacks + 1
  local priority = subscriber.options.priority
  if priority and priority >= 0 and priority < insert_index then
    insert_index = math.floor(priority)
  end
  if insert_index < 1 then
    insert_index = 1
  end
  table.insert(node.callbacks, insert_index, subscriber)

  return subscriber
end

--- @param id integer
--- @return busted.EventSubscriber?
function M:unsubscribe(id)
  local node = self._channel_root
  local owner, index = find_subscription_owner(node, id)
  if not owner or not index then
    return nil
  end
  return table.remove(owner.callbacks, index)
end

--- @param element? busted.Element
--- @return busted.FileTrace?
function M:getFile(element)
  if not element then
    return nil
  end

  local parent = self.context:parent(element)
  --- @cast parent busted.Element?

  while parent do
    --- @cast parent busted.Element
    if parent.file then
      --- @type busted.FileReference?
      local file = parent.file[1]
      if file and type(file.name) == 'string' then
        local run = file.run
        if run and run.getTrace and run.rewriteMessage then
          --- @cast file busted.FileReference
          --- @cast run busted.FileRun
          return {
            name = file.name,
            getTrace = run.getTrace,
            rewriteMessage = run.rewriteMessage,
          }
        end
      end
    end

    if parent.descriptor == 'file' and type(parent.name) == 'string' then
      local run = parent.run
      if run and run.getTrace and run.rewriteMessage then
        --- @cast run busted.FileRun
        return {
          name = parent.name,
          getTrace = run.getTrace,
          rewriteMessage = run.rewriteMessage,
        }
      end
    end

    parent = self.context:parent(parent)
    --- @cast parent busted.Element?
  end

  return nil
end

--- @param msg string
--- @param level? integer
function M.fail(msg, level)
  local rawlevel = (type(level) ~= 'number' or level <= 0) and level
  level = level or 1
  local _, emsg = pcall(error, msg, rawlevel or level + 2)
  local e = { message = emsg }
  setmetatable(e, hasToString(msg) and failureMt or failureMtNoString)
  error(e, rawlevel or level + 1)
end

--- @param msg string
function M.pending(msg)
  local p = { message = msg }
  setmetatable(p, pendingMt)
  error(p)
end

--- @param callable busted.CallableValue
--- @param var string
--- @param value any
function M.bindfenv(callable, var, value)
  local env = {}
  local f = (debug.getmetatable(callable) or {}).__call or callable
  setmetatable(env, { __index = getfenv(f) })
  env[var] = value
  setfenv(f, env)
end

--- @param callable any
function M:wrap(callable)
  assert(isCallable(callable))
  -- prioritize __call if it exists, like in files
  self._environment:wrap((debug.getmetatable(callable) or {}).__call or callable)
end

--- @param descriptor string
--- @param run busted.CallableValue
--- @param element busted.Element
--- @return busted.Status, any
function M:safe(descriptor, run, element)
  local runner = run
  if type(runner) ~= 'function' then
    local target = runner
    local mt = debug.getmetatable(target)
    local call = mt and mt.__call
    if type(call) == 'function' then
      runner = function(...)
        return call(target, ...)
      end
    else
      error('attempt to execute non-callable block for ' .. tostring(descriptor), 2)
    end
  end
  self.context:push(element)
  local trace, message
  local status = 'success'

  local ret = {
    xpcall(runner, function(msg)
      status = errortype(msg)
      trace = self:getTrace(element, 3, msg)
      message = self:rewriteMessage(element, msg, trace)
    end),
  }
  --- @cast ret any[]

  local ok = ret[1]
  if not ok then
    if status == 'success' then
      status = 'error'
      local err_msg = ret[2] or message or 'unknown error'
      trace = self:getTrace(element, 3, err_msg)
      message = self:rewriteMessage(element, err_msg, trace)
    elseif status == 'failure' and descriptor ~= 'it' then
      status = 'error'
    end

    self:publish(
      { status, element.descriptor },
      element,
      self.context:parent(element),
      message,
      trace
    )
  end

  --- @type busted.Status
  local status_obj = self.status(status)
  self.context:pop()
  return status_obj, unpack(ret, 2, #ret)
end

--- @param descriptor string
--- @param channel busted.EventChannelPath
--- @param element busted.Element
--- @param ... any
--- @return boolean
function M:safe_publish(descriptor, channel, element, ...)
  local args = { ... }
  local n = select('#', ...)
  if channel[2] == 'start' then
    element.starttick = vim.uv.hrtime()
    element.starttime = vim.uv.now()
  elseif channel[2] == 'end' then
    element.endtime = vim.uv.now()
    element.endtick = vim.uv.hrtime()
    element.duration = element.starttick and (element.endtick - element.starttick)
  end
  local status = self:safe(descriptor, function()
    self:publish(channel, element, unpack(args, 1, n))
  end, element)
  return status:success()
end

--- @param key string
--- @param value any
function M:exportApi(key, value)
  self.api[key] = value
end

--- @param key string
--- @param value any
function M:exportApiMethod(key, value)
  self:exportApi(key, function(...)
    return value(self, ...)
  end)
end

--- @param key string
--- @param value any
function M:export(key, value)
  self.api[key] = value
  self._environment:set(key, value)
end

--- @param key string
--- @param _value any
function M:hide(key, _value)
  self.api[key] = nil
  self._environment:set(key, nil)
end

--- @param descriptor string
--- @param executor? busted.Executor|string|busted.ExecutorAttributes
--- @param attributes? busted.ExecutorAttributes
function M:register(descriptor, executor, attributes)
  local alias --- @type string?
  local executors = self._executor_impl
  local eattributes = self._executor_attributes

  if type(executor) == 'string' then
    alias = descriptor
    descriptor = executor
    executor = executors[descriptor]
    attributes = attributes or eattributes[descriptor]
    executors[alias] = executor
    eattributes[alias] = attributes
  elseif executor ~= nil and not isCallable(executor) then
    executors[descriptor] = nil
    eattributes[descriptor] = executor
  else
    executors[descriptor] = executor
    eattributes[descriptor] = attributes
  end

  --- @param name? string|busted.CallableValue
  --- @param fn? busted.CallableValue
  --- @return fun(f: busted.CallableValue)?
  local function publisher(name, fn)
    if not fn and type(name) == 'function' then
      fn = name
      name = alias
    elseif not fn then
      fn = attributes and attributes.default_fn
    end

    local trace

    local ctx = self.context:get()
    if self.context:parent(ctx) then
      trace = self:getTrace(ctx, 3, name)
    end

    --- @param f busted.CallableValue
    local function publish(f)
      self:publish({ 'register', descriptor }, name, f, trace, attributes)
    end

    if fn then
      publish(fn)
    else
      return publish
    end
  end

  local edescriptor = alias or descriptor
  self.executors[edescriptor] = publisher
  self:export(edescriptor, publisher)

  self:subscribe({ 'register', descriptor }, function(name, fn, trace, attr)
    local ctx = self.context:get()
    --- @type busted.Element
    local plugin = {
      descriptor = descriptor,
      attributes = attr or {},
      name = name,
      run = fn,
      trace = trace,
      starttick = nil,
      endtick = nil,
      starttime = nil,
      endtime = nil,
      duration = nil,
    }

    self.context:attach(plugin)

    ctx[descriptor] = ctx[descriptor] or {}
    ctx[descriptor][#ctx[descriptor] + 1] = plugin
  end)
end

--- @param current? busted.Element
function M:execute(current)
  if not current then
    current = self.context:get()
  end
  for _, v in pairs(self.context:children(current)) do
    local executor = self._executor_impl[v.descriptor]
    if executor and not self.skipAll then
      self:safe(v.descriptor, function()
        executor(v)
      end, v)
    end
  end
end

return M
