local helpers = require('nvim-test.helpers')
local eq = helpers.eq
local path = require('pl.path')

describe('pl.path', function()
  it('joins paths correctly', function()
    eq('folder/subfolder/file.txt', path.join('folder', 'subfolder', 'file.txt'))
    eq('folder/subfolder/file.txt', path.join('folder', '', 'subfolder', 'file.txt'))
  end)

  it('splits directory and file components', function()
    local dir, file = path.splitpath('folder/subfolder/file.txt')
    eq('folder/subfolder', dir)
    eq('file.txt', file)

    local trailing_dir, trailing_file = path.splitpath('folder/subfolder/')
    eq('folder/subfolder', trailing_dir)
    eq('', trailing_file)
  end)

  it('extracts extensions from the final segment only', function()
    local root, ext = path.splitext('archive.tar.gz')
    eq('archive.tar', root)
    eq('.gz', ext)

    local dir_root, dir_ext = path.splitext('dir.name/file')
    eq('dir.name/file', dir_root)
    eq('', dir_ext)
  end)

  it('derives dirname and basename wrappers', function()
    eq('folder/subfolder', path.dirname('folder/subfolder/file.txt'))
    eq('file.txt', path.basename('folder/subfolder/file.txt'))
    eq('', path.dirname('file.txt'))
    eq('', path.basename('folder/subfolder/'))
  end)

  it('normalizes redundant path segments', function()
    eq('foo/baz', path.normpath('foo//bar/../baz/.'))
    eq('.', path.normpath(''))
  end)

  it('computes relative paths from different anchors', function()
    eq('b/c', path.relpath('/a/b/c', '/a'))
    eq('../c', path.relpath('/a/c', '/a/b'))
  end)
end)
