# nvim-test

Testing framework for Neovim plugins.

Adapted directly from https://github.com/neovim/neovim/tree/master/test

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
