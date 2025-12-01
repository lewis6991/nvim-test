--- @class busted.DebugInfo: debuglib.DebugInfo
--- @field traceback string
--- @field message string

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

local function errortype(obj)
  local mt = debug.getmetatable(obj)
  if mt == failureMt or mt == failureMtNoString then
    return 'failure'
  elseif mt == pendingMt then
    return 'pending'
  end
  return 'error'
end

local function hasToString(obj)
  return type(obj) == 'string' or (debug.getmetatable(obj) or {}).__tostring
end

local function isCallable(obj)
  return type(obj) == 'function' or (debug.getmetatable(obj) or {}).__call
end

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

--- @class busted.Mediator
--- @field publish fun(self, channel: table, ...: any)
--- @field subscribe fun(self, channel: table, fn: fun(...: any), options?: table): table
--- @field removeSubscriber fun(self, channel: table): any

--- @class busted.ExecutorAttributes
--- @field default_fn fun()?
--- @field envmode? 'insulate'|'unwrap'|'expose'

--- @alias busted.Executor fun(plugin: table)

local function bind_method(instance, method)
  return function(arg1, ...)
    if arg1 == instance then
      return method(instance, ...)
    end
    return method(instance, arg1, ...)
  end
end

--- @class busted.Busted
--- @field version string
--- @field context busted.Context
--- @field api table<string, any>
--- @field executors table<string, fun(name: string, fn?: fun())>
--- @field status fun(status: string): busted.Status
--- @field skipAll boolean
--- @field private _mediator busted.Mediator
--- @field private _environment busted.Environment
--- @field private _executor_impl table<string, busted.Executor?>
--- @field private _executor_attributes table<string, busted.ExecutorAttributes?>
local M = {}
M.__index = M

function M.new()
  local context = require('busted.context').new()
  local instance = {
    version = '2.2.0',
    context = context,
    api = {},
    executors = {},
    status = require('busted.status'),
    skipAll = false,
    --- @type busted.Mediator
    _mediator = require('mediator')(),
    _environment = require('busted.environment').new(context),
    --- @type table<string, busted.Executor?>
    _executor_impl = {},
    --- @type table<string, busted.ExecutorAttributes?>
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

  local file = self:getFile(element)

  if file then
    return file.getTrace(file.name, info)
  end

  -- trim traceback
  local index = info.traceback:find('\n%s*%[C]')
  info.traceback = info.traceback:sub(1, index)
  return info
end

function M:rewriteMessage(element, message, trace)
  local file = self:getFile(element)
  local msg = hasToString(message) and tostring(message)
  msg = msg or (message ~= nil and pretty_write(message) or 'Nil error')
  msg = (file and file.rewriteMessage and file.rewriteMessage(file.name, msg) or msg)

  local hasFileLine = msg:match('^[^\n]-:%d+: .*')
  if not hasFileLine then
    trace = trace or self:getTrace(element, 3, message)
    local fileline = trace.short_src .. ':' .. trace.currentline .. ': '
    msg = fileline .. msg
  end

  return msg
end

function M:publish(...)
  return self._mediator:publish(...)
end

function M:subscribe(...)
  return self._mediator:subscribe(...)
end

function M:unsubscribe(...)
  return self._mediator:removeSubscriber(...)
end

function M:getFile(element)
  local parent = self.context:parent(element)

  while parent do
    if parent.file then
      local file = parent.file[1]
      return {
        name = file.name,
        getTrace = file.run.getTrace,
        rewriteMessage = file.run.rewriteMessage,
      }
    end

    if parent.descriptor == 'file' then
      return {
        name = parent.name,
        getTrace = parent.run.getTrace,
        rewriteMessage = parent.run.rewriteMessage,
      }
    end

    parent = self.context:parent(parent)
  end

  return parent
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

function M:bindfenv(callable, var, value)
  local _ = self
  local env = {}
  local f = (debug.getmetatable(callable) or {}).__call or callable
  setmetatable(env, { __index = getfenv(f) })
  env[var] = value
  setfenv(f, env)
end

function M:wrap(callable)
  if isCallable(callable) then
    -- prioritize __call if it exists, like in files
    self._environment:wrap((debug.getmetatable(callable) or {}).__call or callable)
  end
end

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

  local results = { self.status(status) }
  for i = 2, #ret do
    results[i] = ret[i]
  end
  self.context:pop()
  return unpack(results)
end

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

function M:exportApi(key, value)
  self.api[key] = value
end

function M:export(key, value)
  self:exportApi(key, value)
  self._environment:set(key, value)
end

function M:hide(key, _value)
  self.api[key] = nil
  self._environment:set(key, nil)
end

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
    if executor ~= nil and not isCallable(executor) then
      attributes = executor
      executor = nil
    end
    executors[descriptor] = executor
    eattributes[descriptor] = attributes
  end

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

    if not ctx[descriptor] then
      ctx[descriptor] = { plugin }
    else
      ctx[descriptor][#ctx[descriptor] + 1] = plugin
    end
  end)
end

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
