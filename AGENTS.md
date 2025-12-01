### Coding
- All code must be fully type annotated with LuaCATs annotations.
  - Do not add `@return nil`
- Prefer functional style over object oriented. Only use classes when there is a lot of state to manage.
- Exported tables from modules should always be named `M`.

### Checks
- Run `make emmylua-check` to check typing
- Run `make format` to fix code formatting
- Run `make test` to run testsuite

### Misc
- When running in the test runner. `vim.api` and `vim.fn` are not available.
- `exec_lua()` runs inside an embedded nvim instance which has access to `vim.api` and `vim.fn`

