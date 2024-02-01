local helpers = require('nvim-test.helpers')
local exec_lua = helpers.exec_lua
local eq = helpers.eq

describe('my tests', function()
  before_each(function()
    helpers.clear()

    -- Make plugin available
    exec_lua('package.path = ...', package.path)
  end)

  it('run a test', function()
    eq(true, exec_lua[[
        return require('myplugin').foo()
    ]])
  end)
end)
