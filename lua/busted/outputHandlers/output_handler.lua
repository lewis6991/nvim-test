local ESC = string.char(27)
local RESET = ESC .. '[0m'

--- @param code string
--- @return fun(x: string): string
local function wrap(code)
  local prefix = ESC .. '[' .. code .. 'm'
  return function(text)
    text = tostring(text or '')
    if text == '' then
      return ''
    end
    return prefix .. text .. RESET
  end
end

local colors = {
  reset = RESET,
  black = wrap('30'),
  red = wrap('31'),
  green = wrap('32'),
  yellow = wrap('33'),
  blue = wrap('34'),
  magenta = wrap('35'),
  cyan = wrap('36'),
  white = wrap('37'),
  bright = wrap('1'),
  dim = wrap('2'),
}

--- @param value any
--- @return string
local function pretty(value)
  if type(value) == 'string' then
    return value
  end
  return vim.inspect(value)
end

local function succ(s)
  return colors.bright(colors.green(s))
end

local function skip(s)
  return colors.bright(colors.yellow(s))
end

local function fail(s)
  return colors.bright(colors.magenta(s))
end

local function errr(s)
  return colors.bright(colors.red(s))
end

local function sect(s)
  return colors.green(colors.dim(s))
end

local file = colors.cyan
local time = colors.dim
local nmbr = colors.bright

local function getFileLine(element)
  local fileline = ''
  if element.trace or element.trace.short_src then
    fileline = file(element.trace.short_src) .. ' @ ' .. file(element.trace.currentline) .. ': '
  end
  return fileline
end

local function pendingDescription(pending)
  local s = ''

  if type(pending.message) == 'string' then
    s = s .. pending.message .. '\n'
  elseif pending.message ~= nil then
    s = s .. pretty(pending.message) .. '\n'
  end

  return s
end

local summaryStrings = {
  skipped = {
    header = skip('SKIPPED ') .. ' ' .. nmbr('%d') .. ' %s, listed below:\n',
    test = skip('SKIPPED ') .. ' %s\n',
    footer = ' ' .. nmbr('%d') .. ' SKIPPED %s\n',
  },

  failure = {
    header = fail('FAILED  ') .. ' ' .. nmbr('%d') .. ' %s, listed below:\n',
    test = fail('FAILED  ') .. ' %s\n',
    footer = ' ' .. nmbr('%d') .. ' FAILED %s\n',
  },

  error = {
    header = errr('ERROR   ') .. ' ' .. nmbr('%d') .. ' %s, listed below:\n',
    test = errr('ERROR   ') .. ' %s\n',
    footer = ' ' .. nmbr('%d') .. ' %s\n',
  },
}

local function getTestList(status, count, list, getDescription)
  local s = ''
  local header = summaryStrings[status].header
  if count > 0 and header then
    local tests = (count == 1 and 'test' or 'tests')
    local errors = (count == 1 and 'error' or 'errors')
    s = header:format(count, status == 'error' and errors or tests)

    local testString = summaryStrings[status].test
    if testString then
      for _, t in ipairs(list) do
        --- @diagnostic disable-next-line: preferred-local-alias
        local fullname = getFileLine(t.element) .. colors.bright(t.name)
        s = s .. testString:format(fullname)
        s = s .. getDescription(t)
      end
    end
  end
  return s
end

local function getSummary(status, count)
  local footer = summaryStrings[status].footer
  if count > 0 and footer then
    local tests = (count == 1 and 'TEST' or 'TESTS')
    local errors = (count == 1 and 'ERROR' or 'ERRORS')
    return footer:format(count, status == 'error' and errors or tests)
  end
  return ''
end

local function getElapsedTime(tbl)
  if tbl.duration then
    return tbl.duration * 1000
  end
  return tonumber('nan')
end

