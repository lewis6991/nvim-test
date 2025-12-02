--- @alias busted.StatusInput string|boolean|nil
--- @alias busted.StatusValue 'success'|'pending'|'failure'|'error'
--- @alias busted.StatusLike busted.StatusInput|busted.Status

local STATUS_MAP = {
  ['success'] = 'success',
  ['pending'] = 'pending',
  ['failure'] = 'failure',
  ['error'] = 'error',
  ['true'] = 'success',
  ['false'] = 'failure',
  ['nil'] = 'error',
} ---@type table<string, busted.StatusValue>

--- @param status busted.StatusLike
--- @return busted.StatusValue
local function normalize_status(status)
  return STATUS_MAP[tostring(status)] or 'error'
end

--- @class busted.Status
--- @field private _status busted.StatusValue
local M = {}
M.__index = M

--- @private
--- @return string
function M:__tostring()
  return self._status
end

--- @param initial_status? busted.StatusLike
--- @return busted.Status
function M.new(initial_status)
  local instance = {
    _status = normalize_status(initial_status),
  }

  return setmetatable(instance, M)
end

--- @return boolean
function M:success()
  return self._status == 'success'
end

--- @return boolean
function M:pending()
  return self._status == 'pending'
end

--- @return boolean
function M:failure()
  return self._status == 'failure'
end

--- @return boolean
function M:error()
  return self._status == 'error'
end

--- @return busted.StatusValue
function M:get()
  return self._status
end

--- @param status busted.StatusLike
function M:set(status)
  self._status = normalize_status(status)
end

--- @param status busted.StatusLike
function M:update(status)
  local next_status = normalize_status(status)
  if self._status == 'success' or (self._status == 'pending' and next_status ~= 'success') then
    self._status = next_status
  end
end

setmetatable(M, {
  __call = function(_, initial_status)
    return M.new(initial_status)
  end,
})

return M
