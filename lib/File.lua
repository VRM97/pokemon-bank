local V = ...

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")

local DIRNAME = "bank"

local Module = {}

function Module.fs()
  return SaveData.persistenceFs()
end

function Module.exists(name)
  local fs = Module.fs()
  local ok, info = pcall(fs.getInfo, name)
  return ok and info ~= nil
end

function Module.read(name)
  local fs = Module.fs()
  local ok, result = pcall(fs.read, name)
  if ok and type(result) == "string" then return result end
  return nil
end

function Module.write(name, data)
  local fs = Module.fs()
  local ok, result = pcall(fs.write, name, data)
  return ok and result ~= false
end

function Module.remove(name)
  local fs = Module.fs()
  pcall(fs.remove, name)
end

function Module.readDecoded(name)
  if not Module.exists(name) then return nil end
  local raw = Module.read(name)
  if not raw then return nil end
  local decoded = SaveSerializer.decode(raw)
  if type(decoded) ~= "table" then return nil end
  return decoded
end

function Module.writeWithBackup(fileName, backupName, tmpName, encoded)
  if Module.exists(fileName) then
    local prev = Module.read(fileName)
    if prev then Module.write(backupName, prev) end
  end
  if not Module.write(tmpName, encoded) then
    return false, ("could not stage %s"):format(tmpName)
  end
  Module.remove(fileName)
  if not Module.write(fileName, encoded) then
    return false, ("could not write %s"):format(fileName)
  end
  Module.remove(tmpName)
  return true
end

function Module.new(mod, filename, freshFile, onFileLoad)
  local FILE = DIRNAME .. "/" .. filename
  local BACKUP = FILE .. ".bak"
  local TMP = FILE .. ".tmp"
  local KNOWN_FILES = { FILE, BACKUP, TMP }
  local file
  local dirty = false

  local File = {
    STORAGE_DIR = DIRNAME,
    markDirty = function() dirty = true end,
    isDirty = function() return dirty end,
  }

  function File.replaceFile(decoded)
    if (type(onFileLoad) == "function" and onFileLoad(decoded)) then File.markDirty() end
    file = decoded
    return file
  end

  function File.loadFile()
    if file then return file end
    local decoded = Module.readDecoded(FILE) or Module.readDecoded(TMP) or Module.readDecoded(BACKUP) or freshFile()
    return File.replaceFile(decoded)
  end

  function File.readFileBackup()
    return Module.readDecoded(BACKUP)
  end

  function File.restoreFileBackup()
    local decoded = Module.readDecoded(TMP) or Module.readDecoded(BACKUP)
    if not decoded then return false end
    File.replaceFile(decoded)
  end

  function File.reloadFile()
    file = nil
    return File.loadFile()
  end

  function File.flushFile()
    local was = dirty
    if not (dirty and file) then return was end
    local fs = Module.fs()
    pcall(fs.createDirectory, DIRNAME)
    local ok, encoded = pcall(SaveSerializer.encode, file)
    if not ok then
      mod.log:warn("could not encode file %s", FILE)
      return was
    end
    local written, err = Module.writeWithBackup(FILE, BACKUP, TMP, encoded)
    if not written then
      mod.log:warn("%s", err)
      return was
    end
    dirty = false
    return was
  end

  function File.resetFile()
    file = freshFile()
    dirty = false
  end

  function File.deleteFile()
    for _, name in ipairs(KNOWN_FILES) do Module.remove(name) end
  end

  return File
end

return Module