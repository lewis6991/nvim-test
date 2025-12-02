--- Block is the coordinator for busted lifecycle hooks inside the current
--- context tree. It owns the root context captured at construction time,
--- surfaces helper utilities for sorting runnable elements, and drives hook
--- execution through `busted:safe`.
---
--- Responsibilities:
--- - Sync descendant environments with the root before invoking hooks so that
---   descriptors resolve to their canonical implementations.
--- - Reject descriptors when a nested context tries to register lifecycle
---   handlers that are already defined higher in the tree to prevent invalid
---   nesting patterns.
--- - Execute lifecycle entries in ancestor-first order, caching their success
---   state to ensure each descriptor runs at most once per node.
--- - Provide structured error surfacing by routing invocations through the
---   busted executor, which wraps hooks with error handling.
---
--- Example:
--- ```lua
--- local block = Block.new(busted)
--- block:execAllOnce('before_each', busted.context:get(), function(desc)
---   print(('failed %s hook'):format(desc))
--- end)
--- ```

--- @param elements busted.Element[]
--- @return busted.Element[]
local function sort(elements)
  table.sort(elements, function(t1, t2)
    if t1.name and t2.name then
      return t1.name < t2.name
    end
    return t2.name ~= nil
  end)
  return elements
end

--- @class busted.BlockLifecycle
--- @field success? boolean
--- @field [integer] busted.BlockRuntimeElement

--- @class busted.BlockRuntimeElement: busted.Element
--- @field env? table<string, fun(...: any): any>
--- @field lazy_setup? { success?: boolean }
--- @field [string] busted.BlockLifecycle?
--- @field run? busted.CallableValue

--- @param callable busted.CallableValue?
--- @return (fun(...: any): any)?
local function to_function(callable)
  if type(callable) == 'function' then
    return callable
  end
  if not callable then
    return nil
  end
  local mt = getmetatable(callable)
  local call = mt and mt.__call
  return type(call) == 'function' and call or nil
end

--- @class busted.Block
--- @field private _busted busted.Busted
--- @field private _root busted.BlockRuntimeElement
local M = {}
M.__index = M

--- @param busted busted.Busted
--- @return busted.Block
function M.new(busted)
  local root = busted.context:get()
  --- @cast root busted.BlockRuntimeElement
  return setmetatable({
    _busted = busted,
    _root = root,
  }, M)
end

--- @param descriptor string
--- @param element busted.Element
function M:reject(descriptor, element)
  local _ = self
  --- @cast element busted.BlockRuntimeElement
  local env = element.env
  if not env then
    env = {}
    element.env = env
  end
  env[descriptor] = function(...)
    error("'" .. descriptor .. "' not supported inside current context block", 2)
  end
end

--- @param element busted.Element
function M:rejectAll(element)
  --- @cast element busted.BlockRuntimeElement
  local run = element.run
  local fn = to_function(run)
  if not fn then
    return
  end
  local env = getfenv(fn)
  local root = self._root
  local executors = self._busted.executors
  local root_env = root.env
  if not root_env then
    return
  end
  for descriptor, _ in pairs(executors) do
    if root_env[descriptor] and (env ~= _G and env[descriptor] or rawget(env, descriptor)) then
      self:reject(descriptor, element)
    end
  end
end

--- @param descriptor string
--- @param element busted.Element
--- @return busted.Status status
--- @return any ...
function M:_exec(descriptor, element)
  --- @cast element busted.BlockRuntimeElement
  local env = element.env
  if not env then
    env = {}
    element.env = env
  end
  self:rejectAll(element)
  local run = element.run
  if not run then
    error(('missing runnable for %s'):format(tostring(descriptor)), 2)
  end
  return self._busted:safe(descriptor, run, element)
end

