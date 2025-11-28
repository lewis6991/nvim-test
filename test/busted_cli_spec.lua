local cli_factory = require('busted.modules.cli')

local fs = vim.fs

describe('busted.modules.cli', function()
  local cli

  local function parse_args(list)
    list = list or {}
    list[0] = list[0] or 'busted'
    local parsed, err = cli:parse(list)
    assert(parsed, err)
    return parsed
  end

  before_each(function()
    cli = cli_factory({ standalone = false })
    cli:set_name('busted')
  end)

  it('applies defaults and aliases when no args are provided', function()
    local parsed = parse_args({})
    assert.are.same('./', parsed.directory)
    assert.are.same({ 'spec' }, parsed.ROOT)
    assert.are.same({ '_spec' }, parsed.pattern)
    assert.are.equal(parsed.pattern, parsed.p)
    assert.is_false(parsed.coverage)
    assert.is_true(parsed['auto-insulate'])
    assert.is_true(parsed['keep-going'])
    assert.is_true(parsed.k)
  end)

  it('collects positional roots and multiple patterns', function()
    local parsed = parse_args({ 'foo', 'bar', '--pattern', 'alpha', '--pattern', 'beta' })
    assert.are.same({ 'foo', 'bar' }, parsed.ROOT)
    assert.are.same({ 'alpha', 'beta' }, parsed.pattern)
  end)

  it('joins directories incrementally', function()
    local parsed = parse_args({ '--directory', 'tmp', '--directory', 'nested' })
    assert.are.same(fs.normalize('tmp/nested'), parsed.directory)
  end)

  it('parses comma separated lists for tags and loaders', function()
    local parsed = parse_args({
      '--tags',
      'alpha,beta',
      '--tags',
      'gamma',
      '--loaders',
      'lua',
      '--loaders',
      'plenary',
    })
    assert.are.same({ 'alpha', 'beta', 'gamma' }, parsed.tags)
    assert.are.same(parsed.tags, parsed.t)
    assert.are.same({ 'lua', 'plenary' }, parsed.loaders)
  end)

  it('honors negatable flags', function()
    local parsed = parse_args({
      '--no-auto-insulate',
      '--lazy',
      '--no-keep-going',
      '--no-recursive',
      '--list',
    })
    assert.is_false(parsed['auto-insulate'])
    assert.is_true(parsed.lazy)
    assert.is_false(parsed['keep-going'])
    assert.is_false(parsed.k)
    assert.is_false(parsed.recursive)
    assert.is_false(parsed.R)
    assert.is_true(parsed.list)
    assert.is_true(parsed.l)
  end)

  it('errors when numeric options receive invalid values', function()
    local ok, err = cli:parse({ [0] = 'busted', '--repeat', 'not-a-number' })
    assert.is_nil(ok)
    assert.matches('--repeat', err)
  end)

  it('returns help text when requested', function()
    local ok, err = cli:parse({ [0] = 'busted', '--help' })
    assert.is_nil(ok)
    assert.matches('Usage:', err)
  end)

  it('supports short flag clusters and inline values', function()
    local parsed = parse_args({ '-clv', '--output=alt.output' })
    assert.is_true(parsed.c)
    assert.is_true(parsed.coverage)
    assert.is_true(parsed.l)
    assert.is_true(parsed.list)
    assert.is_true(parsed.v)
    assert.is_true(parsed.verbose)
    assert.are.equal('alt.output', parsed.output)
  end)

  it('rejects conflicting include and exclude tags', function()
    local ok, err = cli:parse({
      [0] = 'busted',
      '--tags',
      'focus',
      '--exclude-tags',
      'focus',
    })
    assert.is_nil(ok)
    assert.matches('Cannot use %-%-tags and %-%-exclude%-tags', err)
  end)

  it('rejects positional roots when running standalone', function()
    local standalone = cli_factory({ standalone = true })
    standalone:set_name('busted')
    local ok, err = standalone:parse({ [0] = 'busted', 'spec/foo_spec.lua' })
    assert.is_nil(ok)
    assert.matches('Unexpected positional argument', err)
  end)
end)
