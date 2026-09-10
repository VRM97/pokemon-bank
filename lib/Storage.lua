local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Utils = V.require("Utils")

local STORAGE_VERSION = 6
local PC_BOX_NAMES_KEY = "boxNames"

local Module = {}

function Module.install(mod, File)
  local Storage = { STORAGE_VERSION = STORAGE_VERSION }

  local function boxIdTaken(boxes, id)
    for _, box in ipairs(boxes) do
      if type(box) == "table" and box.id == id then return true end
    end
    return false
  end

  local function freshBox(boxes)
    return {
      id = Utils.generateId(function(id) return boxIdTaken(boxes, id) end),
      name = nil,
      content = {}
    }
  end

  function Storage.newBox(s) return freshBox(s.boxes) end

  local function freshStorage()
    local boxes = {}
    boxes[1] = freshBox(boxes)
    return {
      version = STORAGE_VERSION,
      boxes = boxes,
      currentBox = 1,
      items = {},
      moves = {},
      money = 0,
      timeCapsule = {},
    }
  end

  function Storage.ensureStorageId(s)
    if type(s.storageId) == "number" then return false end
    s.storageId = Utils.generateId()
    return true
  end

  function Storage.ensureOrphaned(s)
    if not s.orphaned then s.orphaned = { mons = {}, items = {}, moves = {}, monMoves = {}, timeCapsule = {} } end
    s.orphaned.mons = type(s.orphaned.mons) == "table" and s.orphaned.mons or {}
    s.orphaned.items = type(s.orphaned.items) == "table" and s.orphaned.items or {}
    s.orphaned.moves = type(s.orphaned.moves) == "table" and s.orphaned.moves or {}
    s.orphaned.monMoves = type(s.orphaned.monMoves) == "table" and s.orphaned.monMoves or {}
    s.orphaned.timeCapsule = type(s.orphaned.timeCapsule) == "table" and s.orphaned.timeCapsule or {}
    return s.orphaned
  end

  function Storage.reconcileCountBucket(bucket, orphanedBucket, isValid, fromLabel)
    local quarantined, restored = 0, 0
    local lostItems, restoredItems = {}, {}
    local badIds = {}
    for id in pairs(bucket) do
      if not isValid(id) then badIds[#badIds + 1] = id end
    end
    for _, id in ipairs(badIds) do
      local qty = bucket[id] or 0
      if qty > 0 then
        bucket[id] = nil
        orphanedBucket[id] = (orphanedBucket[id] or 0) + qty
        quarantined = quarantined + qty
        lostItems[#lostItems + 1] = { id = id, count = qty, from = fromLabel }
      end
    end
    local goodIds = {}
    for id in pairs(orphanedBucket) do
      if isValid(id) then goodIds[#goodIds + 1] = id end
    end
    for _, id in ipairs(goodIds) do
      local qty = orphanedBucket[id] or 0
      if qty > 0 then
        orphanedBucket[id] = nil
        bucket[id] = (bucket[id] or 0) + qty
        restored = restored + qty
        restoredItems[#restoredItems + 1] = { id = id, count = qty }
      end
    end
    return { quarantined = quarantined, restored = restored, lostItems = lostItems, restoredItems = restoredItems }
  end

  local boxCapacityOverride

  function Storage.boxCapacity()
    if boxCapacityOverride ~= nil then return boxCapacityOverride end
    local raw = tonumber(mod.options:get("box_size"))
    if raw == nil or raw == 0 then raw = 30 end
    raw = math.floor(raw)
    if raw < 0 then return math.huge end
    return raw
  end

  function Storage.normalizeBoxes(s)
    local boxes = type(s.boxes) == "table" and s.boxes or {}
    local policy = mod.options:get("empty_box_deletion") or "unnamed"
    local compact = {}
    for _, box in ipairs(boxes) do
      if type(box) == "table" then
        local content = type(box.content) == "table" and box.content or {}
        local name = type(box.name) == "string" and box.name ~= "" and box.name or nil
        local drop = #content == 0 and (policy == "all" or (policy == "unnamed" and not name))
        if not drop then
          local id = box.id
          if id == nil or boxIdTaken(compact, id) then
            id = Utils.generateId(function(candidate) return boxIdTaken(compact, candidate) end)
          end
          compact[#compact + 1] = { id = id, name = name, content = content }
        end
      end
    end
    if #compact == 0 or #compact[#compact].content > 0 then
      compact[#compact + 1] = freshBox(compact)
    end
    s.boxes = compact
    s.currentBox = math.max(1, math.min(#s.boxes, math.floor(tonumber(s.currentBox) or 1)))
    s.items = type(s.items) == "table" and s.items or {}
    s.moves = type(s.moves) == "table" and s.moves or {}
    s.money = math.max(0, math.floor(tonumber(s.money) or 0))
    s.timeCapsule = type(s.timeCapsule) == "table" and s.timeCapsule or {}
    if s.orphaned then
      Storage.ensureOrphaned(s)
      local orphaned = s.orphaned
      for id, count in pairs(orphaned.items) do
        if not count or count <= 0 then orphaned.items[id] = nil end
      end
      for id, count in pairs(orphaned.moves) do
        if not count or count <= 0 then orphaned.moves[id] = nil end
      end
      for bankId, moves in pairs(orphaned.monMoves) do
        if type(moves) ~= "table" or #moves == 0 then orphaned.monMoves[bankId] = nil end
      end
      if #orphaned.mons == 0 and next(orphaned.items) == nil and next(orphaned.moves) == nil and next(orphaned.monMoves) == nil and #orphaned.timeCapsule == 0 then s.orphaned = nil end
    end
  end

  function Storage.reflowBoxCapacity(s)
    local capacity = Storage.boxCapacity()
    if capacity == math.huge then return false end
    local excess = {}
    for _, box in ipairs(s.boxes) do
      local content = type(box) == "table" and box.content
      if type(content) == "table" and #content > capacity then
        for i = capacity + 1, #content do excess[#excess + 1] = content[i] end
        for i = #content, capacity + 1, -1 do content[i] = nil end
      end
    end
    if #excess == 0 then return false end
    local boxNum = math.max(1, #s.boxes)
    for _, mon in ipairs(excess) do
      local box = s.boxes[boxNum]
      if not box then
        box = freshBox(s.boxes)
        s.boxes[boxNum] = box
      end
      if #box.content >= capacity then
        boxNum = boxNum + 1
        box = freshBox(s.boxes)
        s.boxes[boxNum] = box
      end
      table.insert(box.content, mon)
    end
    return true
  end

  local function migrateStorage(s)
    local currentVersion = tonumber(s.version) or 1
    if currentVersion >= STORAGE_VERSION then return false end
    if currentVersion < 3 then
      local orphaned = { mons = {}, items = {} }
      if type(s.invalidPokemon) == "table" then
        for _, mon in ipairs(s.invalidPokemon) do
          if type(mon) == "table" then orphaned.mons[#orphaned.mons + 1] = mon end
        end
        s.invalidPokemon = nil
      end
      if type(s.invalidItems) == "table" then
        for id, count in pairs(s.invalidItems) do
          if count and count > 0 then orphaned.items[id] = count end
        end
        s.invalidItems = nil
      end
      -- Only set orphaned if it has content
      if #orphaned.mons > 0 or next(orphaned.items) ~= nil then s.orphaned = orphaned end
    end
    if currentVersion < 6 then
      local oldNames = type(s.boxNames) == "table" and s.boxNames or {}
      local oldBoxes = type(s.boxes) == "table" and s.boxes or {}
      local boxes = {}
      for i, content in ipairs(oldBoxes) do
        local name = oldNames[i]
        boxes[i] = {
          id = Utils.generateId(function(id) return boxIdTaken(boxes, id) end),
          name = (type(name) == "string" and name ~= "") and name or nil,
          content = type(content) == "table" and content or {},
        }
      end
      if #boxes == 0 then boxes[1] = freshBox(boxes) end
      s.boxes = boxes
      s.boxNames = nil
    end
    s.version = STORAGE_VERSION
    return true
  end

  local function normalizeStorage(decoded)
    local migrated = migrateStorage(decoded)
    local reflowed = Storage.reflowBoxCapacity(decoded)
    Storage.normalizeBoxes(decoded)
    return migrated or reflowed
  end

  local storage = File.new(mod, "storage.lua", freshStorage, normalizeStorage)
  Storage.markDirty = storage.markDirty
  Storage.isDirty = storage.isDirty
  Storage.loadStorage = storage.loadFile
  Storage.flushStorage = storage.flushFile
  Storage.replaceStorage = storage.replaceFile
  Storage.resetStorage = storage.resetFile
  Storage.readBackup = storage.readFileBackup
  Storage.deleteStorage = storage.deleteFile

  function Storage.listBoxes()
    local out = {}
    for index, box in ipairs(storage.loadFile().boxes or {}) do
      out[index] = {
        id = box.id,
        name = box.name,
      }
    end
    return out
  end

  function Storage.listOrphaned(bucketName)
    local out = {}
    local s = storage.loadFile()
    local orphaned = s.orphaned and s.orphaned[bucketName] or {}
    for id, count in pairs(orphaned) do out[id] = count end
    return out
  end

  function Storage.orphanedCount(bucketName, id)
    local s = storage.loadFile()
    local orphaned = s.orphaned and s.orphaned[bucketName] or {}
    if id ~= nil then return orphaned[id] or 0 end
    local n = 0
    for _, count in pairs(orphaned) do n = n + count end
    return n
  end

  function Storage.pcBoxNamesTable()
    local names = mod.save:get(PC_BOX_NAMES_KEY)
    if type(names) ~= "table" then
      names = {}
      mod.save:set(PC_BOX_NAMES_KEY, names)
    end
    return names
  end

  function Storage.pcBoxName(game, i)
    local name = Storage.pcBoxNamesTable()[i]
    if type(name) == "string" and name ~= "" then return name end
    if game and game.save and GameVersion.generation() == 2 then
      local Gen2Boxes = require("src.core.gen2.Boxes")
      local native = Gen2Boxes.name(game.save, i)
      if native ~= Gen2Boxes.defaultName(i) then return native end
    end
    return nil
  end

  function Storage.pcBoxLabel(game, i)
    return Storage.pcBoxName(game, i) or Strings("PC BOX %d", i)
  end

  function Storage.boxLabel(s, i)
    local box = s.boxes and s.boxes[i]
    local name = box and box.name
    if type(name) == "string" and name ~= "" then return name end
    return Strings("BOX %d", i)
  end

  function Storage.reapplyBoxPolicy()
    local s = storage.loadFile()
    Storage.reflowBoxCapacity(s)
    Storage.normalizeBoxes(s)
    storage.markDirty()
  end

  function Storage.setBoxSizeOverride(value)
    local newOverride
    if value == nil then
      newOverride = nil
    elseif value == math.huge then
      newOverride = math.huge
    else
      local n = tonumber(value)
      if not n or n ~= math.floor(n) or n <= 0 then return false, "bad request" end
      newOverride = n
    end
    if newOverride == boxCapacityOverride then return true end
    boxCapacityOverride = newOverride
    Storage.reapplyBoxPolicy()
    return true
  end

  function Storage.getBoxSizeOverride() return boxCapacityOverride end

  function Storage.getStorageId()
    local s = storage.loadFile()
    if Storage.ensureStorageId(s) then Storage.markDirty() end
    return s.storageId
  end
  return Storage
end

return Module
