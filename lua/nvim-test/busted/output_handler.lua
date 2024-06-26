return function(options)
  local busted = require('busted')
  local handler = require('busted.outputHandlers.base')()
  local colors = require('term.colors')
  local pretty = require('pl.pretty')

  --- @type table<string,fun(s:string): string>
  local c = {
    succ = function(s)
      return colors.bright(colors.green(s))
    end,
    skip = function(s)
      return colors.bright(colors.yellow(s))
    end,
    fail = function(s)
      return colors.bright(colors.magenta(s))
    end,
    errr = function(s)
      return colors.bright(colors.red(s))
    end,
    test = tostring,
    file = colors.cyan,
    time = colors.dim,
    note = colors.yellow,
    sect = function(s)
      return colors.green(colors.dim(s))
    end,
    nmbr = colors.bright,
  }

  local repeatSuiteString = '\nRepeating all tests (run %d of %d) . . .\n\n'
  local randomizeString = c.note('Note: Randomizing test order with a seed of %d.\n')
  local globalSetup = c.sect('--------') .. ' Global test environment setup.\n'
  local fileStartString = c.sect('--------') .. ' Running tests from ' .. c.file('%s') .. '\n'
  local runString = c.sect('RUN     ') .. ' ' .. c.test('%s') .. ': '
  local successString = c.succ('OK') .. '\n'
  local skippedString = c.skip('SKIP') .. '\n'
  local failureString = c.fail('FAIL') .. '\n'
  local errorString = c.errr('ERR') .. '\n'
  local fileEndString = c.sect('--------')
    .. ' '
    .. c.nmbr('%d')
    .. ' %s from '
    .. c.file('%s')
    .. ' '
    .. c.time('(%.2f ms total)')
    .. '\n\n'
  local globalTeardown = c.sect('--------') .. ' Global test environment teardown.\n'
  local suiteEndString = string.format(
    '%s %s %%s from %s test %%s ran. %s\n',
    c.sect('========'),
    c.nmbr('%d'),
    c.nmbr('%d'),
    c.time('(%.2f ms total)')
  )
  local successStatus = c.succ('PASSED  ') .. ' ' .. c.nmbr('%d') .. ' %s.\n'
  local timeString = c.time('%.2f ms')

  local summaryStrings = {
    skipped = {
      header = c.skip('SKIPPED ') .. ' ' .. c.nmbr('%d') .. ' %s, listed below:\n',
      test = c.skip('SKIPPED ') .. ' %s\n',
      footer = ' ' .. c.nmbr('%d') .. ' SKIPPED %s\n',
    },

    failure = {
      header = c.fail('FAILED  ') .. ' ' .. c.nmbr('%d') .. ' %s, listed below:\n',
      test = c.fail('FAILED  ') .. ' %s\n',
      footer = ' ' .. c.nmbr('%d') .. ' FAILED %s\n',
    },

    error = {
      header = c.errr('ERROR   ') .. ' ' .. c.nmbr('%d') .. ' %s, listed below:\n',
      test = c.errr('ERROR   ') .. ' %s\n',
      footer = ' ' .. c.nmbr('%d') .. ' %s\n',
    },
  }

  local fileCount = 0
  local fileTestCount = 0
  local testCount = 0
  local successCount = 0
  local skippedCount = 0
  local failureCount = 0
  local errorCount = 0

  local pendingDescription = function(pending)
    local s = ''

    if type(pending.message) == 'string' then
      s = s .. pending.message .. '\n'
    elseif pending.message ~= nil then
      s = s .. pretty.write(pending.message) .. '\n'
    end

    return s
  end

  local failureDescription = function(failure)
    local s = failure.randomseed and ('Random seed: ' .. failure.randomseed .. '\n') or ''
    if type(failure.message) == 'string' then
      s = s .. failure.message
    elseif failure.message == nil then
      s = s .. 'Nil error'
    else
      s = s .. pretty.write(failure.message)
    end

    s = s .. '\n'

    if options.verbose and failure.trace and failure.trace.traceback then
      s = s .. failure.trace.traceback .. '\n'
    end

    return s
  end

  local getFileLine = function(element)
    local fileline = ''
    if element.trace or element.trace.short_src then
      fileline = colors.cyan(element.trace.short_src)
        .. ' @ '
        .. colors.cyan(element.trace.currentline)
        .. ': '
    end
    return fileline
  end

  local getTestList = function(status, count, list, getDescription)
    local s = ''
    local header = summaryStrings[status].header
    if count > 0 and header then
      local tests = (count == 1 and 'test' or 'tests')
      local errors = (count == 1 and 'error' or 'errors')
      s = header:format(count, status == 'error' and errors or tests)

      local testString = summaryStrings[status].test
      if testString then
        for _, t in ipairs(list) do
          local fullname = getFileLine(t.element) .. colors.bright(t.name)
          s = s .. testString:format(fullname)
          s = s .. getDescription(t)
        end
      end
    end
    return s
  end

  local getSummary = function(status, count)
    local footer = summaryStrings[status].footer
    if count > 0 and footer then
      local tests = (count == 1 and 'TEST' or 'TESTS')
      local errors = (count == 1 and 'ERROR' or 'ERRORS')
      return footer:format(count, status == 'error' and errors or tests)
    end
    return ''
  end

  local getSummaryString = function()
    local tests = (successCount == 1 and 'test' or 'tests')
    return table.concat({
      successStatus:format(successCount, tests),

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

  handler.suiteStart = function(_suite, count, total, randomseed)
    if total > 1 then
      io.write(repeatSuiteString:format(count, total))
    end
    if randomseed then
      io.write(randomizeString:format(randomseed))
    end
    io.write(globalSetup)
    io.flush()

    return nil, true
  end

  local function getElapsedTime(tbl)
    if tbl.duration then
      return tbl.duration * 1000
    else
      return tonumber('nan')
    end
  end

  handler.suiteEnd = function(suite, _count, _total)
    local elapsedTime_ms = getElapsedTime(suite)
    local tests = testCount == 1 and 'test' or 'tests'
    local files = fileCount == 1 and 'file' or 'files'
    io.write(globalTeardown)
    io.write(suiteEndString:format(testCount, tests, fileCount, files, elapsedTime_ms))
    io.write(getSummaryString())
    io.flush()

    return nil, true
  end

  handler.fileStart = function(file)
    fileTestCount = 0
    io.write(fileStartString:format(vim.fs.normalize(file.name)))
    io.flush()
    return nil, true
  end

  handler.fileEnd = function(file)
    local elapsedTime_ms = getElapsedTime(file)
    local tests = fileTestCount == 1 and 'test' or 'tests'
    fileCount = fileCount + 1
    io.write(
      fileEndString:format(fileTestCount, tests, vim.fs.normalize(file.name), elapsedTime_ms)
    )
    io.flush()
    return nil, true
  end

  handler.testStart = function(element, _parent)
    local desc = (' %s'):format(handler.getFullName(element))
    io.write(runString:format(desc))
    io.flush()

    return nil, true
  end

  local function write_status(element, string)
    io.write(timeString:format(getElapsedTime(element)) .. ' ' .. string)
    io.flush()
  end

  handler.testEnd = function(element, _parent, status, _debug)
    local s --- @type string

    fileTestCount = fileTestCount + 1
    testCount = testCount + 1
    if status == 'success' then
      successCount = successCount + 1
      s = successString
    elseif status == 'pending' then
      skippedCount = skippedCount + 1
      s = skippedString
    elseif status == 'failure' then
      failureCount = failureCount + 1
      s = failureString .. failureDescription(handler.failures[#handler.failures])
    elseif status == 'error' then
      errorCount = errorCount + 1
      s = errorString .. failureDescription(handler.errors[#handler.errors])
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
