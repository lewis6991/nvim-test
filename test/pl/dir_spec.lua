local helpers = require('nvim-test.helpers')
local eq = helpers.eq

local dir = require('pl.dir')
local path = require('pl.path')

local uv = vim.uv

local tmp_roots = {} --- @type string[]

local function new_tmpdir()
  local template = path.join(assert(uv.os_tmpdir()), 'nvim-test-dir-spec-XXXXXX')
  local root = assert(uv.fs_mkdtemp(template), 'failed to create temporary directory')
  table.insert(tmp_roots, root)
  return root
end

--- @param dirpath string
local function mkdir(dirpath)
  local mode = assert(tonumber('755', 8))
  assert(uv.fs_mkdir(dirpath, mode))
end

--- @param filepath string
--- @param contents? string
local function write_file(filepath, contents)
  local fd = assert(io.open(filepath, 'w'))
  fd:write(contents or '')
  fd:close()
end

after_each(function()
  for _, dirpath in ipairs(tmp_roots) do
    vim.fs.rm(dirpath, { recursive = true, force = true })
  end
  tmp_roots = {}
end)

local function build_sample_tree()
  local root = new_tmpdir()
  local src = path.join(root, 'src')
  local nested = path.join(src, 'nested')
  local docs = path.join(root, 'docs')

  mkdir(src)
  mkdir(nested)
  mkdir(docs)

  write_file(path.join(root, 'README.md'), '# docs')
  write_file(path.join(root, 'build.sh'), '#!/bin/sh')
  write_file(path.join(src, 'main.lua'), 'return true')
  write_file(path.join(nested, 'util.lua'), 'return {}')
  write_file(path.join(docs, 'guide.txt'), 'guide')

  return root
end

describe('pl.dir', function()
  it('matches patterns and filters file lists', function()
    eq(true, dir.fnmatch('notes.txt', '*.txt'))
    eq(false, dir.fnmatch('notes.txt', '*.lua'))

    local filtered = dir.filter({ 'init.lua', 'README.md', 'plugin.lua' }, '*.lua')
    eq({ 'init.lua', 'plugin.lua' }, filtered)
  end)

  it('collects files and directories with optional masks', function()
    local root = build_sample_tree()

    local lua_files = dir.getfiles(path.join(root, 'src'), '*.lua')
    eq({ path.join(root, 'src', 'main.lua') }, lua_files)

    local directories = dir.getdirectories(root)
    eq({ path.join(root, 'docs'), path.join(root, 'src') }, directories)
  end)

  it('walks directory trees depth-first by default', function()
    local root = build_sample_tree()
    local seen = {}
    local iter = dir.walk(root)

    -- Drain the iterator
    while true do
      local current, dirs, files = iter()
      if not current then
        break
      end
      seen[current] = { dirs = dirs, files = files }
    end

    eq({
      [root] = {
        dirs = { 'docs', 'src' },
        files = { 'README.md', 'build.sh' },
      },
      [path.join(root, 'docs')] = {
        dirs = {},
        files = { 'guide.txt' },
      },
      [path.join(root, 'src')] = {
        dirs = { 'nested' },
        files = { 'main.lua' },
      },
      [path.join(root, 'src', 'nested')] = {
        dirs = {},
        files = { 'util.lua' },
      },
    }, seen)
  end)

  it('removes directory trees recursively', function()
    local root = build_sample_tree()
    local ok, err = dir.rmtree(root)
    assert(ok, err)
    eq(nil, path.exists(root))
  end)

  it('creates nested directory structures with makepath', function()
    local deep = path.join(new_tmpdir(), 'a', 'b', 'c')
    --- @diagnostic disable-next-line: unnecessary-assert
    assert(dir.makepath(deep))
    assert(path.isdir(deep))
  end)
end)
