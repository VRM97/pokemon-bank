local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Utils = V.require("Utils")
local BoxAccess = V.require("BoxAccess")
local Progress = V.require("Progress")
local CustomStorageModule = V.require("CustomStorage")

local STORAGE_VERSION = 8
local PC_BOX_NAMES_KEY = "boxNames"
local CURRENT_BOX_KEY = "bank_current_box"

local Module = {}

function Module.install(mod)
  local CustomStorage = CustomStorageModule.install(mod)
  local Storage = { STORAGE_VERSION = STORAGE_VERSION, CustomStorage = CustomStorage }

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

  function Storage.newBox(s) return freshBox(s.entries.boxes) end

  function Storage.ensureStorageId(s)
    if type(s.storageId) == "number" then return false end
    s.storageId = Utils.generateId()
    return true
  end

  function Storage.ensureOrphaned(s) return s.orphaned end

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

  local function compactBoxes(boxes)
    local policy = mod.options:get("empty_box_deletion") or "unnamed"
    local compact = {}
    for _, box in ipairs(type(boxes) == "table" and boxes or {}) do
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
    while #compact < 2 do compact[#compact + 1] = freshBox(compact) end
    return compact
  end

  local function reflowBoxes(boxes)
    local capacity = Storage.boxCapacity()
    if capacity == math.huge then return boxes, false end
    local excess = {}
    for _, box in ipairs(boxes) do
      local content = type(box) == "table" and box.content
      if type(content) == "table" and #content > capacity then
        for i = capacity + 1, #content do excess[#excess + 1] = content[i] end
        for i = #content, capacity + 1, -1 do content[i] = nil end
      end
    end
    if #excess == 0 then return boxes, false end
    local boxNum = math.max(1, #boxes)
    for _, mon in ipairs(excess) do
      local box = boxes[boxNum]
      if not box then
        box = freshBox(boxes)
        boxes[boxNum] = box
      end
      if #box.content >= capacity then
        boxNum = boxNum + 1
        box = freshBox(boxes)
        boxes[boxNum] = box
      end
      table.insert(box.content, mon)
    end
    return boxes, true
  end

  local function validateBoxesOrphaned(orphaned)
    local changed = false
    if type(orphaned.mons) ~= "table" then orphaned.mons = {}; changed = true end
    if type(orphaned.moves) ~= "table" then orphaned.moves = {}; changed = true end
    for key, moves in pairs(orphaned.moves) do
      if type(moves) ~= "table" or #moves == 0 then orphaned.moves[key] = nil; changed = true end
    end
    return changed
  end

  function Storage.normalizeBoxes(s)
    s.entries.boxes = compactBoxes(s.entries.boxes)
    validateBoxesOrphaned(s.orphaned.boxes)
  end

  local function num(v, default) return math.max(0, math.floor(tonumber(v) or default or 0)) end

  local function boxesFreshStats() return { species = {} } end

  local function onlyFields(v, fields)
    local out, changed = {}, type(v) ~= "table"
    v = type(v) == "table" and v or {}
    for k in pairs(v) do if fields[k] == nil then changed = true end end
    for k, rebuild in pairs(fields) do
      local value, fieldChanged = rebuild(v[k])
      out[k] = value
      if fieldChanged then changed = true end
    end
    return out, changed
  end

  local function cleanSpecies(species)
    local clean, changed = {}, type(species) ~= "table"
    for id, count in pairs(type(species) == "table" and species or {}) do
      if type(id) == "string" and num(count) > 0 then clean[id] = num(count) end
      if clean[id] ~= count then changed = true end
    end
    return clean, changed
  end

  local function wholeField(v) return num(v), num(v) ~= v end

  local function boxesNormalizeStats(v) return onlyFields(v, { species = cleanSpecies }) end

  local function movesFreshStats() return { taught = 0 } end

  local function movesNormalizeStats(v) return onlyFields(v, { taught = wholeField }) end

  local function emptyFreshStats() return {} end

  local function emptyNormalizeStats(v) return onlyFields(v, {}) end

  local function topSpecies(species)
    local bestId, bestCount = nil, 0
    for id, count in pairs(species) do
      if count > bestCount or (count == bestCount and bestId and id < bestId) then bestId, bestCount = id, count end
    end
    return bestId, bestCount
  end

  local boxesStats = {
    { label = "TOP", description = "Most deposited.", value = function(game, v)
      local id, count = topSpecies(v.species)
      if not id then return nil end
      local def = game and game.data and game.data.pokemon and game.data.pokemon[id]
      return tostring(count), "TOP " .. ((def and def.name) or id)
    end },
  }

  local movesStats = {
    { label = "TAUGHT", description = "Moves taught.", value = function(_, v) return tostring(v.taught) end },
  }

  local migrateStorage = function(s)
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
    if currentVersion < 7 then
      s.entries = {
        boxes = s.boxes,
        items = s.items,
        moves = s.moves,
        money = s.money,
        timeCapsule = s.timeCapsule,
      }
      s.boxes, s.items, s.moves, s.money, s.timeCapsule = nil, nil, nil, nil, nil
      if s.orphaned then
        s.orphaned.boxes = { mons = s.orphaned.mons, moves = s.orphaned.monMoves }
        s.orphaned.mons = nil
        s.orphaned.monMoves = nil
      end
      if mod.save:get(CURRENT_BOX_KEY) == nil then mod.save:set(CURRENT_BOX_KEY, tonumber(s.currentBox) or 1) end
      s.currentBox = nil
    end
    s.version = STORAGE_VERSION
    return true
  end

  Storage.hooks = {}
  local function hook(name)
    return function(...)
      local fn = Storage.hooks[name]
      if fn then return fn(...) end
    end
  end

  local function validateWith(name, shapeOnly)
    return function(value, orphaned, game)
      if game then
        local result = Storage.hooks[name] and Storage.hooks[name](game) or {}
        return result.changed, result
      end
      return shapeOnly(value, orphaned)
    end
  end

  Storage.containers = { boxes = {}, items = {}, moves = {} }

  local function tabRow(key) return { screen = Storage.containers[key] or hook(key .. ".screen"), menuScreen = hook(key .. ".menuScreen") } end

  local function withTab(key, config)
    for k, v in pairs(tabRow(key)) do config[k] = v end
    return config
  end

  local ok, err = CustomStorage.registerCustomStorage({
    id = mod.id,
    name = "Pokémon Bank",
    storageVersion = STORAGE_VERSION,
    statsVersion = 2,
    migrate = migrateStorage,
    menu = "entries",
    entries = {
      CustomStorage.MultiArray.entry(withTab("boxes", {
        key = "boxes", label = "POKéMON", shortLabel = "BOX",
        description = "Store POKéMON in the\nBANK or take them out.",
        getContainers = function() return Storage.loadStorage().entries.boxes end,
        normalize = function(value)
          local boxes = type(value) == "table" and value or {}
          local reflowed, changed = reflowBoxes(boxes)
          return compactBoxes(reflowed), changed
        end,
        validate = validateWith("boxes.validate", function(_, orphaned) return validateBoxesOrphaned(orphaned) end),
        orphanList = function(bucket) return bucket.mons end,
        freshStats = boxesFreshStats,
        normalizeStats = boxesNormalizeStats,
        stats = boxesStats,
        linkWithdraw = hook("boxes.withdraw"),
        linkDeposit = hook("boxes.deposit"),
        link = {
          pokemon = true, isValid = hook("pokemon.isValid"), prepare = hook("pokemon.prepare"),
          poolLabel = hook("boxes.poolLabel"), currentPool = hook("boxes.currentPool"),
        },
        isUnlocked = Progress.gotPokedex,
      })),
      CustomStorage.Array.entry(withTab("timeCapsule", {
        key = "timeCapsule", label = "TIME CAPSULE", shortLabel = "CAPS",
        description = "Send POKéMON forward\nacross generations.",
        getStore = function() return Storage.loadStorage().entries.timeCapsule end,
        validate = validateWith("timeCapsule.validate", CustomStorage.Array.validate),
        linkEnabled = false,
        link = { pokemon = true },
        isUnlocked = Progress.gotPokedex,
      })),
      CustomStorage.Map.entry(withTab("items", {
        key = "items", label = "ITEMS", shortLabel = "ITEM",
        description = "Store items in the\nBANK or take them out.",
        getStore = function() return Storage.loadStorage().entries.items end,
        validate = validateWith("items.validate", CustomStorage.Map.validate),
        freshStats = emptyFreshStats,
        normalizeStats = emptyNormalizeStats,
        link = { isValid = hook("items.isValid"), nameOf = hook("items.nameOf"), footer = hook("items.footer") },
      })),
      CustomStorage.Map.entry(withTab("moves", {
        key = "moves", label = "MOVES", shortLabel = "MOVE",
        description = "Store moves in the\nBANK or take them out.",
        getStore = function() return Storage.loadStorage().entries.moves end,
        validate = validateWith("moves.validate", CustomStorage.Map.validate),
        freshStats = movesFreshStats,
        normalizeStats = movesNormalizeStats,
        stats = movesStats,
        link = { isValid = hook("moves.isValid"), nameOf = hook("moves.nameOf"), footer = hook("moves.footer") },
      })),
      CustomStorage.Single.entry(withTab("money", {
        key = "money", label = "MONEY",
        description = "Store money in the\nBANK or take it out.",
        freshStats = emptyFreshStats,
        normalizeStats = emptyNormalizeStats,
        linkEnabled = true,
        link = { prefix = "¥" },
      })),
      CustomStorage.Single.entry(withTab("coins", {
        key = "coins", label = "COINS", shortLabel = "COIN",
        description = "Store casino coins in\nthe BANK or take them\nout.",
        freshStats = emptyFreshStats,
        normalizeStats = emptyNormalizeStats,
        linkEnabled = true,
        isUnlocked = Progress.gotCoinCase,
      })),
    },
  })
  if not ok then error(("vrm_pokemon_bank: could not register its own CustomStorage: %s"):format(tostring(err)), 0) end

  local record = CustomStorage.getCustomStorage(mod.id)
  local storage = record.file

  Storage.markDirty = storage.markDirty
  Storage.loadStorage = storage.loadFile
  Storage.flushStorage = storage.flushFile

  function Storage.listBoxes()
    local out = {}
    for index, box in ipairs(storage.loadFile().entries.boxes or {}) do
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

  function Storage.currentBox()
    local s = storage.loadFile()
    local saved = tonumber(mod.save:get(CURRENT_BOX_KEY, 1)) or 1
    return math.max(1, math.min(#s.entries.boxes, math.floor(saved)))
  end

  function Storage.setCurrentBox(n)
    local s = storage.loadFile()
    mod.save:set(CURRENT_BOX_KEY, math.max(1, math.min(#s.entries.boxes, math.floor(tonumber(n) or 1))))
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
    if GameVersion.generation() == 3 then return BoxAccess.nativeName(game, i) end
    local name = Storage.pcBoxNamesTable()[i]
    if type(name) == "string" and name ~= "" then return name end
    if game and game.save and GameVersion.generation() == 2 then
      local Gen2Boxes = require("src.core.gen2.Boxes")
      local native = Gen2Boxes.name(game.save, i)
      if native ~= Gen2Boxes.defaultName(i) then return native end
    end
    return nil
  end

  function Storage.pcBoxLabel(game, i) return Storage.pcBoxName(game, i) or Strings("BOX %d", i) end

  function Storage.boxLabel(s, i)
    local box = s.entries.boxes and s.entries.boxes[i]
    local name = box and box.name
    if type(name) == "string" and name ~= "" then return name end
    return Strings("BOX %d", i)
  end

  function Storage.reapplyBoxPolicy()
    local s = storage.loadFile()
    s.entries.boxes = reflowBoxes(s.entries.boxes)
    Storage.normalizeBoxes(s)
    storage.markDirty()
  end

  function Storage.setBoxSizeOverride(value)
    local newOverride
    if value == nil then newOverride = nil
    elseif value == math.huge then newOverride = math.huge
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
