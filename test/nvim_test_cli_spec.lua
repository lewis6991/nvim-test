local uv = assert(vim and vim.uv, 'nvim-test requires vim.uv')

local function mkdir_p(path)
  local absolute = path
  local current = absolute:sub(1, 1) == '/' and '/' or ''
  for part in absolute:gmatch('[^/]+') do
    if current == '' or current == '/' then
      current = (current == '/' and '/' .. part) or part
    else
      current = current .. '/' .. part
    end
    local ok, err = uv.fs_mkdir(current, 448)
    if not ok and err and not tostring(err):match('EEXIST') then
      error(('failed to create %s: %s'):format(current, err))
    end
  end
end

local function rm_rf(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end
  if stat.type == 'directory' then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        rm_rf(path .. '/' .. name)
      end
    end
    uv.fs_rmdir(path)
  else
    uv.fs_unlink(path)
  end
end

local function with_tmpdir(cb)
  local base = uv.os_tmpdir() or '/tmp'
  local dir = assert(uv.fs_mkdtemp(base .. '/nvim-test-cli-XXXXXX'))
  local ok, err = pcall(cb, dir)
  rm_rf(dir)
  assert(ok, err)
end

local function write_runner_shim(path)
  local progpath = assert(uv.exepath(), 'uv.exepath() unavailable')
  local file = assert(io.open(path, 'w'))
  file:write('#!/usr/bin/env sh\n')
  file:write(string.format('exec %q "$@"\n', progpath))
  file:close()
  if uv.fs_chmod then
    uv.fs_chmod(path, 493)
  end
end

local function shell_escape(str)
  str = tostring(str)
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

local function run_cli(args, env)
  local cwd = uv.cwd()
  local parts = { 'cd', shell_escape(cwd), '&&' }
  for name, value in pairs(env or {}) do
    parts[#parts + 1] = string.format('%s=%s', name, shell_escape(value))
  end
  parts[#parts + 1] = './bin/nvim-test'
  for _, arg in ipairs(args) do
    parts[#parts + 1] = shell_escape(arg)
  end

  local command = table.concat(parts, ' ')
  local pipe = assert(io.popen(command .. ' 2>&1', 'r'))
  local output = pipe:read('*a')
  local ok, _, code = pipe:close()
  local exit_code = ok and 0 or code
  return exit_code, output
end

describe('nvim-test CLI', function()
  it('prints help output for -h', function()
    with_tmpdir(function(tmpdir)
      local runner_version = 'spec-runner'
      local runner_bin = table.concat({ tmpdir, 'nvim-test', 'nvim-runner-' .. runner_version, 'bin' }, '/')
      mkdir_p(runner_bin)
      write_runner_shim(runner_bin .. '/nvim')

      local code, output = run_cli({ '-h' }, {
        NVIM_RUNNER_VERSION = runner_version,
        XDG_DATA_HOME = tmpdir,
      })

      assert.are.equal(0, code, output)
      assert.matches('Usage: nvim%-test', output)
    end)
  end)
end)