return function(options)
  local busted = require('busted')
  local handler = require('busted.outputHandlers.base')()

  local fileCount = 0
  local fileTestCount = 0
  local testCount = 0
  local successCount = 0
  local skippedCount = 0
  local failureCount = 0
  local errorCount = 0

  local failureDescription = function(failure)
    local s = ''
    if type(failure.message) == 'string' then
      s = s .. failure.message
    elseif failure.message == nil then
      s = s .. 'Nil error'
    else
      s = s .. pretty(failure.message)
    end

    s = s .. '\n'

    if options.verbose and failure.trace and failure.trace.traceback then
      s = s .. failure.trace.traceback .. '\n'
    end

    return s
  end

  local getSummaryString = function()
    local tests = (successCount == 1 and 'test' or 'tests')
    return table.concat({
      (succ('PASSED  ') .. ' ' .. nmbr('%d') .. ' %s.\n'):format(successCount, tests),

      getTestList('skipped', skippedCount, handler.pendings, pendingDescription),
      getTestList('failure', failureCount, handler.failures, failureDescription),
      getTestList('error', errorCount, handler.errors, failureDescription),

      ((skippedCount + failureCount + errorCount) > 0 and '\n' or ''),
      getSummary('skipped', skippedCount),
      getSummary('failure', failureCount),
      getSummary('error', errorCount),
    })
  end

  handler.suiteReset = function()
    fileCount = 0
    fileTestCount = 0
    testCount = 0
    successCount = 0
    skippedCount = 0
    failureCount = 0
    errorCount = 0

    return nil, true
  end

  handler.suiteStart = function(_suite, count, total)
    if total > 1 then
      io.write(('\nRepeating all tests (run %d of %d) . . .\n\n'):format(count, total))
    end
    io.write(sect('--------') .. ' Global test environment setup.\n')
    io.flush()

    return nil, true
  end

  handler.suiteEnd = function(suite, _count, _total)
    local tests = testCount == 1 and 'test' or 'tests'
    local files = fileCount == 1 and 'file' or 'files'
    io.write(sect('--------') .. ' Global test environment teardown.\n')
    local suiteEndString = string.format(
      '%s %s %%s from %s test %%s ran. %s\n',
      sect('========'),
      nmbr('%d'),
      nmbr('%d'),
      time('(%.2f ms total)')
    )
    io.write(suiteEndString:format(testCount, tests, fileCount, files, getElapsedTime(suite)))
    io.write(getSummaryString())
    io.flush()

    return nil, true
  end

  handler.fileStart = function(f)
    fileTestCount = 0
    io.write(sect('--------') .. ' Running tests from ' .. file(vim.fs.normalize(f.name)) .. '\n')
    io.flush()
    return nil, true
  end

  handler.fileEnd = function(f)
    local tests = fileTestCount == 1 and 'test' or 'tests'
    fileCount = fileCount + 1
    local fileEndString = sect('--------')
      .. ' '
      .. nmbr('%d')
      .. ' %s from '
      .. file('%s')
      .. ' '
      .. time('(%.2f ms total)')
      .. '\n\n'
    io.write(
      fileEndString:format(fileTestCount, tests, vim.fs.normalize(f.name), getElapsedTime(f))
    )
    io.flush()
    return nil, true
  end

  handler.testStart = function(element, _parent)
    local desc = (' %s'):format(handler.getFullName(element))
    io.write(sect('RUN     ') .. ' ' .. tostring(desc) .. ': ')
    io.flush()

    return nil, true
  end

  local function write_status(element, string)
    io.write(time('%.2f ms'):format(getElapsedTime(element)) .. ' ' .. string)
    io.flush()
  end

  handler.testEnd = function(element, _parent, status, _debug)
    local s --- @type string

    fileTestCount = fileTestCount + 1
    testCount = testCount + 1
    if status == 'success' then
      successCount = successCount + 1
      s = succ('OK') .. '\n'
    elseif status == 'pending' then
      skippedCount = skippedCount + 1
      s = skip('SKIP') .. '\n'
    elseif status == 'failure' then
      failureCount = failureCount + 1
      s = fail('FAIL') .. '\n' .. failureDescription(handler.failures[#handler.failures])
    elseif status == 'error' then
      errorCount = errorCount + 1
      s = errr('ERR') .. '\n' .. failureDescription(handler.errors[#handler.errors])
    else
      s = 'unexpected test status! (' .. status .. ')'
    end
    write_status(element, s)

    return nil, true
  end

  handler.error = function(element, _parent, _message, _debug)
    if element.descriptor ~= 'it' then
      write_status(element, failureDescription(handler.errors[#handler.errors]))
      errorCount = errorCount + 1
    end

    return nil, true
  end

  busted.subscribe({ 'suite', 'reset' }, handler.suiteReset)
  busted.subscribe({ 'suite', 'start' }, handler.suiteStart)
  busted.subscribe({ 'suite', 'end' }, handler.suiteEnd)
  busted.subscribe({ 'file', 'start' }, handler.fileStart)
  busted.subscribe({ 'file', 'end' }, handler.fileEnd)
  busted.subscribe({ 'test', 'start' }, handler.testStart, { predicate = handler.cancelOnPending })
  busted.subscribe({ 'test', 'end' }, handler.testEnd, { predicate = handler.cancelOnPending })
  busted.subscribe({ 'failure' }, handler.error)
  busted.subscribe({ 'error' }, handler.error)

  return handler
end
