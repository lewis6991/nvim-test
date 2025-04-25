--- Extended operations on Lua tables.
--
-- See @{02-arrays.md.Useful_Operations_on_Tables|the Guide}
--
-- Dependencies: `pl.utils`, `pl.types`
-- @module pl.tablex
local utils = require('pl.utils')
local types = require('pl.types')
local getmetatable, setmetatable, require = getmetatable, setmetatable, require
local tsort, append, remove = table.sort, table.insert, table.remove
local min = math.min
local pairs, type, unpack, select, tostring = pairs, type, utils.unpack, select, tostring
local function_arg = utils.function_arg
local assert_arg = utils.assert_arg

local tablex = {}

-- -- generally, functions that make copies of tables try to preserve the metatable.
-- -- However, when the source has no obvious type, then we attach appropriate metatables
-- -- like List, Map, etc to the result.
-- local function setmeta(res, tbl, pl_class)
--   local mt = getmetatable(tbl) or pl_class and require('pl.' .. pl_class)
--   return mt and setmetatable(res, mt) or res
-- end

local function makelist(l)
  return setmetatable(l, require('pl.List'))
end

-- local function makemap(m)
--   return setmetatable(m, require('pl.Map'))
-- end

local function complain(idx, msg)
  error(('argument %d is not %s'):format(idx, msg), 3)
end

local function assert_arg_indexable(idx, val)
  if not types.is_indexable(val) then
    complain(idx, 'indexable')
  end
end

local function assert_arg_iterable(idx, val)
  if not types.is_iterable(val) then
    complain(idx, 'iterable')
  end
end

local function assert_arg_writeable(idx, val)
  if not types.is_writeable(val) then
    complain(idx, 'writeable')
  end
end

--- copy a table into another, in-place.
-- @within Copying
-- @tab t1 destination table
-- @tab t2 source (actually any iterable object)
-- @return first table
function tablex.update(t1, t2)
  assert_arg_writeable(1, t1)
  assert_arg_iterable(2, t2)
  for k, v in pairs(t2) do
    t1[k] = v
  end
  return t1
end

--- total number of elements in this table.
-- Note that this is distinct from `#t`, which is the number
-- of values in the array part; this value will always
-- be greater or equal. The difference gives the size of
-- the hash part, for practical purposes. Works for any
-- object with a __pairs metamethod.
-- @tab t a table
-- @return the size
function tablex.size(t)
  assert_arg_iterable(1, t)
  local i = 0
  for k in pairs(t) do
    i = i + 1
  end
  return i
end

--- make a shallow copy of a table
-- @within Copying
-- @tab t an iterable source
-- @return new table
function tablex.copy(t)
  assert_arg_iterable(1, t)
  local res = {}
  for k, v in pairs(t) do
    res[k] = v
  end
  return res
end

local function cycle_aware_copy(t, cache)
  if type(t) ~= 'table' then
    return t
  end
  if cache[t] then
    return cache[t]
  end
  assert_arg_iterable(1, t)
  local res = {}
  cache[t] = res
  local mt = getmetatable(t)
  for k, v in pairs(t) do
    k = cycle_aware_copy(k, cache)
    v = cycle_aware_copy(v, cache)
    res[k] = v
  end
  setmetatable(res, mt)
  return res
end

--- make a deep copy of a table, recursively copying all the keys and fields.
-- This supports cycles in tables; cycles will be reproduced in the copy.
-- This will also set the copied table's metatable to that of the original.
-- @within Copying
-- @tab t A table
-- @return new table
function tablex.deepcopy(t)
  return cycle_aware_copy(t, {})
end

local abs = math.abs

local function cycle_aware_compare(t1, t2, ignore_mt, eps, cache)
  if cache[t1] and cache[t1][t2] then
    return true
  end
  local ty1 = type(t1)
  local ty2 = type(t2)
  if ty1 ~= ty2 then
    return false
  end
  -- non-table types can be directly compared
  if ty1 ~= 'table' then
    if ty1 == 'number' and eps then
      return abs(t1 - t2) < eps
    end
    return t1 == t2
  end
  -- as well as tables which have the metamethod __eq
  local mt = getmetatable(t1)
  if not ignore_mt and mt and mt.__eq then
    return t1 == t2
  end
  for k1 in pairs(t1) do
    if t2[k1] == nil then
      return false
    end
  end
  for k2 in pairs(t2) do
    if t1[k2] == nil then
      return false
    end
  end
  cache[t1] = cache[t1] or {}
  cache[t1][t2] = true
  for k1, v1 in pairs(t1) do
    local v2 = t2[k1]
    if not cycle_aware_compare(v1, v2, ignore_mt, eps, cache) then
      return false
    end
  end
  return true
