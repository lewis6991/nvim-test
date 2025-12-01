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
--- @return boolean
local function isCallable(obj)
  return type(obj) == 'function' or (debug.getmetatable(obj) or {}).__call
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

local PUBLIC_METHODS = {
  'getTrace',
  'rewriteMessage',
  'publish',
  'subscribe',
  'unsubscribe',
  'getFile',
  'fail',
  'pending',
  'bindfenv',
  'wrap',
  'safe',
  'safe_publish',
  'exportApi',
  'export',
  'hide',
  'register',
  'execute',
}

--- @class busted.Status
--- @field success fun(self): boolean
--- @field pending fun(self): boolean
--- @field failure fun(self): boolean
--- @field error fun(self): boolean
--- @field get fun(self): string
--- @field set fun(self, status: string)
--- @field update fun(self, status: string)

--- @class busted.ExecutorAttributes
--- @field default_fn fun()?
--- @field envmode? 'insulate'|'unwrap'|'expose'

--- @alias busted.Executor fun(plugin: table)
--- @alias busted.CallableValue (fun(...: any): any)|{ __call: fun(...: any): any }

--- @param instance table
--- @param method fun(self: table, ...: any): any
--- @return fun(...: any): any
local function bind_method(instance, method)
  return function(arg1, ...)
    if arg1 == instance then
      return method(instance, ...)
    end
    return method(instance, arg1, ...)
  end
end

--- @class (partial) busted.Busted
--- @field private _executor_impl table<string, busted.Executor?>
--- @field private _executor_attributes table<string, busted.ExecutorAttributes?>
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
    --- @type table<string, fun(name: string|busted.CallableValue|nil, fn?: busted.CallableValue)>
    executors = {},
    status = require('busted.status'),
    skipAll = false,
    _mediator = require('mediator').new(),
    _environment = require('busted.environment').new(context),
    _executor_impl = {},
    _executor_attributes = {},
  }

  setmetatable(instance, { __index = M })

  -- bind public methods
  for _, name in ipairs(PUBLIC_METHODS) do
    local method = M[name] or error('missing method implementation for ' .. name)
    instance[name] = bind_method(instance, method)
  end

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

--- @param ... any
--- @return mediator.PublishResult
function M:publish(...)
  return self._mediator:publish(...)
end

--- @param ... any
--- @return mediator.Subscriber
function M:subscribe(...)
  return self._mediator:subscribe(...)
end

--- @param ... any
--- @return mediator.Subscriber?
function M:unsubscribe(...)
  return self._mediator:removeSubscriber(...)
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
function M:fail(msg, level)
  local _ = self
  local rawlevel = (type(level) ~= 'number' or level <= 0) and level
  level = level or 1
  local _, emsg = pcall(error, msg, rawlevel or level + 2)
  local e = { message = emsg }
  setmetatable(e, hasToString(msg) and failureMt or failureMtNoString)
  error(e, rawlevel or level + 1)
end

--- @param msg string
function M:pending(msg)
  local _ = self
  local p = { message = msg }
  setmetatable(p, pendingMt)
  error(p)
end

--- @param callable busted.CallableValue
--- @param var string
--- @param value any
function M:bindfenv(callable, var, value)
  local _ = self
  local env = {}
  local f = (debug.getmetatable(callable) or {}).__call or callable
  setmetatable(env, { __index = getfenv(f) })
  env[var] = value
  setfenv(f, env)
end

--- @param callable any
function M:wrap(callable)
  if isCallable(callable) then
    -- prioritize __call if it exists, like in files
    self._environment:wrap((debug.getmetatable(callable) or {}).__call or callable)
  end
end

--- @param descriptor string
--- @param run fun(): any
--- @param element busted.Element
--- @return busted.Status, any
function M:safe(descriptor, run, element)
  self.context:push(element)
  local trace, message
  local status = 'success'

  local ret = {
    xpcall(run, function(msg)
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
--- @param channel mediator.ChannelPath
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
function M:export(key, value)
  self:exportApi(key, value)
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
  local alias
  --- @type table<string, busted.Executor?>
  local executors = self._executor_impl
  --- @type table<string, busted.ExecutorAttributes?>
  local eattributes = self._executor_attributes

  if type(executor) == 'string' then
    alias = descriptor
    descriptor = executor
    executor = executors[descriptor]
    attributes = attributes or eattributes[descriptor]
    executors[alias] = executor
    eattributes[alias] = attributes
  else
    --- @cast executor busted.Executor|busted.ExecutorAttributes|nil
    if executor ~= nil and not isCallable(executor) then
      --- @cast executor busted.ExecutorAttributes
      attributes = executor
      executor = nil
    end
    --- @cast executor busted.Executor?
    executors[descriptor] = executor
    eattributes[descriptor] = attributes
  end

  --- @param name? string|busted.CallableValue
  --- @param fn? busted.CallableValue
  --- @return fun(f: busted.CallableValue)|nil
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

    ctx[descriptor] = ctx[descriptor] or { plugin }
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
