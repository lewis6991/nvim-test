local helpers = require('nvim-test.helpers')
local eq = helpers.eq

describe('nvim-test.helpers', function()
  describe('dedent', function()
    it('strips the shared indentation from a block', function()
      local input = table.concat({
        '        first',
        '          second',
        '        third',
      }, '\n')

      local expected = table.concat({
        'first',
        '  second',
        'third',
      }, '\n')

      eq(expected, helpers.dedent(input))
    end)

    it('leaves a caller-provided indent in place', function()
      local input = table.concat({
        '      keep me',
        '      also keep me',
      }, '\n')

      local expected = table.concat({
        '  keep me',
        '  also keep me',
      }, '\n')

      eq(expected, helpers.dedent(input, 2))
    end)
  end)

  describe('pcall utilities', function()
    local function explode()
      error('/tmp/foo.lua:99: something bad happened')
    end

    it('scrubs stack traces when pcall returns an error', function()
      local ok, err = helpers.pcall(explode)
      assert.is_false(ok)
      assert(err, 'expected sanitized error message')
      ---@cast err string
      assert.matches('%.%.%./foo%.lua:0: something bad happened', err)
      assert.not_matches('99', err)
    end)

    it('pcall_err returns the sanitized error and enforces failures', function()
      local err = helpers.pcall_err(explode)
      ---@cast err string
      assert.matches('%.%.%./foo%.lua:0: something bad happened', err)

      assert.has_error(function()
        helpers.pcall_err(function()
          return 'ok'
        end)
      end, 'expected failure, but got success')
    end)
  end)

  describe('create_callindex', function()
    it('memoizes generated dispatchers and forwards the method name', function()
      local received = {}
      local callindex = helpers.create_callindex(function(method, ...)
        table.insert(received, { method = method, args = { ... } })
        local parts = { method, ... }
        for i, value in ipairs(parts) do
          parts[i] = tostring(value)
        end
        return table.concat(parts, '-')
      end)

      local foo = callindex.foo
      local bar = callindex.bar

      eq('foo-1-2', foo(1, 2))
      eq('bar-true', bar(true))

      -- Subsequent lookups should reuse the cached dispatcher.
      eq(foo, callindex.foo)

      eq({
        { method = 'foo', args = { 1, 2 } },
        { method = 'bar', args = { true } },
      }, received)
    end)
  end)
end)
