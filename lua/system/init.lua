--- Lua System Library.
-- @module system

--- Terminal
-- @section terminal

local system = require 'system.core'


--- UTF8 codepage.
-- To be used with `system.setconsoleoutputcp` and `system.setconsolecp`.
-- @field CODEPAGE_UTF8 The Windows CodePage for UTF8.
system.CODEPAGE_UTF8 = 65001

do
  local backup_mt = {}

  --- Returns a backup of terminal settings for stdin/out/err.
  -- Handles terminal/console flags, Windows codepage, and non-block flags on the streams.
  -- Backs up terminal/console flags only if a stream is a tty.
  -- @return table with backup of terminal settings
  function system.termbackup()
    local backup = setmetatable({}, backup_mt)

    if system.isatty(io.stdin) then
      backup.console_in = system.getconsoleflags(io.stdin)
      backup.term_in = system.tcgetattr(io.stdin)
    end
    if system.isatty(io.stdout) then
      backup.console_out = system.getconsoleflags(io.stdout)
      backup.term_out = system.tcgetattr(io.stdout)
    end
    if system.isatty(io.stderr) then
      backup.console_err = system.getconsoleflags(io.stderr)
      backup.term_err = system.tcgetattr(io.stderr)
    end

    backup.block_in = system.getnonblock(io.stdin)
    backup.block_out = system.getnonblock(io.stdout)
    backup.block_err = system.getnonblock(io.stderr)

    backup.consoleoutcodepage = system.getconsoleoutputcp()
    backup.consolecp = system.getconsolecp()

    return backup
  end



  --- Restores terminal settings from a backup
  -- @tparam table backup the backup of terminal settings, see `termbackup`.
  -- @treturn boolean true
  function system.termrestore(backup)
    if getmetatable(backup) ~= backup_mt then
      error("arg #1 to termrestore, expected backup table, got " .. type(backup), 2)
    end

    if backup.console_in  then system.setconsoleflags(io.stdin, backup.console_in) end
    if backup.term_in     then system.tcsetattr(io.stdin, system.TCSANOW, backup.term_in) end
    if backup.console_out then system.setconsoleflags(io.stdout, backup.console_out) end
    if backup.term_out    then system.tcsetattr(io.stdout, system.TCSANOW, backup.term_out) end
    if backup.console_err then system.setconsoleflags(io.stderr, backup.console_err) end
    if backup.term_err    then system.tcsetattr(io.stderr, system.TCSANOW, backup.term_err) end

    if backup.block_in  ~= nil then system.setnonblock(io.stdin,  backup.block_in) end
    if backup.block_out ~= nil then system.setnonblock(io.stdout, backup.block_out) end
    if backup.block_err ~= nil then system.setnonblock(io.stderr, backup.block_err) end

    if backup.consoleoutcodepage then system.setconsoleoutputcp(backup.consoleoutcodepage) end
    if backup.consolecp          then system.setconsolecp(backup.consolecp) end
    return true
  end
end


do -- autotermrestore
  local global_backup -- global backup for terminal settings


  local add_gc_method do
    -- __gc meta-method is not available in all Lua versions
    local has_gc = not newproxy or false -- `__gc` was added when `newproxy` was removed

    if has_gc then
      -- use default GC mechanism since it is available
      function add_gc_method(t, f)
        setmetatable(t, { __gc = f })
      end
    else
      -- create workaround using a proxy userdata, typical for Lua 5.1
      function add_gc_method(t, f)
        local proxy = newproxy(true)
        getmetatable(proxy).__gc = function()
          t["__gc_proxy"] = nil
          f(t)
        end
        t["__gc_proxy"] = proxy
      end
    end
  end


  --- Backs up terminal settings and restores them on application exit.
  -- Calls `termbackup` to back up terminal settings and sets up a GC method to
  -- automatically restore them on application exit (also works on Lua 5.1).
  -- @treturn[1] boolean true
  -- @treturn[2] nil if the backup was already created
  -- @treturn[2] string error message
  function system.autotermrestore()
    if global_backup then
      return nil, "global terminal backup was already set up"
    end
    global_backup = system.termbackup()
    add_gc_method(global_backup, function(self) pcall(system.termrestore, self) end)
    return true
  end

  -- export a reset function only upon testing
  if _G._TEST then
    function system._reset_global_backup()
      global_backup = nil
    end
  end
