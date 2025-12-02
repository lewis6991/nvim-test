local cli_factory = require('busted.cli')

---@class BustedCliApi
---@field set_name fun(self: BustedCliApi, name: string)
---@field parse fun(self: BustedCliApi, args: string[]): (busted.cli.Arguments?, string?)

local fs = vim.fs

describe('busted.cli', function()
  ---@type BustedCliApi?
  local cli

  local function parse_args(list)
    assert(cli, 'cli not initialized')
    local args = {}
    for index, value in ipairs(list or {}) do
      args[index] = value
    end
    local parsed, err = cli:parse(args)
    assert(parsed, err)
    return parsed
  end

  local function run_cli(args)
    assert(cli, 'cli not initialized')
    return cli:parse(args)
  end

  local function run_cli_and_expect_error(args)
    local ok, err = run_cli(args)
    assert(not ok)
    assert(err, 'expected CLI error')
    ---@cast err string
    return err
  end

  before_each(function()
    cli = cli_factory({})
    ---@cast cli BustedCliApi
    cli:set_name('busted')
  end)

  it('applies defaults and aliases when no args are provided', function()
    local parsed = parse_args({})
    assert.are.same('./', parsed.directory)
    assert.are.same({ 'spec' }, parsed.ROOT)
    assert.are.same({ '_spec' }, parsed.pattern)
    assert(not parsed.coverage)
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

  it('parses comma separated lists for tags', function()
    local parsed = parse_args({
      '--tags',
      'alpha,beta',
      '--tags',
      'gamma',
    })
    assert.are.same({ 'alpha', 'beta', 'gamma' }, parsed.tags)
  end)

  it('derives default handlers for multi options', function()
    local parsed = parse_args({
      '--filter',
      'alpha',
      '--filter',
      'beta',
      '--filter-out',
      'skip',
    })
    assert.are.same({ 'alpha', 'beta' }, parsed.filter)
    assert.are.same({ 'skip' }, parsed['filter-out'])
  end)

  it('errors when numeric options receive invalid values', function()
    local err = run_cli_and_expect_error({ '--repeat', 'not-a-number' })
    assert.matches('--repeat', err)
  end)

  it('returns help text when requested', function()
    local err = run_cli_and_expect_error({ '--help' })
    assert.matches('Usage: busted', err)
    assert.matches('ARGUMENTS:%s+ROOT', err)
    assert.matches('OPTIONS:%s+%-%-version', err)
    assert.matches('%-C,%s+%-%-directory', err)
    assert.matches('%-%-coverage%-config%-file', err)
    assert.matches('re%-run with %-%-help for usage%.$', err)
  end)

  it('prints a usable help summary for -h', function()
    local err = run_cli_and_expect_error({ '-h' })
    assert.matches('Usage: busted', err)
    assert.matches('%-%-pattern', err)
    assert.matches('%-%-helper', err)
    assert.matches('%-%-coverage', err)
    assert.matches('%-%-quit%-on%-error', err)
  end)

  it('supports short flag clusters and inline values', function()
    local parsed = parse_args({ '-lv', '--coverage', '--output=alt.output' })
    assert(parsed.coverage)
    assert(parsed.l)
    assert(parsed.list)
    assert(parsed.v)
    assert(parsed.verbose)
    assert.are.equal('alt.output', parsed.output)
  end)

  it('rejects conflicting include and exclude tags', function()
    local err = run_cli_and_expect_error({
      '--tags',
      'focus',
      '--exclude-tags',
      'focus',
    })
    assert.matches('Cannot use %-%-tags and %-%-exclude%-tags', err)
  end)
end)
