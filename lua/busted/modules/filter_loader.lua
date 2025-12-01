--- @class busted.FilterLoaderOptions
--- @field tags string[]?
--- @field excludeTags string[]?
--- @field filter string[]?
--- @field filterOut string[]?
--- @field excludeNamesFile string?
--- @field list boolean?
--- @field nokeepgoing boolean?
--- @field suppressPending boolean?

--- @class busted.FilterLoader
--- @field private _busted busted.Busted
--- @field private _options busted.FilterLoaderOptions
--- @field private _exclude_names string[]
local M = {}
M.__index = M

local noop = function() end

--- @param name string
--- @param tag string
--- @return boolean
local function name_has_tag(name, tag)
  return name:find('#' .. tag) ~= nil
end

--- @return nil, boolean
local function ignore_all()
  return nil, false
end

--- @param busted busted.Busted
--- @param options busted.FilterLoaderOptions
--- @return busted.FilterLoader
function M.new(busted, options)
  local self = setmetatable({
    _busted = busted,
    _options = options,
    _exclude_names = {},
  }, M)
  self:_load_exclude_names()
  return self
end

--- @private
--- @param name? string
--- @return string
function M:_get_full_name(name)
  local parent = self._busted.context:get()
  local names = { name }

  while parent and (parent.name or parent.descriptor) and parent.descriptor ~= 'file' do
    table.insert(names, 1, parent.name or parent.descriptor)
    parent = self._busted.context:parent(parent)
  end

  return table.concat(names, ' ')
end

--- @param name string
--- @return nil, boolean
function M:filter_exclude_tags(name)
  local exclude_tags = self._options.excludeTags or {}
  for _, tag in pairs(exclude_tags) do
    if name_has_tag(name, tag) then
      return nil, false
    end
  end
  return nil, true
end

