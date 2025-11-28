local M = require('luassert.assert')

M._COPYRIGHT = 'Copyright (c) 2018 Olivine Labs, LLC.'
M._DESCRIPTION =
  "Extends Lua's built-in assertions to provide additional tests and the ability to create your own."
M._VERSION = 'Luassert 1.8.0'

-- load basic asserts
require('luassert.assertions')
require('luassert.modifiers')
require('luassert.array')
require('luassert.matchers')
require('luassert.formatters')

return M
