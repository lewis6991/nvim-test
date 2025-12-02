--- @class test_file_loader.Options
--- @field recursive? boolean
--- @field excludes? string[]

--- @alias test_file_loader.LoadedFile fun(...: any): any
---
--- @alias test_file_loader.GetTrace
--- fun(filename: string, info: table): table?

--- @alias test_file_loader.LoadTestFile
--- fun(busted_ctx: busted.Busted, filename: string): (
---   test_file_loader.LoadedFile?,
---   test_file_loader.GetTrace?
--- )

local fs = vim.fs
local uv = vim.uv
local EMPTY_OPTIONS = {} ---@type test_file_loader.Options
local EMPTY_PATTERNS = {} ---@type string[]

--- @param target string
--- @return string?
local function get_path_type(target)
  local stat = uv.fs_stat(target)
  if not stat then
    return nil
  end
  return stat.type
end

--- @param directory string
--- @param recursive boolean
--- @return string[]
local function collect_files(directory, recursive)
  local files = {} ---@type string[]

  ---@param dir string
  local function walk(dir)
    local iter = uv.fs_scandir(dir)
    if not iter then
      return
    end
    while true do
      local name, type = uv.fs_scandir_next(iter)
      if not name then
        break
      end
      if name:sub(1, 1) ~= '.' then
        local full = fs.joinpath(dir, name)
        if type == 'file' then
          files[#files + 1] = full
        elseif type == 'directory' and recursive then
          walk(full)
        end
      end
    end
  end

  walk(directory)
  return files
end

--- @param filename string
--- @param patterns string[]
--- @param excludes string[]
--- @return boolean
local function should_include_file(filename, patterns, excludes)
  local basename = fs.basename(filename)

  for _, patt in ipairs(excludes) do
    if patt ~= '' and basename:find(patt) then
      return false
    end
  end

  if #patterns == 0 then
    return true
  end

  for _, patt in ipairs(patterns) do
    if basename:find(patt) then
      return true
    end
  end

  return false
end

--- @param busted busted.Busted
--- @param root string
--- @param patterns string[]
--- @param options test_file_loader.Options
--- @return string[]
local function gather_root_files(busted, root, patterns, options)
  local root_type = get_path_type(root)

  if root_type == 'file' then
    return { root }
  end

  if root_type == 'directory' then
    local excludes = options.excludes or {}
    local recursive = options.recursive == true
    local files = collect_files(root, recursive)

    return vim.tbl_filter(function(path)
      return should_include_file(path, patterns, excludes)
    end, files)
  end

  busted:publish({ 'error' }, {}, nil, string.format('Cannot find file or directory: %s', root), {})
  return {}
end

--- @param busted busted.Busted
--- @param patterns string[]
local function publish_no_matches(busted, patterns)
  local pattern = patterns[1] or ''
  if #patterns > 1 then
    pattern = '\n\t' .. table.concat(patterns, '\n\t')
  end

  busted:publish(
    { 'error' },
    {},
    nil,
    string.format('No test files found matching Lua pattern: %s', pattern),
    {}
  )
end

--- @param _filename string
--- @param info table
--- @return table
local function trim_c_frames(_filename, info)
  local index = info.traceback:find('\n%s*%[C]')
  if index then
    info.traceback = info.traceback:sub(1, index)
  end
  return info
end

--- @param busted busted.Busted
--- @param rootFiles string[]
--- @param patterns string[]?
--- @param options test_file_loader.Options?
--- @return string[]
local function get_all_test_files(busted, rootFiles, patterns, options)
  options = options or EMPTY_OPTIONS
  patterns = patterns or EMPTY_PATTERNS
  local fileList = {} ---@type string[]
  for _, root in ipairs(rootFiles) do
    local files = gather_root_files(busted, root, patterns, options)
    table.sort(files)
    vim.list_extend(fileList, files)
  end
  return fileList
end

--- @param busted_ctx busted.Busted
--- @param filename string
--- @return test_file_loader.LoadedFile?, test_file_loader.GetTrace?
local function load_test_file(busted_ctx, filename)
  if filename:sub(-4) == '.lua' then
    local file, err = loadfile(filename)
    if not file then
      busted_ctx:publish(
        { 'error', 'file' },
        { descriptor = 'file', name = filename },
        nil,
        err,
        {}
      )
      return nil, nil
    end
    return file, trim_c_frames
  end
end

--- @param busted busted.Busted
--- @param rootFiles string[]
--- @param patterns string[]?
--- @param options test_file_loader.Options?
--- @return string[]
return function(busted, rootFiles, patterns, options)
  patterns = patterns or EMPTY_PATTERNS
  options = options or EMPTY_OPTIONS
  local fileList = get_all_test_files(busted, rootFiles, patterns, options)

  for _, fileName in ipairs(fileList) do
    local testFile, getTrace = load_test_file(busted, fileName)

    if testFile then
      --- @type busted.CallableValue
      local file = setmetatable({
        getTrace = getTrace,
      }, {
        __call = testFile,
      })

      busted.executors.file(fileName, file)
    end
  end

  if #fileList == 0 then
    publish_no_matches(busted, patterns)
  end

  return fileList
end
