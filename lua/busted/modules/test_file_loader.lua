local FILE_NOT_FOUND_MSG = 'Cannot find file or directory: %s'
local NO_MATCHING_TESTS_MSG = 'No test files found matching Lua pattern: %s'

local uv = assert(vim and vim.uv, 'nvim-test requires vim.uv')
local fs = vim.fs

local function filter(list, predicate)
  return vim.tbl_filter(predicate, list)
end

local function stat_type(target)
  local stat = uv.fs_stat(target)
  return stat and stat.type or nil
end

local function collect_files(root, recursive)
  local files = {}

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

  walk(root)
  return files
end

return function(busted, loaders)
  local fileLoaders = {}

  for _, v in pairs(loaders) do
    local loader = require('busted.modules.files.' .. v)
    fileLoaders[#fileLoaders + 1] = loader
  end

  local function getTestFiles(rootFile, patterns, options)
    local fileList
    local rootType = stat_type(rootFile)

    if rootType == 'file' then
      fileList = { rootFile }
    elseif rootType == 'directory' then
      fileList = collect_files(rootFile, not not options.recursive)

      fileList = filter(fileList, function(filename)
        local basename = fs.basename(filename)
        for _, patt in ipairs(options.excludes or {}) do
          if patt ~= '' and basename:find(patt) then
            return nil
          end
        end
        for _, patt in ipairs(patterns) do
          if basename:find(patt) then
            return true
          end
        end
        return #patterns == 0
      end)
    else
      busted.publish({ 'error' }, {}, nil, string.format(FILE_NOT_FOUND_MSG, rootFile), {})
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
    for _, v in pairs(fileLoaders) do
      if v.match(busted_ctx, filename) then
        return v.load(busted_ctx, filename)
      end
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
      busted.publish({ 'error' }, {}, nil, string.format(NO_MATCHING_TESTS_MSG, pattern), {})
    end

    return fileList
  end

  return loadTestFiles, loadTestFile, getAllTestFiles
end
