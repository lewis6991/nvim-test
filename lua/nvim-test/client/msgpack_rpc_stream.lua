--- @alias test.MessageType 'request'|'notification'|'response'

--- @class vim.mpack.Session
--- @field receive fun(self, data: string, pos: integer): type: test.MessageType, id_or_cb: integer|function, method_or_error: string, args_or_result: any[], pos: integer
--- @field request fun(self, ...)
--- @field notify fun(self, ...)
--- @field reply fun(self, id: integer)

--- @class vim.mpack.Packer

--- @class vim.mpack.Unacker

--- @class vim.mpack
--- @field encode fun(obj: any): string
--- @field decode fun(obj: string): any
--- @field Packer fun(opts): vim.mpack.Packer
--- @field Session fun(opts): vim.mpack.Session
--- @field Unpacker fun(opts): vim.mpack.Unacker
--- @field NIL userdata vim.NIL
local mpack = vim.mpack

--- @class test.MsgpackRpcStream
--- @field package _stream test.ProcessStream
--- @field package _session vim.mpack.Session
--- @field package _pack vim.mpack.Packer
local M = {}
M.__index = M

function M.new(stream)
  return setmetatable({
    _stream = stream,
    _pack = mpack.Packer(),
    _session = mpack.Session({
      unpack = mpack.Unpacker({
        ext = {
          -- Buffer
          [0] = function(_c, s)
            return mpack.decode(s)
          end,
          -- Window
          [1] = function(_c, s)
            return mpack.decode(s)
          end,
          -- Tabpage
          [2] = function(_c, s)
            return mpack.decode(s)
          end,
        },
      }),
    }),
  }, M)
end

--- @param method string
--- @param args any[]
--- @param response_cb? function
function M:write(method, args, response_cb)
  local data --- @type string[]
  if response_cb then
    assert(type(response_cb) == 'function')
    data = { self._session:request(response_cb) }
  else
    data = { self._session:notify() }
  end

  data[#data + 1] = self._pack(method)
  data[#data + 1] = self._pack(args)

  self._stream:write(table.concat(data))
end

--- @private
--- @param id integer
--- @param value any
--- @param is_error boolean
function M:_respond(id, value, is_error)
  --- @type string[]
  local data = { self._session:reply(id) }
  if is_error then
    data[#data + 1] = self._pack(value)
    data[#data + 1] = self._pack(mpack.NIL)
  else
    data[#data + 1] = self._pack(mpack.NIL)
    data[#data + 1] = self._pack(value)
  end
  self._stream:write(table.concat(data))
end

--- @param request_cb fun(method: string, args: any[], resp: fun(value: any, is_error: boolean))
--- @param notification_cb fun(method: string, args: any[])
--- @param eof_cb any
function M:read_start(request_cb, notification_cb, eof_cb)
  self._stream:read_start(function(data)
    if not data then
      return eof_cb()
    end

    local pos, len = 1, #data

    while pos <= len do
      local type, id_or_cb, method_or_error, args_or_result, pos0 = self._session:receive(data, pos)
      pos = pos0

      if type == 'request' then
        assert(type(id_or_cb) == 'number')
        request_cb(method_or_error, args_or_result, function(value, is_error)
          self:_respond(id_or_cb, value, is_error)
        end)
      elseif type == 'notification' then
        notification_cb(method_or_error, args_or_result)
      elseif type == 'response' then
        if method_or_error == mpack.NIL then
          id_or_cb(nil, args_or_result)
        else
          id_or_cb(method_or_error)
        end
      end
    end
  end)
end

function M:read_stop()
  self._stream:read_stop()
end

function M:close(signal)
  self._stream:close(signal)
end

return M
