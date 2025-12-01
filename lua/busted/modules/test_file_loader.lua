local function stat_type(target)
  local stat = vim.uv.fs_stat(target)
  return stat and stat.type or nil
end

local function collect_files(root, recursive)
  local files = {}

  local function walk(dir)
    local iter = vim.uv.fs_scandir(dir)
    if not iter then
      return
    end
    while true do
      local name, type = vim.uv.fs_scandir_next(iter)
      if not name then
        break
      end
      if name:sub(1, 1) ~= '.' then
        local full = vim.fs.joinpath(dir, name)
        if type == 'file' then
          files[#files + 1] = full
        elseif type == 'directory' and recursive then
          walk(full)
        end
      end
    end
  end

  walk(root)
  return files
end

--- @param busted busted.Busted
return function(busted)
  local loader = require('busted.modules.files.lua')

  local function getTestFiles(rootFile, patterns, options)
    local fileList --- @type string[]
    local rootType = stat_type(rootFile)

    if rootType == 'file' then
      fileList = { rootFile }
    elseif rootType == 'directory' then
      fileList = collect_files(rootFile, not not options.recursive)

      fileList = vim.tbl_filter(function(filename)
        local basename = vim.fs.basename(filename)
        for _, patt in ipairs(options.excludes or {}) do
          if patt ~= '' and basename:find(patt) then
            return false
          end
        end
        for _, patt in ipairs(patterns) do
          if basename:find(patt) then
            return true
          end
        end
        return #patterns == 0
      end, fileList)
    else
      busted:publish(
        { 'error' },
        {},
        nil,
        string.format('Cannot find file or directory: %s', rootFile),
        {}
      )
      fileList = {}
    end
    table.sort(fileList)
    return fileList
  end

  local function getAllTestFiles(rootFiles, patterns, options)
    local fileList = {}
    for _, root in ipairs(rootFiles) do
      vim.list_extend(fileList, getTestFiles(root, patterns, options))
    end
    return fileList
  end

  local function loadTestFile(busted_ctx, filename)
    if loader.match(busted_ctx, filename) then
      return loader.load(busted_ctx, filename)
    end
  end

  local function loadTestFiles(rootFiles, patterns, options)
    local fileList = getAllTestFiles(rootFiles, patterns, options)

    for _, fileName in ipairs(fileList) do
      local testFile, getTrace, rewriteMessage = loadTestFile(busted, fileName)

      if testFile then
        local file = setmetatable({
          getTrace = getTrace,
          rewriteMessage = rewriteMessage,
        }, {
          __call = testFile,
        })

        busted.executors.file(fileName, file)
      end
    end

    if #fileList == 0 then
      local pattern = patterns[1]
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
    return fileList
  end

  return loadTestFiles, loadTestFile, getAllTestFiles
end
