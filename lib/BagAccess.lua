local GameVersion = require("src.core.GameVersion")

local GEN_3_POCKETS = { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }

local BagAccess = {}

local function gen3Bag()
  local ok, runtime = pcall(require, "src.core.game3.runtime")
  if not ok then return nil end
  local session = runtime and runtime.getSession and runtime.getSession()
  local bag = session and session.bag
  local _, Bag = pcall(require, "src.core.game3.bag")
  if bag and Bag then return bag, Bag end
  return nil
end

local function nameOf(number)
  local ok, Compat = pcall(require, "src.mods.Gen3Compat")
  local name = ok and Compat and Compat.itemName and Compat.itemName(number)
  return type(name) == "string" and name or nil
end

local function numberOf(id)
  local ok, Compat = pcall(require, "src.mods.Gen3Compat")
  return ok and Compat and Compat.itemId and Compat.itemId(id) or nil
end

local function slotsOf(bag, pocket) return bag.pockets and bag.pockets[pocket] or {} end

BagAccess.itemName = nameOf
BagAccess.itemNumber = numberOf

local function heldField() return GameVersion.generation() == 2 and "item" or "heldItem" end

function BagAccess.heldItemName(mon)
  if type(mon) ~= "table" then return nil end
  local value = mon.item or mon.heldItem
  if value == nil or value == 0 or value == "" then return nil end
  if type(value) == "string" then return value end
  if type(mon.heldItemAlt) == "string" then return mon.heldItemAlt end
  return nameOf(value)
end

function BagAccess.reshapeHeldItem(mon)
  if type(mon) ~= "table" then return end
  local value, name = mon.item or mon.heldItem, BagAccess.heldItemName(mon)
  mon.item, mon.heldItem = nil, nil
  if value == nil or value == 0 or value == "" then mon.heldItemAlt = nil return end
  name = name or value
  local number = type(value) == "number" and value or (type(mon.heldItemAlt) == "number" and mon.heldItemAlt)
  if GameVersion.generation() == 3 then number = number or numberOf(name) end
  if GameVersion.generation() == 3 and number then mon[heldField()], mon.heldItemAlt = number, type(name) == "string" and name or nil
  else mon[heldField()], mon.heldItemAlt = name, number or nil end
end

function BagAccess.setHeldItem(mon, name)
  mon.item, mon.heldItem, mon.heldItemAlt = nil, nil, nil
  if name == nil then return end
  mon[heldField()] = name
  BagAccess.reshapeHeldItem(mon)
end

local function isMachineId(id) return type(id) == "string" and (id:find("^TM_") or id:find("^HM_")) ~= nil end

local function isBall(id)
  local ok, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  return ok and type(ItemEffects.isBall) == "function" and ItemEffects.isBall(id) == true
end

function BagAccess.pocketOf(id, data)
  local def = data and data.items and data.items[id]
  if def == nil then return nil end
  if def.pocket or GameVersion.generation() ~= 1 then return def.pocket end
  if def.machine or isMachineId(id) then return "TM_HM" end
  if def.keyItem then return "KEY_ITEM" end
  if def.ball or isBall(id) then return "BALL" end
  return "ITEM"
end

local function moveInPocket(save, id, pocket, toIndex, data)
  local order = require("src.inventory.Bag").order(save, data)
  local slots, ids, from = {}, {}, nil
  for i, oid in ipairs(order) do
    if BagAccess.pocketOf(oid, data) == pocket then
      slots[#slots + 1], ids[#ids + 1] = i, oid
      if oid == id then from = #ids end
    end
  end
  if not from then return false end
  local to = math.max(1, math.min(math.floor(tonumber(toIndex) or from), #ids))
  if to == from then return false end
  table.insert(ids, to, table.remove(ids, from))
  for i, slot in ipairs(slots) do order[slot] = ids[i] end
  return true
end

function BagAccess.order(save, data)
  if GameVersion.generation() ~= 3 then return require("src.inventory.Bag").order(save, data) end
  local bag = gen3Bag()
  local out = {}
  if not bag then return out end
  for _, pocket in ipairs(GEN_3_POCKETS) do
    for _, slot in ipairs(slotsOf(bag, pocket)) do
      local name = (tonumber(slot.qty) or 0) > 0 and nameOf(slot.id)
      if name then out[#out + 1] = name end
    end
  end
  return out
end

function BagAccess.counts(game)
  if GameVersion.generation() ~= 3 then return game.save.inventory end
  local bag = gen3Bag()
  local out = {}
  if not bag then return out end
  for _, pocket in ipairs(GEN_3_POCKETS) do
    for _, slot in ipairs(slotsOf(bag, pocket)) do
      local name, qty = nameOf(slot.id), tonumber(slot.qty) or 0
      if name and qty > 0 then out[name] = (out[name] or 0) + qty end
    end
  end
  return out
end

function BagAccess.hasItem(game, id)
  if GameVersion.generation() ~= 3 then
    local inventory = game and game.save and game.save.inventory
    return type(inventory) == "table" and (tonumber(inventory[id]) or 0) > 0
  end
  local bag, Bag = gen3Bag()
  local number = type(id) == "number" and id or numberOf(id)
  if not (Bag and number) then return false end
  return Bag.has(bag, number) == true
end

function BagAccess.add(save, id, qty, data)
  if GameVersion.generation() ~= 3 then return require("src.inventory.Bag").add(save, id, qty, data) end
  local bag, Bag = gen3Bag()
  local number = numberOf(id)
  if not (Bag and number) then return false end
  return (Bag.add(bag, number, qty)) == true
end

function BagAccess.remove(save, id, qty)
  if GameVersion.generation() ~= 3 then return require("src.inventory.Bag").remove(save, id, qty) end
  local bag, Bag = gen3Bag()
  local number = numberOf(id)
  if not (Bag and number) then return false end
  return Bag.remove(bag, number, qty) == true
end

function BagAccess.move(save, id, pocket, toIndex, data)
  if GameVersion.generation() == 1 then return moveInPocket(save, id, pocket, toIndex, data or require("src.core.Data")) end
  if GameVersion.generation() ~= 3 then return require("src.inventory.Bag").move(save, id, pocket, toIndex, data) end
  local bag = gen3Bag()
  local number = numberOf(id)
  if not (bag and number) then return false end
  local slots = slotsOf(bag, pocket)
  local from
  for i, slot in ipairs(slots) do
    if slot.id == number then from = i break end
  end
  if not from then return false end
  local to = math.max(1, math.min(math.floor(tonumber(toIndex) or from), #slots))
  if to == from then return false end
  table.insert(slots, to, table.remove(slots, from))
  return true
end

return BagAccess
