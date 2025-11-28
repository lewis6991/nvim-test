local fmt = string.format

local M = {}

function M.arg_too_little(func, min_args, got)
  return fmt("the '%s' function requires a minimum of %s arguments, got: %s", func, min_args, got)
end

function M.bad_arg_type(index, func, expected, actual)
  return fmt("bad argument #%s to '%s' (%s expected, got %s)", index, func, expected, actual)
end

M.same_positive = 'Expected objects to be the same.\nPassed in:\n%s\nExpected:\n%s'
M.same_negative = 'Expected objects to not be the same.\nPassed in:\n%s\nDid not expect:\n%s'

M.equals_positive = 'Expected objects to be equal.\nPassed in:\n%s\nExpected:\n%s'
M.equals_negative = 'Expected objects to not be equal.\nPassed in:\n%s\nDid not expect:\n%s'

M.near_positive = 'Expected values to be near.\nPassed in:\n%s\nExpected:\n%s +/- %s'
M.near_negative = 'Expected values to not be near.\nPassed in:\n%s\nDid not expect:\n%s +/- %s'

M.matches_positive = 'Expected strings to match.\nPassed in:\n%s\nExpected:\n%s'
M.matches_negative = 'Expected strings not to match.\nPassed in:\n%s\nDid not expect:\n%s'

M.unique_positive = 'Expected object to be unique:\n%s'
M.unique_negative = 'Expected object to not be unique:\n%s'

M.error_positive = 'Expected a different error.\nCaught:\n%s\nExpected:\n%s'
M.error_negative = 'Expected no error, but caught:\n%s'

M.truthy_positive = 'Expected to be truthy, but value was:\n%s'
M.truthy_negative = 'Expected to not be truthy, but value was:\n%s'

M.falsy_positive = 'Expected to be falsy, but value was:\n%s'
M.falsy_negative = 'Expected to not be falsy, but value was:\n%s'

M.called_positive = 'Expected to be called %s time(s), but was called %s time(s)'
M.called_negative = 'Expected not to be called exactly %s time(s), but it was.'

M.called_at_least_positive = 'Expected to be called at least %s time(s), but was called %s time(s)'
M.called_at_most_positive = 'Expected to be called at most %s time(s), but was called %s time(s)'
M.called_more_than_positive =
  'Expected to be called more than %s time(s), but was called %s time(s)'
M.called_less_than_positive =
  'Expected to be called less than %s time(s), but was called %s time(s)'

M.called_with_positive =
  'Function was never called with matching arguments.\nCalled with (last call if any):\n%s\nExpected:\n%s'
M.called_with_negative =
  'Function was called with matching arguments at least once.\nCalled with (last matching call):\n%s\nDid not expect:\n%s'

M.returned_with_positive =
  'Function never returned matching arguments.\nReturned (last call if any):\n%s\nExpected:\n%s'
M.returned_with_negative =
  'Function returned matching arguments at least once.\nReturned (last matching call):\n%s\nDid not expect:\n%s'

M.returned_arguments_positive = 'Expected to be called with %s argument(s), but was called with %s'
M.returned_arguments_negative =
  'Expected not to be called with %s argument(s), but was called with %s'

M.array_holes_positive = 'Expected array to have holes, but none was found.'
M.array_holes_negative = 'Expected array to not have holes, hole found at position: %s'

return M
