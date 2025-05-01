local utils = require('nvim-test.utils')

--- return a list of all files in a directory which match a shell pattern.
--- @param dirname? string A directory.
--- @param recursive? boolean If true, the function will search recursively in subdirectories.
--- @return string[] list of files
local function getfiles(dirname, recursive)
  dirname = dirname or '.'
  assert(utils.isdir(dirname), 'not a directory')

  local files = {} --- @type string[]
  for f, ty in vim.fs.dir(dirname, { depth = recursive and math.huge or nil }) do
    if ty == 'file' then
      files[#files + 1] = vim.fs.joinpath(dirname, f)
    end
  end
  return files
end

--- @param busted busted
--- @param loaders string[] A list of loaders to use.
return function(busted, loaders)
  ---@type nvim-test.Fileloader[]
  local fileLoaders = {}

  for _, v in pairs(loaders) do
    ---@type nvim-test.Fileloader
    local loader = require('busted.modules.files.' .. v)
    fileLoaders[#fileLoaders + 1] = loader
  end

  local function getTestFiles(rootFile, patterns, options)
    local ret --- @type string[]

    if utils.isfile(rootFile) then
      ret = { rootFile }
    elseif utils.isdir(rootFile) then
      ret = getfiles(rootFile, options.recursive)

      --- @param filename string
      --- @return boolean
      ret = vim.tbl_filter(function(filename)
        local basename = vim.fs.basename(filename)
        for _, patt in ipairs(options.excludes) do
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
      end, ret)

      --- @param filename string
      --- @return boolean
      ret = vim.tbl_filter(function(filename)
        if utils.is_windows then
          return not filename:find('%\\%.%w+.%w+', #rootFile)
        else
          return not filename:find('/%.%w+.%w+', #rootFile)
        end
      end, ret)
    else
      busted.publish(
        { 'error' },
        {},
        nil,
        ('Cannot find file or directory: %s'):format(rootFile),
        {}
      )
      ret = {}
    end

    table.sort(ret)
    return ret
  end

  local function getAllTestFiles(rootFiles, patterns, options)
    local fileList = {}
    for _, root in ipairs(rootFiles) do
      for _, e in ipairs(getTestFiles(root, patterns, options)) do
        table.insert(fileList, e)
      end
    end
    return fileList
  end

  -- runs a testfile, loading its tests
  local function loadTestFile(busted, filename)
    for _, v in pairs(fileLoaders) do
      if v.match(busted, filename) then
        return v.load(busted, filename)
      end
    end
  end

  local function loadTestFiles(rootFiles, patterns, options)
    local fileList = getAllTestFiles(rootFiles, patterns, options)

    for i, fileName in ipairs(fileList) do
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
      busted.publish({ 'error' }, {}, nil, ('No test files found matching Lua pattern: %s'):format(pattern), {})
    end

    return fileList
  end

  return loadTestFiles, loadTestFile, getAllTestFiles
end
