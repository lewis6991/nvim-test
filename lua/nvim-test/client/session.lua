local uv = vim.uv or vim.loop

--- @class test.Session
--- @field private _msgpack_rpc_stream test.MsgpackRpcStream
--- @field private _pending_messages string[]
--- @field private _prepare uv.uv_prepare_t
--- @field private _timer uv.uv_timer_t
--- @field private _is_running boolean
--- @field private _log_cb? fun(type: string, method: string, args: any[])
local M = {}
M.__index = M

local function resume(co, ...)
  local status, result = coroutine.resume(co, ...)

  if coroutine.status(co) == 'dead' then
    if not status then
      error(result)
    end
    return
  end

  assert(coroutine.status(co) == 'suspended')
  result(co)
end

local function coroutine_exec(func, ...)
  local args = { ... }
  local on_complete --- @type function?

  if #args > 0 and type(args[#args]) == 'function' then
    -- completion callback
    on_complete = table.remove(args)
  end

  resume(coroutine.create(function()
    local status, result, flag = pcall(func, unpack(args))
    if on_complete then
      coroutine.yield(function()
        -- run the completion callback on the main thread
        on_complete(status, result, flag)
      end)
    end
  end))
end

---@param stream test.MsgpackRpcStream
---@param log_cb? fun(type: string, method: string, args: any[])
---@return test.Session
function M.new(stream, log_cb)
  return setmetatable({
    _msgpack_rpc_stream = stream,
    _pending_messages = {},
    _prepare = uv.new_prepare(),
    _timer = uv.new_timer(),
    _log_cb = log_cb,
    _is_running = false,
  }, M)
end

--- @param timeout integer
--- @return string
function M:next_message(timeout)
  if self._is_running then
    error('Event loop already running')
  end

  if #self._pending_messages > 0 then
    return table.remove(self._pending_messages, 1)
  end

  local function on_request(method, args, response)
    table.insert(self._pending_messages, { 'request', method, args, response })
    uv.stop()
  end

  local function on_notification(method, args)
    table.insert(self._pending_messages, { 'notification', method, args })
    uv.stop()
  end

  self:_run(on_request, on_notification, timeout)
  return table.remove(self._pending_messages, 1)
end

function M:notify(method, ...)
  self._msgpack_rpc_stream:write(method, { ... })
end

function M:request(method, ...)
  local args = { ... }
  local err, result
  if self._is_running then
    err, result = self:_yielding_request(method, args)
  else
    err, result = self:_blocking_request(method, args)
  end

  if err then
    return false, err
  end

  return true, result
end

---@param request_cb fun()?
---@param notification_cb fun()?
---@param setup_cb fun()?
---@param timeout integer?
function M:run(request_cb, notification_cb, setup_cb, timeout)
  local function on_request(method, args, response)
    coroutine_exec(request_cb, method, args, function(status, result, flag)
      if status then
        response:send(result, flag)
      else
        response:send(result, true)
      end
    end)
  end

  local function on_notification(method, args)
    coroutine_exec(notification_cb, method, args)
  end

  self._is_running = true

  if setup_cb then
    coroutine_exec(setup_cb)
  end

  while #self._pending_messages > 0 do
    local msg = table.remove(self._pending_messages, 1)
    if msg[1] == 'request' then
      on_request(msg[2], msg[3], msg[4])
    else
      on_notification(msg[2], msg[3])
    end
  end

  self:_run(on_request, on_notification, timeout)
  self._is_running = false
end

function M:stop()
  uv.stop()
end

function M:close(signal)
  if not self._timer:is_closing() then
    self._timer:close()
  end
  if not self._prepare:is_closing() then
    self._prepare:close()
  end
  self._msgpack_rpc_stream:close(signal)
end

--- @private
--- @param method string
--- @param args any[]
--- @return any
function M:_yielding_request(method, args)
  --- @param co thread
  return coroutine.yield(function(co)
    self._msgpack_rpc_stream:write(method, args, function(err, result)
      resume(co, err, result)
    end)
  end)
end

--- @private
--- @param method string
--- @param args any[]
--- @return [integer, string]?, any?
function M:_blocking_request(method, args)
  --- @type [integer, string]?, any?
  local err, result

  local function on_request(method_, args_, response)
    table.insert(self._pending_messages, { 'request', method_, args_, response })
  end

  local function on_notification(method_, args_)
    table.insert(self._pending_messages, { 'notification', method_, args_ })
  end

  self._msgpack_rpc_stream:write(method, args, function(e, r)
    err = e
    result = r
    uv.stop()
  end)

  self:_run(on_request, on_notification)
  return (err or self.eof_err), result
end

--- @private
--- @param request_cb function
--- @param notification_cb function
--- @param timeout? integer
function M:_run(request_cb, notification_cb, timeout)
  if type(timeout) == 'number' then
    self._prepare:start(function()
      self._timer:start(timeout, 0, function()
        uv.stop()
      end)
      self._prepare:stop()
    end)
  end

  local request_cb_logged = function(...)
    if self._log_cb then
      self._log_cb(...)
    end
    return request_cb(...)
  end

  local notification_cb_logged = function(...)
    if self._log_cb then
      self._log_cb(...)
    end
    return notification_cb(...)
  end

  self._msgpack_rpc_stream:read_start(request_cb_logged, notification_cb_logged, function()
    uv.stop()
    self.eof_err = { 1, 'EOF was received from Nvim. Likely the Nvim process crashed.' }
  end)
  uv.run()
  self._prepare:stop()
  self._timer:stop()
  self._msgpack_rpc_stream:read_stop()
end

return M
