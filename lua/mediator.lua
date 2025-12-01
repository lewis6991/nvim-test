--- @class mediator.SubscriberOptions
--- @field priority? integer
--- @field predicate? fun(...: any): boolean

--- @class mediator.SubscriberUpdate
--- @field fn? fun(...: any): any
--- @field options? mediator.SubscriberOptions

--- @class mediator.SubscriberLookup
--- @field index integer
--- @field value mediator.Subscriber

--- @alias mediator.ChannelPath string[]
--- @alias mediator.PublishResult any[]
--- @alias mediator.CallbackFn fun(...: any): any, boolean?

--- @param obj table
--- @return integer
local function getUniqueId(obj)
  local hex = tostring(obj):match(':%s*[0xX]*(%x+)')
  assert(hex, 'failed to extract unique identifier')
  local value = tonumber(hex, 16)
  assert(value, 'failed to convert identifier to number')
  --- @cast value integer
  return value
end

--- @class mediator.Subscriber
--- @field id integer
--- @field fn fun(...: any): any
--- @field options mediator.SubscriberOptions
--- @field channel? mediator.Channel
--- @field update fun(self: mediator.Subscriber, opts?: mediator.SubscriberUpdate)
local Subscriber = {}
Subscriber.__index = Subscriber

--- @param fn fun(...: any): any
--- @param options? mediator.SubscriberOptions
--- @return mediator.Subscriber
function Subscriber.new(fn, options)
  --- @type mediator.Subscriber
  local subscriber = setmetatable({
    options = options or {},
    fn = fn,
    channel = nil,
  }, Subscriber)

  subscriber.id = getUniqueId(subscriber)
  return subscriber
end

--- @param opts? mediator.SubscriberUpdate
function Subscriber:update(opts)
  if not opts then
    return
  end

  if opts.fn then
    self.fn = opts.fn
  end
  if opts.options then
    self.options = opts.options
  end
end

--- @class mediator.Channel
--- @field stopped boolean
--- @field namespace string
--- @field callbacks mediator.Subscriber[]
--- @field channels table<string, mediator.Channel>
--- @field parent? mediator.Channel
local Channel = {}
Channel.__index = Channel

--- @param namespace string
--- @param parent? mediator.Channel
--- @return mediator.Channel
function Channel.new(namespace, parent)
  --- @type mediator.Channel
  local channel = setmetatable({
    stopped = false,
    namespace = namespace,
    callbacks = {},
    channels = {},
    parent = parent,
  }, Channel)
  return channel
end

--- @param fn mediator.CallbackFn
--- @param options? mediator.SubscriberOptions
--- @return mediator.Subscriber
function Channel:addSubscriber(fn, options)
  local callback = Subscriber.new(fn, options)
  local insert_index = #self.callbacks + 1
  local opts = options or {}

  if opts.priority and opts.priority >= 0 and opts.priority < insert_index then
    insert_index = opts.priority
  end

  insert_index = math.floor(insert_index)
  if insert_index < 1 then
    insert_index = 1
  end

  table.insert(self.callbacks, insert_index, callback)

  return callback
end

--- @param id integer
--- @return mediator.SubscriberLookup?
function Channel:getSubscriber(id)
  for index = 1, #self.callbacks do
    local callback = self.callbacks[index]
    if callback and callback.id == id then
      return { index = index, value = callback }
    end
  end

  for _, child in pairs(self.channels) do
    local found = child:getSubscriber(id)
    if found then
      return found
    end
  end
end

--- @param id integer
--- @param priority integer
function Channel:setPriority(id, priority)
  local callback = self:getSubscriber(id)
  if not callback or not callback.value then
    return
  end

  table.remove(self.callbacks, callback.index)
  table.insert(self.callbacks, priority, callback.value)
end

--- @param channel_namespace string
--- @return mediator.Channel
function Channel:addChannel(channel_namespace)
  --- @diagnostic disable-next-line:param-type-mismatch
  local child = Channel.new(channel_namespace, self)
  self.channels[channel_namespace] = child
  return child
end

--- @param channel_namespace string?
--- @return boolean
function Channel:hasChannel(channel_namespace)
  if not channel_namespace then
    return false
  end
  return self.channels[channel_namespace] ~= nil
end

--- @param channel_namespace string
--- @return mediator.Channel
function Channel:getChannel(channel_namespace)
  if not self:hasChannel(channel_namespace) then
    return self:addChannel(channel_namespace)
  end
  return self.channels[channel_namespace]
end

--- @param id integer
--- @return mediator.Subscriber?
function Channel:removeSubscriber(id)
  local callback = self:getSubscriber(id)

  if callback and callback.value then
    for _, child in pairs(self.channels) do
      child:removeSubscriber(id)
    end

    return table.remove(self.callbacks, callback.index)
  end
end

--- @param result mediator.PublishResult
--- @return mediator.PublishResult
function Channel:publish(result, ...)
  for index = 1, #self.callbacks do
    local callback = self.callbacks[index]
    if callback then
      local predicate = callback.options.predicate

      if not predicate or predicate(...) then
        local value, continue = callback.fn(...)

        if value then
          table.insert(result, value)
        end
        if not continue then
          return result
        end
      end
    end
  end

  if self.parent then
    return self.parent:publish(result, ...)
  end

  return result
end

--- @class mediator.Instance
--- @field channel mediator.Channel
local M = {}
M.__index = M

--- @return mediator.Instance
function M.new()
  return setmetatable({
    channel = Channel.new('root'),
  }, M)
end

--- @param channelNamespace mediator.ChannelPath
--- @return mediator.Channel
function M:getChannel(channelNamespace)
  --- @type mediator.Channel
  local channel = self.channel

  for index = 1, #channelNamespace do
    channel = channel:getChannel(channelNamespace[index])
  end

  return channel
end

--- @param channelNamespace mediator.ChannelPath
--- @param fn mediator.CallbackFn
--- @param options? mediator.SubscriberOptions
--- @return mediator.Subscriber
function M:subscribe(channelNamespace, fn, options)
  return self:getChannel(channelNamespace):addSubscriber(fn, options)
end

--- @param id integer
--- @param channelNamespace mediator.ChannelPath
--- @return mediator.SubscriberLookup?
function M:getSubscriber(id, channelNamespace)
  return self:getChannel(channelNamespace):getSubscriber(id)
end

--- @param id integer
--- @param channelNamespace mediator.ChannelPath
--- @return mediator.Subscriber?
function M:removeSubscriber(id, channelNamespace)
  return self:getChannel(channelNamespace):removeSubscriber(id)
end

--- @param channelNamespace mediator.ChannelPath
--- @return mediator.PublishResult
function M:publish(channelNamespace, ...)
  return self:getChannel(channelNamespace):publish({}, ...)
end

return M
