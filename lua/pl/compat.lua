----------------
--- Lua 5.1/5.2/5.3 compatibility.
-- Injects `table.pack`, `table.unpack`, and `package.searchpath` in the global
-- environment, to make sure they are available for Lua 5.1 and LuaJIT.
--
-- All other functions are exported as usual in the returned module table.
--
-- NOTE: everything in this module is also available in `pl.utils`.
-- @module pl.compat
local compat = {}

--- the directory separator character for the current platform.
-- @field dir_separator
local dir_separator = _G.package.config:sub(1, 1)

--- boolean flag this is a Windows platform.
-- @field is_windows
compat.is_windows = dir_separator == '\\'

return compat