--- @param name string
--- @return nil, boolean
function M:filter_tags(name)
  local tags = self._options.tags or {}
  local fullname = self:_get_full_name(name)
  for _, tag in pairs(tags) do
    if name_has_tag(fullname, tag) then
      return nil, true
    end
  end
  return nil, (#tags == 0)
end

--- @param name string
--- @return nil, boolean
function M:filter_out_names(name)
  local patterns = self._options.filterOut or {}
  local fullname = self:_get_full_name(name)
  for _, pattern in pairs(patterns) do
    if fullname:find(pattern) ~= nil then
      return nil, false
    end
  end
  return nil, true
end

--- @param name string
--- @return nil, boolean
function M:exclude_names_file(name)
  local fullname = self:_get_full_name(name)
  for _, candidate in ipairs(self._exclude_names) do
    if fullname == candidate then
      return nil, false
    end
  end
  return nil, true
end

--- @param name string
--- @return nil, boolean
function M:filter_names(name)
  local patterns = self._options.filter or {}
  local fullname = self:_get_full_name(name)
  if #patterns == 0 then
    return nil, true
  end
  for _, pattern in pairs(patterns) do
    if fullname:find(pattern) ~= nil then
      return nil, true
    end
  end
  return nil, false
end

--- @param element table
--- @param _parent any
--- @param status string
--- @return nil, boolean
function M:print_test_name(element, _parent, status)
  if not (self._options.suppressPending and status == 'pending') then
    local fullname = self:_get_full_name()
    local trace = element.trace
    if trace and trace.what == 'Lua' then
      fullname = trace.short_src .. ':' .. trace.currentline .. ': ' .. fullname
    end
    print(fullname)
  end
  return nil, false
end

--- @param descriptor string
--- @param descriptor_name string
--- @param fn fun(...: any)
--- @param ... any
--- @return nil, boolean
function M:stub_out(descriptor, descriptor_name, fn, ...)
  if fn == noop then
    return nil, true
  end
  self._busted:publish({ 'register', descriptor }, descriptor_name, noop, ...)
  return nil, false
end

--- @return nil, boolean
function M:skip_on_error()
  return nil, not self._busted.skipAll
end

--- @param option_name string
--- @return boolean
function M:has_option(option_name)
  local value = self._options[option_name]
  return not not value and value ~= ''
end

--- @param descriptors string[]
--- @param option_name string
--- @param handler fun(self: busted.FilterLoader, ...: any): (nil, boolean)
function M:apply_filter(descriptors, option_name, handler)
  if self:has_option(option_name) then
    for _, descriptor in ipairs(descriptors) do
      self._busted:subscribe({ 'register', descriptor }, function(...)
        return handler(self, ...)
      end, { priority = 1 })
    end
  end
end

--- @private
--- @param descriptors string[]
--- @param option_name string
--- @param handler fun(self: busted.FilterLoader, descriptor: string, ...: any): (nil, boolean)
function M:_apply_descriptor_filter(descriptors, option_name, handler)
  if self:has_option(option_name) then
    for _, descriptor in ipairs(descriptors) do
      self._busted:subscribe({ 'register', descriptor }, function(...)
        return handler(self, descriptor, ...)
      end, { priority = 1 })
    end
  end
end

--- @private
function M:_apply_error_filters()
  self:apply_filter({ 'lazy_setup', 'lazy_teardown' }, 'nokeepgoing', M.skip_on_error)
  self:apply_filter({ 'strict_setup', 'strict_teardown' }, 'nokeepgoing', M.skip_on_error)
  self:apply_filter(
    { 'setup', 'teardown', 'before_each', 'after_each' },
    'nokeepgoing',
    M.skip_on_error
  )
  self:apply_filter({ 'file', 'describe', 'it', 'pending' }, 'nokeepgoing', M.skip_on_error)
end

--- @private
function M:_apply_name_filters()
  -- The following filters are applied in reverse order
  self:apply_filter({ 'it', 'pending' }, 'filter', M.filter_names)
  self:apply_filter({ 'describe', 'it', 'pending' }, 'filterOut', M.filter_out_names)
  self:apply_filter({ 'describe', 'it', 'pending' }, 'excludeNamesFile', M.exclude_names_file)
  self:apply_filter({ 'it', 'pending' }, 'tags', M.filter_tags)
  self:apply_filter({ 'describe', 'it', 'pending' }, 'excludeTags', M.filter_exclude_tags)
end

--- @private
function M:_enable_list_mode()
  self._busted:subscribe({ 'suite', 'start' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'suite', 'end' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'file', 'start' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'file', 'end' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'describe', 'start' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'describe', 'end' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'test', 'start' }, ignore_all, { priority = 1 })
  self._busted:subscribe({ 'test', 'end' }, function(...)
    return self:print_test_name(...)
  end, { priority = 1 })
  self:_apply_descriptor_filter(
    { 'setup', 'teardown', 'before_each', 'after_each' },
    'list',
    M.stub_out
  )
  self:_apply_descriptor_filter({ 'lazy_setup', 'lazy_teardown' }, 'list', M.stub_out)
  self:_apply_descriptor_filter({ 'strict_setup', 'strict_teardown' }, 'list', M.stub_out)
  self:_apply_descriptor_filter({ 'it', 'pending' }, 'list', M.stub_out)
end

--- @private
function M:_load_exclude_names()
  self._exclude_names = {}
  local exclude_file = self._options.excludeNamesFile
  if not exclude_file or exclude_file == '' then
    return
  end
  for line_name in io.lines(exclude_file) do
    table.insert(self._exclude_names, line_name)
  end
  return
end

function M:run()
  if self._options.list then
    self:_enable_list_mode()
  end
  self:_apply_error_filters()
  self:_apply_name_filters()
  return
end

--- @param busted busted.Busted
--- @param options busted.FilterLoaderOptions
function M.apply(busted, options)
  M.new(busted, options):run()
end

return M
