-----------------------------------------------------
-- Serialization helpers for LuaCov statistics.
-- @class module
-- @name luacov.stats

local function read_lines(path)
  if vim and vim.fn and vim.fn.readfile then
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      return lines
    else
      return nil
    end
  end

  local fh = io.open(path, 'r')
  if not fh then
    return nil
  end
  local lines = {}
  for line in fh:lines() do
    table.insert(lines, line)
  end
  fh:close()
  return lines
end

local function write_lines(path, lines)
  if vim and vim.fn and vim.fn.writefile then
    local ok, res = pcall(vim.fn.writefile, lines, path)
    if not ok then
      error(res)
    end
    if res ~= 0 then
      error('writefile returned error code ' .. tostring(res))
    end
    return
  end

  local fh = assert(io.open(path, 'w'))
  for _, line in ipairs(lines) do
    fh:write(line, '\n')
  end
  fh:close()
end

---@class luacov.file_stats
---@field max integer
---@field max_hits integer
---@field [integer] integer

---@class luacov.stats
local stats = {}

-----------------------------------------------------
--- Loads the stats file.
---@param statsfile string path to the stats file.
---@return table<string,luacov.file_stats>|nil
function stats.load(statsfile)
   local raw = read_lines(statsfile)
   if not raw then
      return nil
   end

   local data = {}
   local i = 1
   while i <= #raw do
      local header = raw[i]
      if not header or header == "" then
         break
      end

      local max_str, filename = header:match("^(%d+):(.*)$")
      if not max_str then
         break
      end

      local max = tonumber(max_str)
      if not max then
         break
      end

      i = i + 1
      local hits_line = raw[i]
      if not hits_line then
         break
      end

      local filedata = {
         max = max,
         max_hits = 0,
      }
      data[filename] = filedata

      local entries = vim.split(vim.trim(hits_line), '%s+', { trimempty = true })
      for line_nr = 1, max do
         local hits = tonumber(entries[line_nr]) or 0
         if hits > 0 then
            filedata[line_nr] = hits
            filedata.max_hits = math.max(filedata.max_hits, hits)
         end
      end

      i = i + 1
   end

   if next(data) == nil then
      return nil
   end

   return data
end

-----------------------------------------------------
--- Saves data to the stats file.
---@param statsfile string path to the stats file.
---@param data table<string,luacov.file_stats>
function stats.save(statsfile, data)
   local filenames = {}
   for filename in pairs(data) do
      table.insert(filenames, filename)
   end
   table.sort(filenames)

   local lines = {}
   for _, filename in ipairs(filenames) do
      local filedata = data[filename]
      table.insert(lines, string.format("%d:%s", filedata.max, filename))

      local hits = {}
      for i = 1, filedata.max do
         hits[i] = tostring(filedata[i] or 0)
      end
      table.insert(lines, table.concat(hits, " "))
   end

   write_lines(statsfile, lines)
end

return stats
