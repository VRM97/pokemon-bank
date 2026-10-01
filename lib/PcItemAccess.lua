local V = ...

local GameVersion = require("src.core.GameVersion")
local BagAccess = V.require("BagAccess")

local PcItemAccess = {}

local DEFAULT_CAP = 50

local function gen3Storage()
  local okRuntime, runtime = pcall(require, "src.core.game3.runtime")
  local session = okRuntime and runtime and runtime.getSession and runtime.getSession()
  local okStorage, Storage = pcall(require, "src.core.game3.storage")
  if not (session and okStorage and type(Storage) == "table") then return nil end
  return session, Storage, Storage.ensure(session)
end

local function gen3Entry(storage, number)
  for i, entry in ipairs(storage.items) do
    if entry.id == number then return entry, i end
  end
end

local function legacyStore(game)
  game.save.pcItems = game.save.pcItems or {}
  return game.save.pcItems
end

function PcItemAccess.counts(game)
  if GameVersion.generation() ~= 3 then return legacyStore(game) end
  local out = {}
  local _, _, storage = gen3Storage()
  for _, entry in ipairs(storage and storage.items or {}) do
    local name, qty = BagAccess.itemName(entry.id), tonumber(entry.qty) or 0
    if name and qty > 0 then out[name] = (out[name] or 0) + qty end
  end
  return out
end

function PcItemAccess.full(game, id, qty)
  if GameVersion.generation() ~= 3 then
    local pc = legacyStore(game)
    if pc[id] then return false end
    local stacks = 0
    for _ in pairs(pc) do stacks = stacks + 1 end
    return stacks >= ((game.data.field and game.data.field.pcItemCap) or DEFAULT_CAP)
  end
  local _, Storage, storage = gen3Storage()
  local number = BagAccess.itemNumber(id)
  if not (storage and number) then return true end
  local entry = gen3Entry(storage, number)
  if entry then return (tonumber(entry.qty) or 0) + (qty or 1) > (Storage.MAX_ITEM_QTY or 999) end
  return #storage.items >= (Storage.PC_ITEMS_COUNT or DEFAULT_CAP)
end

function PcItemAccess.add(game, id, qty)
  if GameVersion.generation() ~= 3 then
    local pc = legacyStore(game)
    pc[id] = (pc[id] or 0) + qty
    return true
  end
  local session, Storage = gen3Storage()
  local number = BagAccess.itemNumber(id)
  if not (Storage and number and type(Storage.addPcItem) == "function") then return false end
  return (Storage.addPcItem(session, number, qty)) == true
end

function PcItemAccess.remove(game, id, qty)
  if GameVersion.generation() ~= 3 then
    local pc = legacyStore(game)
    local have = pc[id] or 0
    if qty <= 0 or qty > have then return false end
    pc[id] = have - qty
    if pc[id] <= 0 then pc[id] = nil end
    return true
  end
  local _, _, storage = gen3Storage()
  local number = BagAccess.itemNumber(id)
  if not (storage and number) then return false end
  local entry, index = gen3Entry(storage, number)
  local have = entry and tonumber(entry.qty) or 0
  if qty <= 0 or qty > have then return false end
  entry.qty = have - qty
  if entry.qty <= 0 then table.remove(storage.items, index) end
  return true
end

return PcItemAccess