end

--- compare two values.
-- if they are tables, then compare their keys and fields recursively.
-- @within Comparing
-- @param t1 A value
-- @param t2 A value
-- @bool[opt] ignore_mt if true, ignore __eq metamethod (default false)
-- @number[opt] eps if defined, then used for any number comparisons
-- @return true or false
function tablex.deepcompare(t1, t2, ignore_mt, eps)
  return cycle_aware_compare(t1, t2, ignore_mt, eps, {})
end

--- compare two arrays using a predicate.
-- @within Comparing
-- @array t1 an array
-- @array t2 an array
-- @func cmp A comparison function; `bool = cmp(t1_value, t2_value)`
-- @return true or false
-- @usage
-- assert(tablex.compare({ 1, 2, 3 }, { 1, 2, 3 }, "=="))
--
-- assert(tablex.compare(
--    {1,2,3, hello = "world"},  -- fields are not compared!
--    {1,2,3}, function(v1, v2) return v1 == v2 end)
function tablex.compare(t1, t2, cmp)
  assert_arg_indexable(1, t1)
  assert_arg_indexable(2, t2)
  if #t1 ~= #t2 then
    return false
  end
  cmp = function_arg(3, cmp)
  for k = 1, #t1 do
    if not cmp(t1[k], t2[k]) then
      return false
    end
  end
  return true
end

--- compare two list-like tables using an optional predicate, without regard for element order.
-- @within Comparing
-- @array t1 a list-like table
-- @array t2 a list-like table
-- @param cmp A comparison function (may be nil)
function tablex.compare_no_order(t1, t2, cmp)
  assert_arg_indexable(1, t1)
  assert_arg_indexable(2, t2)
  if cmp then
    cmp = function_arg(3, cmp)
  end
  if #t1 ~= #t2 then
    return false
  end
  local visited = {}
  for i = 1, #t1 do
    local val = t1[i]
    local gotcha
    for j = 1, #t2 do
      if not visited[j] then
        local match
        if cmp then
          match = cmp(val, t2[j])
        else
          match = val == t2[j]
        end
        if match then
          gotcha = j
          break
        end
      end
    end
    if not gotcha then
      return false
    end
    visited[gotcha] = true
  end
  return true
end

--- return the index of a value in a list.
-- Like string.find, there is an optional index to start searching,
-- which can be negative.
-- @within Finding
-- @array t A list-like table
-- @param val A value
-- @int idx index to start; -1 means last element,etc (default 1)
-- @return index of value or nil if not found
-- @usage find({10,20,30},20) == 2
-- @usage find({'a','b','a','c'},'a',2) == 3
function tablex.find(t, val, idx)
  assert_arg_indexable(1, t)
  idx = idx or 1
  if idx < 0 then
    idx = #t + idx + 1
  end
  for i = idx, #t do
    if t[i] == val then
      return i
    end
  end
  return nil
end

--- return the index of a value in a list, searching from the end.
-- Like string.find, there is an optional index to start searching,
-- which can be negative.
-- @within Finding
-- @array t A list-like table
-- @param val A value
-- @param idx index to start; -1 means last element,etc (default `#t`)
-- @return index of value or nil if not found
-- @usage rfind({10,10,10},10) == 3
function tablex.rfind(t, val, idx)
  assert_arg_indexable(1, t)
  idx = idx or #t
  if idx < 0 then
    idx = #t + idx + 1
  end
  for i = idx, 1, -1 do
    if t[i] == val then
      return i
    end
  end
  return nil
end

--- return the index (or key) of a value in a table using a comparison function.
--
-- *NOTE*: the 2nd return value of this function, the value returned
-- by the comparison function, has a limitation that it cannot be `false`.
-- Because if it is, then it indicates the comparison failed, and the
-- function will continue the search. See examples.
-- @within Finding
-- @tab t A table
-- @func cmp A comparison function
-- @param arg an optional second argument to the function
-- @return index of value, or nil if not found
-- @return value returned by comparison function (cannot be `false`!)
-- @usage
-- -- using an operator
-- local lst = { "Rudolph", true, false, 15 }
-- local idx, cmp_result = tablex.rfind(lst, "==", "Rudolph")
-- assert(idx == 1)
-- assert(cmp_result == true)
--
-- local idx, cmp_result = tablex.rfind(lst, "==", false)
-- assert(idx == 3)
-- assert(cmp_result == true)       -- looking up 'false' works!
--
-- -- using a function returning the value looked up
-- local cmp = function(v1, v2) return v1 == v2 and v2 end
-- local idx, cmp_result = tablex.rfind(lst, cmp, "Rudolph")
-- assert(idx == 1)
-- assert(cmp_result == "Rudolph")  -- the value is returned
--
-- -- NOTE: this fails, since 'false' cannot be returned!
-- local idx, cmp_result = tablex.rfind(lst, cmp, false)
-- assert(idx == nil)               -- looking up 'false' failed!
-- assert(cmp_result == nil)
function tablex.find_if(t, cmp, arg)
  assert_arg_iterable(1, t)
  cmp = function_arg(2, cmp)
  for k, v in pairs(t) do
    local c = cmp(v, arg)
    if c then
      return k, c
    end
  end
  return nil
end

--- return a list of all values in a table indexed by another list.
-- @tab tbl a table
-- @array idx an index table (a list of keys)
-- @return a list-like table
-- @usage index_by({10,20,30,40},{2,4}) == {20,40}
-- @usage index_by({one=1,two=2,three=3},{'one','three'}) == {1,3}
function tablex.index_by(tbl, idx)
  assert_arg_indexable(1, tbl)
  assert_arg_indexable(2, idx)
  local res = {}
  for i = 1, #idx do
    res[i] = tbl[idx[i]]
  end
  return setmeta(res, tbl, 'List')
end

--- apply a function to all values of a table.
-- This returns a table of the results.
-- Any extra arguments are passed to the function.
-- @within MappingAndFiltering
-- @func fun A function that takes at least one argument
-- @tab t A table
-- @param ... optional arguments
-- @usage map(function(v) return v*v end, {10,20,30,fred=2}) is {100,400,900,fred=4}
function tablex.map(fun, t, ...)
  assert_arg_iterable(1, t)
  fun = function_arg(1, fun)
  local res = {}
  for k, v in pairs(t) do
    res[k] = fun(v, ...)
  end
  return setmeta(res, t)
end

--- apply a function to all values of a list.
-- This returns a table of the results.
-- Any extra arguments are passed to the function.
-- @within MappingAndFiltering
-- @func fun A function that takes at least one argument
-- @array t a table (applies to array part)
-- @param ... optional arguments
-- @return a list-like table
-- @usage imap(function(v) return v*v end, {10,20,30,fred=2}) is {100,400,900}
function tablex.imap(fun, t, ...)
  assert_arg_indexable(1, t)
  fun = function_arg(1, fun)
  local res = {}
  for i = 1, #t do
    res[i] = fun(t[i], ...) or false
  end
  return setmeta(res, t, 'List')
end

--- apply a named method to values from a table.
-- @within MappingAndFiltering
-- @string name the method name
-- @array t a list-like table
-- @param ... any extra arguments to the method
-- @return a `List` with the results of the method (1st result only)
-- @usage
-- local Car = {}
-- Car.__index = Car
-- function Car.new(car)
--   return setmetatable(car or {}, Car)
-- end
-- Car.speed = 0
-- function Car:faster(increase)
--   self.speed = self.speed + increase
--   return self.speed
-- end
--
-- local ferrari = Car.new{ name = "Ferrari" }
-- local lamborghini = Car.new{ name = "Lamborghini", speed = 50 }
-- local cars = { ferrari, lamborghini }
--
-- assert(ferrari.speed == 0)
-- assert(lamborghini.speed == 50)
-- tablex.map_named_method("faster", cars, 10)
-- assert(ferrari.speed == 10)
-- assert(lamborghini.speed == 60)
function tablex.map_named_method(name, t, ...)
  utils.assert_string(1, name)
  assert_arg_indexable(2, t)
  local res = {}
  for i = 1, #t do
    local val = t[i]
    local fun = val[name]
    res[i] = fun(val, ...)
  end
  return setmeta(res, t, 'List')
end

--- apply a function to all values of a table, in-place.
-- Any extra arguments are passed to the function.
-- @func fun A function that takes at least one argument
-- @tab t a table
-- @param ... extra arguments passed to `fun`
-- @see tablex.foreach
function tablex.transform(fun, t, ...)
  assert_arg_iterable(1, t)
  fun = function_arg(1, fun)
  for k, v in pairs(t) do
    t[k] = fun(v, ...)
  end
end

--- 'reduce' a list using a binary function.
-- @func fun a function of two arguments
-- @array t a list-like table
-- @array memo optional initial memo value. Defaults to first value in table.
-- @return the result of the function
-- @usage reduce('+',{1,2,3,4}) == 10
function tablex.reduce(fun, t, memo)
  fun = function_arg(1, fun)
  local n = #t
  if n == 0 then
    return memo
  end
  local res = memo and fun(memo, t[1]) or t[1]
  for i = 2, n do
    res = fun(res, t[i])
  end
  return res
end

local function _copy(dest, src, idest, isrc, nsrc, clean_tail)
  idest = idest or 1
  isrc = isrc or 1
  local iend
  if not nsrc then
    nsrc = #src
    iend = #src
  else
    iend = isrc + min(nsrc - 1, #src - isrc)
  end
  if dest == src then -- special case
    if idest > isrc and iend >= idest then -- overlapping ranges
      src = tablex.sub(src, isrc, nsrc)
      isrc = 1
      iend = #src
    end
  end
  for i = isrc, iend do
    dest[idest] = src[i]
    idest = idest + 1
  end
  if clean_tail then
    tablex.clear(dest, idest)
  end
  return dest
end

--- copy an array into another one, clearing `dest` after `idest+nsrc`, if necessary.
-- @within Copying
-- @array dest a list-like table
-- @array src a list-like table
-- @int[opt=1] idest where to start copying values into destination
-- @int[opt=1] isrc where to start copying values from source
-- @int[opt=#src] nsrc number of elements to copy from source
function tablex.icopy(dest, src, idest, isrc, nsrc)
  assert_arg_indexable(1, dest)
  assert_arg_indexable(2, src)
  return _copy(dest, src, idest, isrc, nsrc, true)
end

--- copy an array into another one.
-- @within Copying
-- @array dest a list-like table
-- @array src a list-like table
-- @int[opt=1] idest where to start copying values into destination
-- @int[opt=1] isrc where to start copying values from source
-- @int[opt=#src] nsrc number of elements to copy from source
function tablex.move(dest, src, idest, isrc, nsrc)
  assert_arg_indexable(1, dest)
  assert_arg_indexable(2, src)
  return _copy(dest, src, idest, isrc, nsrc, false)
end

function tablex._normalize_slice(self, first, last)
  local sz = #self
  if not first then
    first = 1
  end
  if first < 0 then
    first = sz + first + 1
  end
  -- make the range _inclusive_!
  if not last then
    last = sz
  end
  if last < 0 then
    last = sz + 1 + last
  end
  return first, last
end

--- Extract a range from a table, like  'string.sub'.
-- If first or last are negative then they are relative to the end of the list
-- eg. sub(t,-2) gives last 2 entries in a list, and
-- sub(t,-4,-2) gives from -4th to -2nd
-- @within Extraction
-- @array t a list-like table
-- @int first An index
-- @int last An index
-- @return a new List
function tablex.sub(t, first, last)
  assert_arg_indexable(1, t)
  first, last = tablex._normalize_slice(t, first, last)
  local res = {}
  for i = first, last do
    append(res, t[i])
  end
  return setmeta(res, t, 'List')
end

--- set an array range to a value. If it's a function we use the result
-- of applying it to the indices.
-- @array t a list-like table
-- @param val a value
-- @int[opt=1] i1 start range
-- @int[opt=#t] i2 end range
function tablex.set(t, val, i1, i2)
  assert_arg_indexable(1, t)
  i1, i2 = i1 or 1, i2 or #t
  if types.is_callable(val) then
    for i = i1, i2 do
      t[i] = val(i)
    end
  else
    for i = i1, i2 do
      t[i] = val
    end
  end
end

--- create a new array of specified size with initial value.
-- @int n size
-- @param val initial value (can be `nil`, but don't expect `#` to work!)
-- @return the table
function tablex.new(n, val)
  local res = {}
  tablex.set(res, val, 1, n)
  return res
end

--- clear out the contents of a table.
-- @array t a list
-- @param istart optional start position
function tablex.clear(t, istart)
  istart = istart or 1
  for i = istart, #t do
    remove(t)
  end
end

--- insert values into a table.
-- similar to `table.insert` but inserts values from given table `values`,
-- not the object itself, into table `t` at position `pos`.
-- @within Copying
-- @array t the list
-- @int[opt] position (default is at end)
-- @array values
function tablex.insertvalues(t, ...)
  assert_arg(1, t, 'table')
  local pos, values
  if select('#', ...) == 1 then
    pos, values = #t + 1, ...
  else
    pos, values = ...
  end
  if #values > 0 then
    for i = #t, pos, -1 do
      t[i + #values] = t[i]
    end
    local offset = 1 - pos
    for i = pos, pos + #values - 1 do
      t[i] = values[i + offset]
    end
  end
  return t
end

--- remove a range of values from a table.
-- End of range may be negative.
-- @array t a list-like table
-- @int i1 start index
-- @int i2 end index
-- @return the table
function tablex.removevalues(t, i1, i2)
  assert_arg(1, t, 'table')
  i1, i2 = tablex._normalize_slice(t, i1, i2)
  for i = i1, i2 do
    remove(t, i1)
  end
  return t
end

local _find
_find = function(t, value, tables)
  for k, v in pairs(t) do
    if v == value then
      return k
    end
  end
  for k, v in pairs(t) do
    if not tables[v] and type(v) == 'table' then
      tables[v] = true
      local res = _find(v, value, tables)
      if res then
        res = tostring(res)
        if type(k) ~= 'string' then
          return '[' .. k .. ']' .. res
        else
          return k .. '.' .. res
        end
      end
    end
  end
end

--- find a value in a table by recursive search.
-- @within Finding
-- @tab t the table
-- @param value the value
-- @array[opt] exclude any tables to avoid searching
-- @return a fieldspec, e.g. 'a.b' or 'math.sin'
-- @usage search(_G,math.sin,{package.path}) == 'math.sin'
function tablex.search(t, value, exclude)
  assert_arg_iterable(1, t)
  local tables = { [t] = true }
  if exclude then
    for _, v in pairs(exclude) do
      tables[v] = true
    end
  end
  return _find(t, value, tables)
end

--- return an iterator to a table sorted by its keys
-- @within Iterating
-- @tab t the table
-- @func f an optional comparison function (f(x,y) is true if x < y)
-- @usage for k,v in tablex.sort(t) do print(k,v) end
-- @return an iterator to traverse elements sorted by the keys
function tablex.sort(t, f)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  tsort(keys, f)
  local i = 0
  return function()
    i = i + 1
    return keys[i], t[keys[i]]
  end
end

--- return an iterator to a table sorted by its values
-- @within Iterating
-- @tab t the table
-- @func f an optional comparison function (f(x,y) is true if x < y)
-- @usage for k,v in tablex.sortv(t) do print(k,v) end
-- @return an iterator to traverse elements sorted by the values
function tablex.sortv(t, f)
  f = function_arg(2, f or '<')
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  tsort(keys, function(x, y)
    return f(t[x], t[y])
  end)
  local i = 0
  return function()
    i = i + 1
    return keys[i], t[keys[i]]
  end
end

--- modifies a table to be read only.
-- This only offers weak protection. Tables can still be modified with
-- `table.insert` and `rawset`.
--
-- *NOTE*: for Lua 5.1 length, pairs and ipairs will not work, since the
-- equivalent metamethods are only available in Lua 5.2 and newer.
-- @tab t the table
-- @return the table read only (a proxy).
function tablex.readonly(t)
  local mt = {
    __index = t,
    __newindex = function(t, k, v)
      error('Attempt to modify read-only table', 2)
    end,
    __pairs = function()
      return pairs(t)
    end,
    __ipairs = function()
      return ipairs(t)
    end,
    __len = function()
      return #t
    end,
    __metatable = false,
  }
  return setmetatable({}, mt)
end

return tablex
