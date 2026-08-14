local V = ... -- unused: no other lib/ module needed here, kept for the same header shape every lib/ file in this mod has

-- Currently inert: the mod sandbox removes iolib entirely and blocks love.system, both unconditionally regardless of permissions, so haveShell/haveFiles and osName below are always false/nil and canDialog() always returns false.
-- Every caller already has a working fixed-file fallback for that case, so this stays harmless rather than being removed.
local FileDialog = {}

local function haveShell()
  local ok, popen = pcall(function() return io and io.popen end)
  return (ok and popen) and true or false
end

local function haveFiles()
  local ok, open = pcall(function() return io and io.open end)
  return (ok and open) and true or false
end

local function osName()
  local ok, name = pcall(function() return love.system.getOS() end)
  return ok and name or nil
end

-- Runs a command and returns its trimmed stdout, or nil for anything that produced no line -- a cancelled dialog, a missing zenity, no shell at all.
local function commandOutput(cmd)
  if not haveShell() then return nil end
  local ok, pipe = pcall(io.popen, cmd)
  if not (ok and pipe) then return nil end
  local okRead, out = pcall(pipe.read, pipe, "*a")
  pcall(pipe.close, pipe)
  if not (okRead and type(out) == "string") then return nil end
  out = out:gsub("^%s+", ""):gsub("%s+$", "")
  return (out ~= "") and out or nil
end

-- Desktop only, same reasoning as StadiumRomPick.canDialog: Android's own picker is a native bridge whose kind -> filename mapping is a fixed list this mod cannot add a kind to, and NX/consoles have no shell at all.
function FileDialog.canDialog()
  if not (haveShell() and haveFiles()) then return false end
  local p = osName()
  return p == "Windows" or p == "OS X" or p == "Linux"
end

-- Open dialog: choose an existing file. Returns the chosen absolute path, or nil (cancelled, or no dialog on this platform).
function FileDialog.chooseOpen(prompt, filterName, pattern)
  local p = osName()
  if p == "OS X" then
    return commandOutput((
      [[osascript -e 'POSIX path of (choose file with prompt "%s")' 2>/dev/null]]
    ):format(prompt))
  elseif p == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='" .. filterName .. " (" .. pattern .. ")|" .. pattern
        .. "|All files (*.*)|*.*';",
      -- as UTF-8: the console's OEM codepage would mangle a non-ASCII path and crash the next text draw that showed it
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding="
        .. "[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif p == "Linux" then
    local path = commandOutput((
      [[zenity --file-selection --title="%s" --file-filter="%s | %s" 2>/dev/null]]
    ):format(prompt, filterName, pattern))
    if path then return path end
    -- zenity is absent on plenty of installs (most handheld Linux distros included); KDE's own dialog is the usual second answer
    return commandOutput((
      [[kdialog --getopenfilename "$HOME" "%s|%s" 2>/dev/null]]
    ):format(pattern, filterName))
  end
  return nil
end

-- Save dialog: choose a destination, new or existing. Returns the chosen absolute path (whatever extension the player typed, or none -- callers append their own default if missing), or nil.
function FileDialog.chooseSave(prompt, defaultName, filterName, pattern)
  local p = osName()
  if p == "OS X" then
    return commandOutput((
      [[osascript -e 'POSIX path of (choose file name with prompt "%s" default name "%s")' 2>/dev/null]]
    ):format(prompt, defaultName))
  elseif p == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.SaveFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.FileName='" .. defaultName .. "';",
      "$d.Filter='" .. filterName .. " (" .. pattern .. ")|" .. pattern
        .. "|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding="
        .. "[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif p == "Linux" then
    local path = commandOutput((
      [[zenity --file-selection --save --confirm-overwrite --filename="%s" --title="%s" 2>/dev/null]]
    ):format(defaultName, prompt))
    if path then return path end
    return commandOutput((
      [[kdialog --getsavefilename "$HOME/%s" "%s|%s" 2>/dev/null]]
    ):format(defaultName, pattern, filterName))
  end
  return nil
end

-- Absolute-path read/write: love.filesystem only sees inside its physfs mount, and a picked file can be anywhere on disk.
function FileDialog.readFile(path)
  if not haveFiles() then return nil, "no file access" end
  local ok, fp = pcall(io.open, path, "rb")
  if not (ok and fp) then return nil, "could not open that file" end
  local okRead, bytes = pcall(fp.read, fp, "*a")
  pcall(fp.close, fp)
  if not (okRead and type(bytes) == "string") then
    return nil, "could not read that file"
  end
  return bytes
end

function FileDialog.writeFile(path, data)
  if not haveFiles() then return false, "no file access" end
  local ok, fp = pcall(io.open, path, "wb")
  if not (ok and fp) then return false, "could not create that file" end
  local okWrite = pcall(fp.write, fp, data)
  pcall(fp.close, fp)
  if not okWrite then return false, "could not write that file" end
  return true
end

return FileDialog
