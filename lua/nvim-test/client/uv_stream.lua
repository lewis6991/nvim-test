local uv = (vim and vim.uv) or error('nvim-test requires vim.uv')

--- @class test.ProcessStream
--- @field private _proc uv.uv_process_t
--- @field private _pid integer
--- @field private _stdin uv.uv_pipe_t
--- @field private _stdout uv.uv_pipe_t
--- @field private _closed true?
--- @field signal integer
--- @field status integer
local M = {}

--- @param argv string[]
--- @return test.ProcessStream
function M.spawn(argv)
  --- @type test.ProcessStream
  local self = setmetatable({
    _stdin = uv.new_pipe(false),
    _stdout = uv.new_pipe(false),
  }, { __index = M })

  local prog = argv[1]
  if type(prog) ~= 'string' then
    error('argv[1] must be the program path')
  end
  local args = vim.list_slice(argv, 2)

  --- @diagnostic disable-next-line:missing-fields
  self._proc, self._pid = uv.spawn(prog, {
    stdio = { self._stdin, self._stdout, 2 },
    args = args,
  }, function(status, signal)
    self.status = status
    self.signal = signal
  end)

  if not self._proc then
    local err = self._pid
    error(err)
  end

  return self
end

function M:write(data)
  self._stdin:write(data)
end

function M:read_start(cb)
  self._stdout:read_start(function(err, chunk)
    if err then
      error(err)
    end
    cb(chunk)
  end)
end

function M:read_stop()
  self._stdout:read_stop()
end

--- @param signal string
--- @return integer?
--- @return integer?
function M:close(signal)
  if self._closed then
    return
  end
  self._closed = true
  self:read_stop()
  self._stdin:close()
  self._stdout:close()
  if type(signal) == 'string' then
    self._proc:kill('sig' .. signal)
  end
  while self.status == nil do
    uv.run('once')
  end
  return self.status, self.signal
end

return M