end



do
  local oldunpack = unpack or table.unpack
  local pack = function(...) return { n = select("#", ...), ... } end
  local unpack = function(t) return oldunpack(t, 1, t.n) end

  --- Wraps a function to automatically restore terminal settings upon returning.
  -- Calls `termbackup` before calling the function and `termrestore` after.
  -- @tparam function f function to wrap
  -- @treturn function wrapped function
  function system.termwrap(f)
    if type(f) ~= "function" then
      error("arg #1 to wrap, expected function, got " .. type(f), 2)
    end

    return function(...)
      local bu = system.termbackup()
      local results = pack(f(...))
      system.termrestore(bu)
      return unpack(results)
    end
  end
end



--- Debug function for console flags (Windows).
-- Pretty prints the current flags set for the handle.
-- @param fh file handle (`io.stdin`, `io.stdout`, `io.stderr`)
-- @usage -- Print the flags for stdin/out/err
-- system.listconsoleflags(io.stdin)
-- system.listconsoleflags(io.stdout)
-- system.listconsoleflags(io.stderr)
function system.listconsoleflags(fh)
  local flagtype
  if fh == io.stdin then
    print "------ STDIN FLAGS WINDOWS ------"
    flagtype = "CIF_"
  elseif fh == io.stdout then
    print "------ STDOUT FLAGS WINDOWS ------"
    flagtype = "COF_"
  elseif fh == io.stderr then
    print "------ STDERR FLAGS WINDOWS ------"
    flagtype = "COF_"
  end

  local flags = assert(system.getconsoleflags(fh))
  local out = {}
  for k,v in pairs(system) do
    if type(k) == "string" and k:sub(1,4) == flagtype then
      if flags:has_all_of(v) then
        out[#out+1] = string.format("%10d [x] %s",v:value(),k)
      else
        out[#out+1] = string.format("%10d [ ] %s",v:value(),k)
      end
    end
  end
  table.sort(out)
  for k,v in pairs(out) do
    print(v)
  end
end



--- Debug function for terminal flags (Posix).
-- Pretty prints the current flags set for the handle.
-- @param fh file handle (`io.stdin`, `io.stdout`, `io.stderr`)
-- @usage -- Print the flags for stdin/out/err
-- system.listconsoleflags(io.stdin)
-- system.listconsoleflags(io.stdout)
-- system.listconsoleflags(io.stderr)
function system.listtermflags(fh)
  if fh == io.stdin then
    print "------ STDIN FLAGS POSIX ------"
  elseif fh == io.stdout then
    print "------ STDOUT FLAGS POSIX ------"
  elseif fh == io.stderr then
    print "------ STDERR FLAGS POSIX ------"
  end

  local flags = assert(system.tcgetattr(fh))
  for _, flagtype in ipairs { "iflag", "oflag", "lflag" } do
    local prefix = flagtype:sub(1,1):upper() .. "_"  -- I_, O_, or L_, the constant prefixes
    local out = {}
    for k,v in pairs(system) do
      if type(k) == "string" and k:sub(1,2) == prefix then
        if flags[flagtype]:has_all_of(v) then
          out[#out+1] = string.format("%10d [x] %s",v:value(),k)
        else
          out[#out+1] = string.format("%10d [ ] %s",v:value(),k)
        end
      end
    end
    table.sort(out)
    for k,v in pairs(out) do
      print(v)
    end
  end
end



do
  --- Reads a single byte from the console, with a timeout.
  -- This function uses `system.sleep` to wait until either a byte is available or the timeout is reached.
  -- The sleep period is exponentially backing off, starting at 0.0125 seconds, with a maximum of 0.2 seconds.
  -- It returns immediately if a byte is available or if `timeout` is less than or equal to `0`.
  --
  -- Using `system.readansi` is preferred over this function. Since this function can leave stray/invalid
  -- byte-sequences in the input buffer, while `system.readansi` reads full ANSI and UTF8 sequences.
  -- @tparam number timeout the timeout in seconds.
  -- @treturn[1] byte the byte value that was read.
  -- @treturn[2] nil if no key was read
  -- @treturn[2] string error message; `"timeout"` if the timeout was reached.
  function system.readkey(timeout)
    if type(timeout) ~= "number" then
      error("arg #1 to readkey, expected timeout in seconds, got " .. type(timeout), 2)
    end

    local interval = 0.0125
    local key = system._readkey()
    while key == nil and timeout > 0 do
      system.sleep(math.min(interval, timeout))
      timeout = timeout - interval
      interval = math.min(0.2, interval * 2)
      key = system._readkey()
    end

    if key then
      return key
    end
    return nil, "timeout"
  end
end



do
  local left_over_key
  local sequence -- table to store the sequence in progress
  local utf8_length -- length of utf8 sequence currently being processed
  local unpack = unpack or table.unpack

  --- Reads a single key, if it is the start of ansi escape sequence then it reads
  -- the full sequence. The key can be a multi-byte string in case of multibyte UTF-8 character.
  -- This function uses `system.readkey`, and hence `system.sleep` to wait until either a key is
  -- available or the timeout is reached.
  -- It returns immediately if a key is available or if `timeout` is less than or equal to `0`.
  -- In case of an ANSI sequence, it will return the full sequence as a string.
  -- @tparam number timeout the timeout in seconds.
  -- @treturn[1] string the character that was received (can be multi-byte), or a complete ANSI sequence
  -- @treturn[1] string the type of input: `"char"` for a single key, `"ansi"` for an ANSI sequence
  -- @treturn[2] nil in case of an error
  -- @treturn[2] string error message; `"timeout"` if the timeout was reached.
  -- @treturn[2] string partial result in case of an error while reading a sequence, the sequence so far.
  function system.readansi(timeout)
    if type(timeout) ~= "number" then
      error("arg #1 to readansi, expected timeout in seconds, got " .. type(timeout), 2)
    end

    local key

    if not sequence then
      -- no sequence in progress, read a key

      if left_over_key then
        -- we still have a cached key from the last call
        key = left_over_key
        left_over_key = nil
      else
        -- read a new key
        local err
        key, err = system.readkey(timeout)
        if key == nil then -- timeout or error
          return nil, err
        end
      end

      if key == 27 then
        -- looks like an ansi escape sequence, immediately read next char
        -- as an heuristic against manually typing escape sequences
        local key2 = system.readkey(0)
        if key2 ~= 91 and key2 ~= 79 then -- we expect either "[" or "O" for an ANSI sequence
          -- not the expected [ or O character, so we return the key as is
          -- and store the extra key read for the next call
          left_over_key = key2
          return string.char(key), "char"
        end

        -- escape sequence detected
        sequence = { key, key2 }
      else
        -- check UTF8 length
        utf8_length = key < 128 and 1 or key < 224 and 2 or key < 240 and 3 or key < 248 and 4
        if utf8_length  == 1 then
          -- single byte character
          utf8_length = nil
          return string.char(key), "char"
        else
          -- UTF8 sequence detected
          sequence = { key }
        end
      end
    end

    local err
    if utf8_length then
      -- read remainder of UTF8 sequence
      local timeout_end = system.gettime() + timeout
      while true do
        key, err = system.readkey(timeout_end - system.gettime())
        if err then
          break
        end
        table.insert(sequence, key)

        if #sequence == utf8_length then
          -- end of sequence, return the full sequence
          local result = string.char(unpack(sequence))
          sequence = nil
          utf8_length = nil
          return result, "char"
        end
      end

    else
      -- read remainder of ANSI sequence
      local timeout_end = system.gettime() + timeout
      while true do
        key, err = system.readkey(timeout_end - system.gettime())
        if err then
          break
        end
        table.insert(sequence, key)

        if (key >= 65 and key <= 90) or (key >= 97 and key <= 126) then
          -- end of sequence, return the full sequence
          local result = string.char(unpack(sequence))
          sequence = nil
          return result, "ansi"
        end
      end
    end

    -- error, or timeout reached, return the sequence so far
    local partial = string.char(unpack(sequence))
    return nil, err, partial
  end
end



return system