--- @param descriptor string
--- @param current busted.Element
--- @param err? fun(descriptor: string)
--- @return boolean
function M:execAllOnce(descriptor, current, err)
  --- @cast current busted.BlockRuntimeElement
  local context = self._busted.context
  local parent = context:parent(current)

  if parent then
    local success = self:execAllOnce(descriptor, parent, err)
    if not success then
      return success
    end
  end

  local list = current[descriptor]
  if not list then
    --- @type busted.BlockLifecycle
    local new_list = {}
    current[descriptor] = new_list
    list = new_list
  end
  --- @cast list busted.BlockLifecycle
  if list.success ~= nil then
    return list.success
  end

  local success = true
  for _, v in ipairs(list) do
    if not self:_exec(descriptor, v):success() then
      if err then
        err(descriptor)
      end
      success = false
    end
  end

  list.success = success

  return success
end

--- @param descriptor string
--- @param current busted.Element
--- @param propagate? boolean
--- @param err? fun(descriptor: string)
--- @return boolean, busted.Element
function M:execAll(descriptor, current, propagate, err)
  --- @cast current busted.BlockRuntimeElement
  local context = self._busted.context
  local parent = context:parent(current)

  if propagate and parent then
    local success, ancestor = self:execAll(descriptor, parent, propagate, err)
    if not success then
      return success, ancestor
    end
  end

  local list = current[descriptor]
  if not list then
    --- @type busted.BlockLifecycle
    local placeholder = {}
    list = placeholder
  end
  --- @cast list busted.BlockLifecycle

  local success = true
  for _, v in ipairs(list) do
    if not self:_exec(descriptor, v):success() then
      if err then
        err(descriptor)
      end
      success = false
    end
  end
  return success, current
end

--- @param descriptor string
--- @param current busted.Element
--- @param propagate? boolean
--- @param err? fun(descriptor: string)
--- @return boolean
function M:dexecAll(descriptor, current, propagate, err)
  --- @cast current busted.BlockRuntimeElement
  local context = self._busted.context
  local parent = context:parent(current)
  local list = current[descriptor]
  if not list then
    --- @type busted.BlockLifecycle
    local placeholder = {}
    list = placeholder
  end
  --- @cast list busted.BlockLifecycle

  local success = true
  for _, v in ipairs(list) do
    if not self:_exec(descriptor, v):success() then
      if err then
        err(descriptor)
      end
      success = false
    end
  end

  if propagate and parent then
    if not self:dexecAll(descriptor, parent, propagate, err) then
      success = false
    end
  end
  return success
end

--- @param element busted.Element
--- @param err? fun(descriptor: string)
--- @return boolean
function M:lazySetup(element, err)
  --- @cast element busted.BlockRuntimeElement
  return self:execAllOnce('lazy_setup', element, err)
end

--- @param element busted.Element
--- @param err? fun(descriptor: string)
function M:lazyTeardown(element, err)
  --- @cast element busted.BlockRuntimeElement
  if element.lazy_setup and element.lazy_setup.success ~= nil then
    self:dexecAll('lazy_teardown', element, nil, err)
    element.lazy_setup.success = nil
  end
end

--- @param element busted.Element
--- @param err? fun(descriptor: string)
--- @return boolean
function M:setup(element, err)
  --- @cast element busted.BlockRuntimeElement
  local success = self:execAll('strict_setup', element, nil, err)
  return success
end

--- @param element busted.Element
--- @param err? fun(descriptor: string)
--- @return boolean
function M:teardown(element, err)
  --- @cast element busted.BlockRuntimeElement
  return self:dexecAll('strict_teardown', element, nil, err)
end

--- @param descriptor string
--- @param element busted.Element
function M:execute(descriptor, element)
  --- @cast element busted.BlockRuntimeElement
  if not element.env then
    element.env = {}
  end

  local run = element.run
  if not run then
    return
  end

  if self._busted:safe(descriptor, run, element):success() then
    sort(self._busted.context:children(element))

    if self:setup(element) then
      self._busted:execute(element)
    end

    self:lazyTeardown(element)
    self:teardown(element)
  end
end

return M
