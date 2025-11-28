local unpack = table.unpack or unpack
local table_insert = table.insert

local registry = {}

local s = {
  _COPYRIGHT = 'Copyright (c) 2012 Olivine Labs, LLC.',
  _DESCRIPTION = 'A simple string key/value store for string templates.',
  _VERSION = 'Say 1.3',

  set = function(self, key, value)
    registry[key] = value
  end,
}

local __meta = {
  __call = function(_, key, vars)
    if vars ~= nil and type(vars) ~= 'table' then
      error(("expected parameter table to be a table, got '%s'"):format(type(vars)), 2)
    end

    vars = vars or {}
    vars.n = math.max((vars.n or 0), #vars)

    local str = registry[key]
    if str == nil then
      return nil
    end

    str = tostring(str)
    local strings = {}

    for i = 1, vars.n or #vars do
      table_insert(strings, tostring(vars[i]))
    end

    return #strings > 0 and str:format(unpack(strings)) or str
  end,

  __index = function(_, key)
    return registry[key]
  end,
}

s._registry = registry

return setmetatable(s, __meta)
