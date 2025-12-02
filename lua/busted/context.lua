local function shallow_copy(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = v
  end
  return copy
end

local function save()
  local g = {}
  for k, _ in next, _G, nil do
    g[k] = rawget(_G, k)
  end
  return {
    gmt = debug.getmetatable(_G),
    g = g,
    loaded = shallow_copy(package.loaded),
  }
end

local function restore(state)
  setmetatable(_G, state.gmt)
  for k, _ in next, _G, nil do
    rawset(_G, k, state.g[k])
  end
  for k, v in next, state.g, nil do
    if rawget(_G, k) == nil then
      rawset(_G, k, v)
    end
  end
  for k, _ in pairs(package.loaded) do
    package.loaded[k] = state.loaded[k]
  end
end

local PUBLIC_METHODS = {
  'get',
  'set',
  'clear',
  'attach',
  'children',
  'parent',
  'push',
  'pop',
}

local function bind_method(instance, method)
  return function(arg1, ...)
    if arg1 == instance then
      return method(instance, ...)
    end
    return method(instance, arg1, ...)
  end
end

--- @class busted.ContextRef
--- @field private _data table
--- @field private _parents table<table, table>
--- @field private _children table<table, table[]>

--- @class busted.Context
--- @field private _data table
--- @field private _parents table<table, table>
--- @field private _children table<table, table[]>
--- @field private _stack table[]
--- @field private _states table[]
--- @field private _current table
local M = {}
M.__index = M

--- @return busted.Context
function M.new()
  local self = setmetatable({
    _data = { descriptor = 'suite', attributes = {} },
    _parents = {},
    _children = {},
    _stack = {},
    _states = {},
  }, M)

  self._current = self._data
  self:_bind_methods()

  return self
end

--- @private
function M:_bind_methods()
  for _, name in ipairs(PUBLIC_METHODS) do
    local method = M[name]
    if not method then
      error('missing context method: ' .. name)
    end
    self[name] = bind_method(self, method)
  end
end

function M:_unwrap(element, levels)
  levels = levels or 1
  local parent = element
  for _ = 1, levels do
    parent = self:parent(parent)
    if not parent then
      break
    end
  end
  if not element.env then
    element.env = {}
  end
  setmetatable(element.env, {
    __newindex = function(_, key, value)
      if not parent then
        _G[key] = value
      else
        if not parent.env then
          parent.env = {}
        end
        parent.env[key] = value
      end
    end,
  })
end

function M:_push_state(current)
  local state
  if current.attributes.envmode == 'insulate' then
    state = save()
  elseif current.attributes.envmode == 'unwrap' then
    self:_unwrap(current)
  elseif current.attributes.envmode == 'expose' then
    self:_unwrap(current, 2)
  end
  table.insert(self._states, state)
end

function M:_pop_state(current)
  local state = table.remove(self._states)
  if current.attributes.envmode == 'expose' then
    local idx = #self._states
    if idx > 0 then
      local previous = self._states[idx]
      if previous then
        self._states[idx] = save()
      end
    end
  end
  if state ~= nil then
    restore(state)
  end
end

--- @param key? string
--- @return busted.Element
function M:get(key)
  if not key then
    return self._current
  end
  return self._current[key]
end

function M:set(key, value)
  self._current[key] = value
end

function M:clear()
  self._data = { descriptor = 'suite', attributes = {} }
  self._parents = {}
  self._children = {}
  self._stack = {}
  self._states = {}
  self._current = self._data
end

function M:attach(child)
  if not self._children[self._current] then
    self._children[self._current] = {}
  end
  self._parents[child] = self._current
  table.insert(self._children[self._current], child)
end

function M:children(parent)
  return self._children[parent] or {}
end

function M:parent(child)
  return self._parents[child]
end

function M:push(current)
  if not self._parents[current] and current ~= self._data then
    error('Detached child. Cannot push.')
  end
  if self._current ~= current then
    self:_push_state(current)
  end
  table.insert(self._stack, self._current)
  self._current = current
end

function M:pop()
  local current = self._current
  self._current = table.remove(self._stack)
  if self._current ~= current then
    self:_pop_state(current)
  end
  if not self._current then
    error('Context stack empty. Cannot pop.')
  end
end

return M
