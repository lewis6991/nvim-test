# nvim-test

Testing framework for Neovim plugins.

Adapted directly from https://github.com/neovim/neovim/tree/master/test

## Requirements

- [Luarocks]
- [Lua5.1]
- MacOS or Linux

## Usage

```
Usage: nvim-test [OPTIONS] [--] [BUSTED_ARGS]
ARGUMENTS:
  BUSTED_ARGS                     Arguments passed directly to busted.

OPTIONS:
  --runner_version [NVIM_VERSION] Which version of Nvim to run as the test runner
                                  (Default 0.9.5)
  --target_version [NVIM_VERSION] Which version of Nvim to run tests under
                                  (Default 0.9.5)
  --clean                         Redownload test collateral.
  --init                          Initialize nvim-test. Do not run tests.
```

<!-- links -->
[Busted]: https://lunarmodules.github.io/busted

## Example

Create a `Makefile` with the contents:

```make
nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: nvim-test
	nvim-test/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua
```


Add a test file `test/mytest_spec.lua` with the format:

```lua
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
```

Then to run tests:

```bash
make test
```

```
nvim-test/bin/nvim-test test \
        --lpath=.../nvim-test/example/lua/?.lua
-------- Global test environment setup.
-------- Running tests from test/mytest_spec.lua
RUN       my tests run a test: 1.14 ms OK
-------- 1 test from test/mytest_spec.lua (11.97 ms total)

-------- Global test environment teardown.
======== 1 test from 1 test file ran. (12.13 ms total)
PASSED   1 test.
```

See [example](./example) for more details.

[Luarocks]: https://luarocks.org/
[Lua5.1]: https://www.lua.org/versions.html#5.1
