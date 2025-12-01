local output_loader_factory = require('busted.modules.output_handler_loader')
local helper_loader_factory = require('busted.modules.helper_loader')

local function reset_module(name)
  package.loaded[name] = nil
  package.preload[name] = nil
end

describe('busted output handler loader', function()
  it('falls back to the default output handler when the requested handler is missing', function()
    local loader = output_loader_factory()
    local published = {}
    local busted = {
      publish = function(_, subjects, element, _, message)
        published[#published + 1] = { subjects = subjects, element = element, message = message }
      end,
    }

    local fallback_called = false
    local fallback_name = 'busted.outputHandlers._fallback_test'
    package.preload[fallback_name] = function()
      return function()
        return {
          subscribe = function()
            fallback_called = true
          end,
        }
      end
    end

    loader(busted, 'missing.output.handler', {
      arguments = {},
      defaultOutput = fallback_name,
    })

    assert.are.same('missing.output.handler', published[1].element.name)
    assert(fallback_called)
    reset_module(fallback_name)
  end)

  it('loads output handlers from explicit Lua paths', function()
    local loader = output_loader_factory()
    local tmp = vim.fs.joinpath(vim.uv.os_tmpdir(), 'output-handler-' .. vim.uv.now() .. '.lua')
    local fd = assert(vim.uv.fs_open(tmp, 'w', 420))
    assert(vim.uv.fs_write(fd, 'return function() return { subscribe = function() end } end'))
    vim.uv.fs_close(fd)

    loader({ publish = function() end }, tmp, { arguments = {}, defaultOutput = 'does.not.matter' })

    vim.uv.fs_unlink(tmp)
  end)
end)

describe('busted helper loader', function()
  it('invokes helper modules that return functions', function()
    local loader = helper_loader_factory()
    local helper_name = 'test.helper.module'
    local called_with
    package.preload[helper_name] = function()
      return function(_, helper, options)
        called_with = { helper = helper, options = options }
        return true
      end
    end

    local options = { arguments = {} }
    local ok, err = loader({}, helper_name, options)
    assert(ok)
    assert(err == nil)
    assert.are.same(helper_name, called_with.helper)
    reset_module(helper_name)
  end)

  it('propagates errors from helpers', function()
    local loader = helper_loader_factory()
    local helper_name = 'test.helper.error'
    package.preload[helper_name] = function()
      return function()
        error('boom')
      end
    end

    local ok, err = loader({}, helper_name, { arguments = {} })
    assert.is_nil(ok)
    assert.matches('boom', err)
    reset_module(helper_name)
  end)
end)
