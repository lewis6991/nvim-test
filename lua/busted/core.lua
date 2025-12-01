local getfenv = _G.getfenv
local setfenv = _G.setfenv
local unpack = _G.unpack
local fs = vim.fs
local throw = error

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
  return fs.normalize(src)
end

--- @param src string?
--- @return string?
local function dirname(src)
  return fs.dirname(normalize_source(src))
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

local Busted = {}

function Busted.init()
  local root = require('busted.context')()

  --- @class busted.Busted
  local busted = {
    version = '2.2.0',
    context = root.ref(),
    api = {},
    executors = {},
    status = require('busted.status'),
  }

  return busted
end

return function()
  local mediator = require('mediator')()

  local busted = Busted.init()

  local environment = require('busted.environment')(busted.context)

  local executors = {}
  local eattributes = {}

  function busted.getTrace(element, level, msg)
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

    local file = busted.getFile(element)

    if file then
      return file.getTrace(file.name, info)
    end

    -- trim traceback
    local index = info.traceback:find('\n%s*%[C]')
    info.traceback = info.traceback:sub(1, index)
    return info
  end

  function busted.rewriteMessage(element, message, trace)
    local file = busted.getFile(element)
    local msg = hasToString(message) and tostring(message)
    msg = msg or (message ~= nil and pretty_write(message) or 'Nil error')
    msg = (file and file.rewriteMessage and file.rewriteMessage(file.name, msg) or msg)

    local hasFileLine = msg:match('^[^\n]-:%d+: .*')
    if not hasFileLine then
      trace = trace or busted.getTrace(element, 3, message)
      local fileline = trace.short_src .. ':' .. trace.currentline .. ': '
      msg = fileline .. msg
    end

    return msg
  end

  function busted.publish(...)
    return mediator:publish(...)
  end

  function busted.subscribe(...)
    return mediator:subscribe(...)
  end

  function busted.unsubscribe(...)
    return mediator:removeSubscriber(...)
  end

  function busted.getFile(element)
    local parent = busted.context.parent(element)

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

      parent = busted.context.parent(parent)
    end

    return parent
  end

  function busted.fail(msg, level)
    local rawlevel = (type(level) ~= 'number' or level <= 0) and level
    level = level or 1
    local _, emsg = pcall(throw, msg, rawlevel or level + 2)
    local e = { message = emsg }
    setmetatable(e, hasToString(msg) and failureMt or failureMtNoString)
    throw(e, rawlevel or level + 1)
  end

  function busted.pending(msg)
    local p = { message = msg }
    setmetatable(p, pendingMt)
    throw(p)
  end

  function busted.bindfenv(callable, var, value)
    local env = {}
    local f = (debug.getmetatable(callable) or {}).__call or callable
    setmetatable(env, { __index = getfenv(f) })
    env[var] = value
    setfenv(f, env)
  end

  function busted.wrap(callable)
    if isCallable(callable) then
      -- prioritize __call if it exists, like in files
      environment.wrap((debug.getmetatable(callable) or {}).__call or callable)
    end
  end

  function busted.safe(descriptor, run, element)
    busted.context.push(element)
    local trace, message
    local status = 'success'

    local ret = {
      xpcall(run, function(msg)
        status = errortype(msg)
        trace = busted.getTrace(element, 3, msg)
        message = busted.rewriteMessage(element, msg, trace)
      end),
    }
    --- @cast ret any[]

    local ok = ret[1]
    if not ok then
      if status == 'success' then
        status = 'error'
        local err_msg = ret[2] or message or 'unknown error'
        trace = busted.getTrace(element, 3, err_msg)
        message = busted.rewriteMessage(element, err_msg, trace)
      elseif status == 'failure' and descriptor ~= 'it' then
        -- Only 'it' blocks can generate test failures. Failures in all
        -- other blocks are errors outside the test.
        status = 'error'
      end
      -- Note: descriptor may be different from element.descriptor when
      -- safe_publish is used (i.e. for test start/end). The safe_publish
      -- descriptor needs to be different for 'it' blocks so that we can
      -- detect that a 'failure' in a test start/end handler is not really
      -- a test failure, but rather an error outside the test, much like a
      -- failure in a support function (i.e. before_each/after_each or
      -- setup/teardown).
      busted.publish(
        { status, element.descriptor },
        element,
        busted.context.parent(element),
        message,
        trace
      )
    end
    local results = { busted.status(status) }
    for i = 2, #ret do
      results[i] = ret[i]
    end
    busted.context.pop()
    return unpack(results)
  end

  function busted.safe_publish(descriptor, channel, element, ...)
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
    local status = busted.safe(descriptor, function()
      busted.publish(channel, element, unpack(args, 1, n))
    end, element)
    return status:success()
  end

  function busted.exportApi(key, value)
    busted.api[key] = value
  end

  function busted.export(key, value)
    busted.exportApi(key, value)
    environment.set(key, value)
  end

  function busted.hide(key, _value)
    busted.api[key] = nil
    environment.set(key, nil)
  end

  function busted.register(descriptor, executor, attributes)
    local alias = nil
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

    local publisher = function(name, fn)
      if not fn and type(name) == 'function' then
        fn = name
        name = alias
      elseif not fn then
        fn = attributes and attributes.default_fn
      end

      local trace

      local ctx = busted.context.get()
      if busted.context.parent(ctx) then
        trace = busted.getTrace(ctx, 3, name)
      end

      local publish = function(f)
        busted.publish({ 'register', descriptor }, name, f, trace, attributes)
      end

      if fn then
        publish(fn)
      else
        return publish
      end
    end

    local edescriptor = alias or descriptor
    busted.executors[edescriptor] = publisher
    busted.export(edescriptor, publisher)

    busted.subscribe({ 'register', descriptor }, function(name, fn, trace, attr)
      local ctx = busted.context.get()
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

      busted.context.attach(plugin)

      if not ctx[descriptor] then
        ctx[descriptor] = { plugin }
      else
        ctx[descriptor][#ctx[descriptor] + 1] = plugin
      end
    end)
  end

  function busted.execute(current)
    if not current then
      current = busted.context.get()
    end
    for _, v in pairs(busted.context.children(current)) do
      local executor = executors[v.descriptor]
      if executor and not busted.skipAll then
        busted.safe(v.descriptor, function()
          executor(v)
        end, v)
      end
    end
  end

  return busted
end
