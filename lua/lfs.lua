local uv = vim.uv

local lfs = { _VERSION = 'fake' }
package.loaded['lfs'] = lfs

function lfs.attributes(path, attr)
  local stat = uv.fs_stat(path)
  if attr == 'mode' then
    return stat and stat.type or ''
  elseif attr == 'modification' then
    if not stat then
      return nil
    end
    local mtime = stat.mtime
    return mtime.sec + mtime.nsec * 1e-9
  else
    error('not implemented')
  end
end

function lfs.currentdir()
  return uv.cwd()
end

function lfs.chdir(dir)
  local status, err = pcall(uv.chdir, dir)
  if status then
    return true
  else
    return nil, err
  end
end

function lfs.dir(path)
  local fs = uv.fs_scandir(path)
  return function()
    if not fs then
      return
    end
    return uv.fs_scandir_next(fs)
  end
end

function lfs.mkdir(dir)
  return uv.fs_mkdir(dir, 493) -- octal 755
end

return lfs
