local function getUniqueId(obj)
  return tonumber(tostring(obj):match(':%s*[0xX]*(%x+)'), 16)
end

--- @class mediator.Options
--- @field priority? integer
--- @field predicate? fun(...): boolean

--- @class mediator.Subscriber
--- @field options mediator.Options
--- @field fn fun(...): any, boolean?
--- @field id integer
--- @operator call: mediator.Subscriber
local Subscriber = {}
Subscriber.__index = Subscriber

function Subscriber:new(fn, options)
  local sub = setmetatable({
    options = options or {},
    fn = fn,
  }, Subscriber)
  sub.id = getUniqueId(sub)
  return sub
end

setmetatable(Subscriber, { __call = Subscriber.new })

function Subscriber:update(options)
  if options then
    self.fn = options.fn or self.fn
    self.options = options.options or self.options
  end
end

--- @class mediator.Channel
--- @field callbacks mediator.Subscriber[]
--- @field channels mediator.Channel[]
--- @field parent? mediator.Channel
--- @operator call: mediator.Channel
local Channel = {}
Channel.__index = Channel

function Channel:new(namespace, parent)
  return setmetatable({
    stopped = false,
    namespace = namespace,
    callbacks = {},
    channels = {},
    parent = parent,
  }, Channel)
end

setmetatable(Channel, { __call = Channel.new })

--- @param fn function
--- @param options? mediator.Options
--- @return mediator.Subscriber
function Channel:addSubscriber(fn, options)
  local callback = Subscriber(fn, options)
  local priority = (#self.callbacks + 1)

  options = options or {}

  local opt_priority = options.priority
  if opt_priority and opt_priority >= 0 and opt_priority < priority then
    priority = opt_priority
  end

  table.insert(self.callbacks, priority, callback)

  return callback
end

function Channel:getSubscriber(id)
  for i = 1, #self.callbacks do
    local callback = self.callbacks[i]
    if callback.id == id then
      return { index = i, value = callback }
    end
  end
  local sub --- @type mediator.Channel?
  for _, channel in pairs(self.channels) do
    sub = channel:getSubscriber(id)
    if sub then
      break
    end
  end
  return sub
end

function Channel:setPriority(id, priority)
  local callback = self:getSubscriber(id)

  if callback.value then
    table.remove(self.callbacks, callback.index)
    table.insert(self.callbacks, priority, callback.value)
  end
end

--- @param namespace string
--- @return mediator.Channel
function Channel:addChannel(namespace)
  self.channels[namespace] = Channel(namespace, self)
  return self.channels[namespace]
end

--- @param namespace string
--- @return boolean
function Channel:hasChannel(namespace)
  return namespace and self.channels[namespace] and true
end

--- @param namespace string
--- @return mediator.Channel
function Channel:getChannel(namespace)
  return self.channels[namespace] or self:addChannel(namespace)
end

--- @param id string
--- @return mediator.Subscriber?
function Channel:removeSubscriber(id)
  local callback = self:getSubscriber(id)

  if callback and callback.value then
    for _, channel in pairs(self.channels) do
      channel:removeSubscriber(id)
    end

    return table.remove(self.callbacks, callback.index)
  end
end

function Channel:publish(result, ...)
  for i = 1, #self.callbacks do
    local callback = self.callbacks[i]
    local predicate = callback.options.predicate

    -- if it doesn't have a predicate, or it does and it's true then run it
    if not predicate or predicate(...) then
      -- just take the first result and insert it into the result table
      local value, continue = callback.fn(...)

      if value then
        table.insert(result, value)
      end
      if not continue then
        return result
      end
    end
  end

  if self.parent then
    return self.parent:publish(result, ...)
  end

  return result
end

--- @class Mediator
--- @field channel mediator.Channel
local Mediator = {}
Mediator.__index = Mediator

Mediator.Channel = Channel
Mediator.Subscriber = Subscriber

function Mediator.new()
  return setmetatable({ channel = Channel('root') }, Mediator)
end

setmetatable(Mediator, { __call = Mediator.new })

--- @param channelNamespace string[]
--- @return mediator.Channel
function Mediator:getChannel(channelNamespace)
  local channel = self.channel

  for i = 1, #channelNamespace do
    channel = channel:getChannel(channelNamespace[i])
  end

  return channel
end

--- @param channelNamespace string[]
--- @param fn function
--- @param options? mediator.Options
--- @return mediator.Subscriber
function Mediator:subscribe(channelNamespace, fn, options)
  return self:getChannel(channelNamespace):addSubscriber(fn, options)
end

--- @param id string
--- @param channelNamespace string[]
--- @return mediator.Subscriber
function Mediator:getSubscriber(id, channelNamespace)
  return self:getChannel(channelNamespace):getSubscriber(id)
end

--- @param id string
--- @param channelNamespace string[]
--- @return mediator.Subscriber?
function Mediator:removeSubscriber(id, channelNamespace)
  return self:getChannel(channelNamespace):removeSubscriber(id)
end

--- @param channelNamespace string[]
--- @param ... any
--- @return any[]
function Mediator:publish(channelNamespace, ...)
  return self:getChannel(channelNamespace):publish({}, ...)
end

return Mediator
