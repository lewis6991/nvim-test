local setfenv = _G.setfenv

--- @class busted.Environment
--- @field context busted.Context
--- @field _env table<string, any>
local M = {}
M.__index = M

--- @param context busted.Context
--- @return busted.Environment
function M.new(context)
  local self = setmetatable({
    context = context,
    _env = {},
  }, M)

  local function env_index(_, key)
    return self:_getEnvValue(self.context:get(), key) or _G[key]
  end

  local function env_newindex(_, key, value)
    local node = self.context:get()
    node.env = node.env or {}
    node.env[key] = value
  end

  setmetatable(self._env, { __index = env_index, __newindex = env_newindex })

  return self
end

function M:_getEnvValue(node, key)
  if not node then
    return
  end

  local value = node.env and node.env[key]
  if value then
    return value
  end

  return self:_getEnvValue(self.context:parent(node), key)
end

--- @param fn function
function M:wrap(fn)
  setfenv(fn, self._env)
end

function M:set(key, value)
  local current_env = self.context:get('env')

  if not current_env then
    current_env = {}
    self.context:set('env', current_env)
  end

  current_env[key] = value
end

return M
