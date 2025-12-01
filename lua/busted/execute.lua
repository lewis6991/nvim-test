--- @class busted.ExecutionOptions
--- @field sort? boolean

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

local Block = require('busted.block')

--- @param busted busted.Busted
--- @return fun(runs: integer, options?: busted.ExecutionOptions)
return function(busted)
  local block = Block.new(busted)

  --- @param runs integer
  --- @param options? busted.ExecutionOptions
  local function execute(runs, options)
    options = options or {}
    local root = busted.context:get()
    local children = { unpack(busted.context:children(root)) }

    --- @return nil
    local function suite_reset()
      local oldctx = busted.context:get()

      busted.context:clear()
      local ctx = busted.context:get()
      for k, v in pairs(oldctx) do
        ctx[k] = v
      end

      for _, child in ipairs(children) do
        for descriptor, _ in pairs(busted.executors) do
          child[descriptor] = nil
        end
        busted.context:attach(child)
      end
    end

    for i = 1, runs do
      if i > 1 then
        suite_reset()
        root = busted.context:get()
        busted:safe_publish('suite', { 'suite', 'reset' }, root, i, runs)
      end

      if options.sort then
        sort(busted.context:children(root))
      end

      if busted:safe_publish('suite', { 'suite', 'start' }, root, i, runs) then
        if block:setup(root) then
          busted:execute()
        end
        block:lazyTeardown(root)
        block:teardown(root)
      end
      busted:safe_publish('suite', { 'suite', 'end' }, root, i, runs)

      if busted.skipAll then
        break
      end
    end
  end

  return execute
end
