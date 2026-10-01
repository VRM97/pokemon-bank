local V = ...

local SCREEN_ID = "PokemonBankItems"

local Bag = V.require("BagAccess")
local PcItems = V.require("PcItemAccess")
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")
local ChoiceBox = V.require("Widgets").ChoiceBox

local Module = {}

function Module.install(mod, core)
  local GenerationMap = V.require("GenerationMap")
  local loadStorage = core.loadStorage
  local itemName = core.itemName

  local Items = { screenId = SCREEN_ID }

  local function startsWith(text, prefix) return type(text) == "string" and text:find("^" .. prefix) ~= nil end

  local function isHM(id) return startsWith(id, "HM_") or startsWith(id, "HM%d") end

  local function isTM(id) return startsWith(id, "TM_") or startsWith(id, "TM%d") end

  local tmItemDepositOverride = nil

  local function blockTmDeposit(id)
    if not isTM(id) then return false end
    if tmItemDepositOverride ~= nil then return not tmItemDepositOverride end
    return not core.isMovesTabEnabled or core.isMovesTabEnabled()
  end

  local function isKeyItem(def)
    if def == nil then return false end
    return def.keyItem == true or def.pocket == "KEY_ITEM" or def.pocket == "KEY_ITEMS" or def.fieldUse == "key" or (tonumber(def.importance) or 0) > 0
  end

  local extraBlacklist = {}

  local function isBlacklisted(id, def)
    if extraBlacklist[id] or isHM(id) or isKeyItem(def) then return true end
    return false
  end

  local function depositItem(id, qty, def)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    if blockTmDeposit(id) then return false, "is_tm" end
    if isBlacklisted(id, def) then return false, "blacklisted" end
    core.bucketAdd(loadStorage().entries.items, id, qty)
    core.markDirty()
    return true
  end

  local function withdrawItem(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if not core.bucketSub(loadStorage().entries.items, id, qty) then return false, "not enough" end
    core.markDirty()
    return true
  end

  local function listItems()
    local out = {}
    for id, count in pairs(loadStorage().entries.items) do out[id] = count end
    return out
  end

  local function isValidItem(id, data) return type(id) == "string" and id ~= "" and type(data) == "table" and type(data.items) == "table" and data.items[id] ~= nil end

  local function normalizeItemKeys(bucket, data)
    local renames
    for id, qty in pairs(bucket) do
      if qty and qty > 0 and not data.items[id] then
        local translated = GenerationMap.translateItemId(id)
        if translated ~= id and data.items[translated] then
          renames = renames or {}
          renames[#renames + 1] = { from = id, to = translated }
        end
      end
    end
    if not renames then return end
    for _, r in ipairs(renames) do
      bucket[r.to] = (bucket[r.to] or 0) + (bucket[r.from] or 0)
      bucket[r.from] = nil
    end
  end

  function Items.validateStorage(game)
    local data = game and game.data
    if not data then return { changed = false, quarantined = 0, restored = 0, lostItems = {}, restoredItems = {} } end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    if type(data.items) == "table" then
      normalizeItemKeys(s.entries.items, data)
      normalizeItemKeys(orphaned.items, data)
    end
    local function isValid(id) return isValidItem(id, data) and not isBlacklisted(id, data.items[id]) end
    local result = core.reconcileCountBucket(s.entries.items, orphaned.items, isValid, "POKéMON BANK")
    result.changed = result.quarantined > 0 or result.restored > 0
    return result
  end

  local function listInvalidItems() return core.listOrphaned("items") end

  local function invalidItemCount(id) return core.orphanedCount("items", id) end

  local ITEM_POCKETS = {
    { id = "ITEM", label = "ITEMS" },
    { id = "BALL", label = "BALLS" },
    { id = "KEY_ITEM", label = "KEY ITEMS" },
    { id = "TM_HM", label = "TM/HM" },
    -- FRLG
    { id = "ITEMS", label = "ITEMS" },
    { id = "POKE_BALLS", label = "BALLS" },
    { id = "KEY_ITEMS", label = "KEY ITEMS" },
    { id = "TM_CASE", label = "TM/HM" },
    { id = "BERRY_POUCH", label = "BERRIES" },
  }

  function Items.pocketOf(game, id) return Bag.pocketOf(id, game.data) end

  function Items.pocketLabel(pocket)
    if pocket == "ALL" then return "ALL" end
    for _, entry in ipairs(ITEM_POCKETS) do
      if entry.id == pocket then return entry.label end
    end
    return pocket
  end

  function Items.itemDescriptionText(game, id)
    local def = game.data.items[id]
    local description = def and def.description
    if not description then return nil end
    local first, second = description:match("^(.-)<NEXT>(.*)$")
    if not first then first, second = description:match("^(.-)\n(.*)$") end
    if not first then return description end
    if second and second ~= "" then return first .. "\n" .. second end
    return first
  end

  local function itemRow(game, id, count) return { value = id, label = core.truncateName(itemName(game, id)), right = "x" .. tostring(count) } end

  local pcStore = PcItems.counts

  local function bankIds(game) return core.sortedItemIds(game, loadStorage().entries.items) end
  local function pcIds(game) return core.sortedItemIds(game, pcStore(game)) end
  local function bagIds(game)
    local inv = Bag.counts(game)
    local out = {}
    for _, id in ipairs(Bag.order(game.save)) do if inv[id] and inv[id] > 0 then out[#out + 1] = id end end
    return out
  end
  local storeIds = { bank = bankIds, bag = bagIds, pc = pcIds }
  local storeOf = {
    bank = function() return loadStorage().entries.items end,
    bag = function(game) return Bag.counts(game) end,
    pc = pcStore,
  }

  local function pocketFilter(game, ids, pageId)
    if core.isAllPage(pageId) then return ids end
    local out = {}
    for _, id in ipairs(ids) do if Items.pocketOf(game, id) == pageId then out[#out + 1] = id end end
    return out
  end

  local function pagesFor(game, ids)
    local present, pages = {}, {}
    for _, id in ipairs(ids) do
      local p = Items.pocketOf(game, id)
      if p then present[p] = true end
    end
    for _, entry in ipairs(ITEM_POCKETS) do
      if present[entry.id] then pages[#pages + 1] = { id = entry.id, label = entry.label } end
    end
    return pages
  end

  local function successMsg(game, destView, id)
    local name = itemName(game, id)
    if destView == "bank" then return Strings("%s was\nstored in BANK.", name)
    elseif destView == "pc" then return Strings("%s was\nstored via PC.", name)
    else return Strings("Withdrew\n%s.", name) end
  end

  local function bankDepositBlockReason(game, id)
    if blockTmDeposit(id) then return "TMs go through\nthe MOVES tab!" end
    if isBlacklisted(id, game.data.items[id]) then return "That can't be\nstored in BANK!" end
    return nil
  end

  local function moveItem(game, srcView, destView, id, qty, playSound)
    if destView == "bag" then
      if not Bag.add(game.save, id, qty, game.data) then return false, "You can't carry\nany more items." end
    elseif destView == "bank" then
      local reason = bankDepositBlockReason(game, id)
      if reason then return false, reason end
    elseif destView == "pc" then
      if PcItems.full(game, id, qty) then return false, "No room left to\nstore items." end
    end
    if srcView == "bag" then Bag.remove(game.save, id, qty)
    elseif srcView == "bank" then withdrawItem(id, qty)
    elseif srcView == "pc" then PcItems.remove(game, id, qty)
    end
    if destView == "bank" then depositItem(id, qty, game.data.items[id])
    elseif destView == "pc" then PcItems.add(game, id, qty)
    end
    if destView == "bank" then core.emitAction("items", "deposit", "item_deposited", { id = id, qty = qty }) end
    if srcView == "bank" then core.emitAction("items", "withdraw", "item_withdrawn", { id = id, qty = qty }) end
    if playSound ~= false then core.playSound(game, "Withdraw_Deposit") end
    return true, successMsg(game, destView, id)
  end

  function Items.storeHeldItem(game, destView, id, playSound) return moveItem(game, nil, destView, id, 1, playSound) end

  local function startMove(game, srcView, destView, id, rebuild, list, env)
    local count = storeOf[srcView](game)[id]
    if not count then
      list.footer = "The selection changed."
      return
    end
    if destView == "bank" then
      local reason = bankDepositBlockReason(game, id)
      if reason then
        list.footer = reason
        return
      end
    end
    core.askQuantity(game, list, count, function(qty)
      local _, msg = moveItem(game, srcView, destView, id, qty)
      rebuild(true)
      core.currentList(env, list).footer = msg
    end)
  end

  local function startToss(game, view, id, rebuild, list, env)
    local count = storeOf[view](game)[id]
    if not count then
      list.footer = "The selection changed."
      return
    end
    if view ~= "bank" then
      local def = game.data.items[id]
      if isKeyItem(def) or isHM(id) then
        list.footer = "That's too impor-\ntant to toss!"
        return
      end
    end
    core.confirmTossQuantity(game, list, {
      liveList = function() return core.currentList(env, list) end,
      count = count,
      name = itemName(game, id),
      choice = function(prompt, onYes)
        list.footer = prompt
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then
            list.footer = nil
            return
          end
          onYes()
        end, { noSound = true }))
      end,
      onToss = function(qty)
        if view == "bank" then
          withdrawItem(id, qty)
          core.emitAction("items", "remove", "item_tossed", { id = id, qty = qty })
        elseif view == "bag" then Bag.remove(game.save, id, qty)
        else PcItems.remove(game, id, qty)
        end
      end,
      rebuild = function() rebuild(true) end,
    })
  end

  local function transferGroup(view, otherViews)
    local targets = {}
    for _, other in ipairs(otherViews) do
      targets[#targets + 1] = { label = "TO " .. other.label, onSelect = function(game, _, id, rebuild, list, env) startMove(game, view, other.id, id, rebuild, list, env) end }
    end
    return core.transferGroup(targets)
  end

  local function tossRow(view) return { label = "TOSS", onSelect = function(game, _, id, rebuild, list, env) startToss(game, view, id, rebuild, list, env) end } end

  local itemView = core.gridView("item_view", { columns = 6, default = "list", available = function() return GameVersion.generation() == 3 end })

  local function itemIcon(id)
    local ok, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
    if not (ok and BagChrome and BagChrome.iconImage) then return nil end
    return BagChrome.iconImage(Bag.itemNumber(id) or id)
  end

  local function makeContainer(view, label, otherViews, ordered)
    return {
      id = view, label = label,
      getPages = function(game) return pagesFor(game, storeIds[view](game)) end,
      includeAllPage = true,
      title = function(_, pageId)
        if core.isAllPage(pageId) then return label end
        return Strings("%s (%s)", label, Items.pocketLabel(pageId))
      end,
      build = function(game, pageId)
        local ids = pocketFilter(game, storeIds[view](game), pageId)
        local store = storeOf[view](game)
        local rows = {}
        for i, id in ipairs(ids) do rows[i] = itemRow(game, id, store[id]) end
        return rows, { messageBox = true, noSound = true, wrap = true }
      end,
      columns = itemView.columns,
      icon = function(_, _, id) return itemIcon(id) end,
      onStart = itemView.rows,
      canRearrange = ordered and function(_, pageId) return not core.isAllPage(pageId) end or nil,
      onMove = ordered and function(game, fromPageId, fromIndex, _, toIndex)
        local ids = pocketFilter(game, storeIds[view](game), fromPageId)
        local id = ids[fromIndex]
        if not id then return end
        if Bag.move(game.save, id, fromPageId, toIndex, game.data) then core.playSound(game, "Swap") end
      end or nil,
      dynamicFooter = function(game, _, row, nextLabel)
        if itemView.isGrid() then
          local count = row and storeOf[view](game)[row]
          local line = row and Strings("%s x%d", itemName(game, row), count or 0) or ""
          return line .. "\nSELECT: " .. nextLabel
        end
        local detail = row and Items.itemDescriptionText(game, row)
        return detail or ("\nSELECT: " .. nextLabel)
      end,
      canTransfer = true,
      canListPages = true,
      listPagesLabel = "POCKETS",
      canWithdraw = false,
      withdraw = function(game, _, id, destView)
        local count = storeOf[view](game)[id]
        return count and count > 0 and (moveItem(game, view, destView, id, count, false)) or false
      end,
      deposit = function() end,
      onAction = (function()
        local rows = {}
        rows[#rows + 1] = transferGroup(view, otherViews)
        rows[#rows + 1] = tossRow(view)
        return rows
      end)(),
    }
  end

  local BANK = { id = "bank", label = "BANK" }
  local BAG = { id = "bag", label = "BAG" }
  local PC = { id = "pc", label = "PC" }
  Items.containers = {
    makeContainer("bank", "BANK", { BAG, PC }, false),
    makeContainer("bag", "BAG", { BANK, PC }, true),
    makeContainer("pc", "PC", { BANK, BAG }, false),
  }

  local function BankItemMenu(game) return core.entryScreen(game, Items.containers, { screenId = SCREEN_ID, counter = true }) end

  mod.content.screens:register(SCREEN_ID, { new = BankItemMenu })

  local itemsTab = core.entryTab("items", "show_items_tab")
  Items.tabEnabled = itemsTab.shown

  mod.exports.depositItem = function(id, qty, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    local ok, err = depositItem(id, qty, def)
    if ok then core.emitAction("items", "deposit", "item_deposited", { id = id, qty = qty }) end
    return ok, err
  end

  mod.exports.withdrawItem = core.emitOnSuccess(withdrawItem, "items", "withdraw", "item_withdrawn", core.idQtyPayload)
  mod.exports.tossItem = core.emitOnSuccess(withdrawItem, "items", "remove", "item_tossed", core.idQtyPayload)
  mod.exports.listItems = listItems

  mod.exports.isValidItem = function(id, game) return isValidItem(id, game and game.data) end
  mod.exports.validateItemsStorage = Items.validateStorage
  mod.exports.listInvalidItems = listInvalidItems
  mod.exports.invalidItemCount = invalidItemCount

  mod.exports.isBlacklisted = function(id, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    return isBlacklisted(id, def)
  end

  mod.exports.blacklistItem = function(id)
    if type(id) ~= "string" or id == "" then return false end
    extraBlacklist[id] = true
    return true
  end

  function Items.setTmItemDepositAllowed(value)
    if value == nil then tmItemDepositOverride = nil
    else tmItemDepositOverride = value ~= false end
    return true
  end

  function Items.getTmItemDepositOverride() return tmItemDepositOverride end

  mod.exports.setTmItemDepositAllowed = Items.setTmItemDepositAllowed
  mod.exports.isTmItemDepositAllowed = function() return not blockTmDeposit("TM_") end
  mod.exports.getTmItemDepositOverride = Items.getTmItemDepositOverride
  mod.exports.itemsScreenId = SCREEN_ID
  mod.exports.setItemsTabEnabled = itemsTab.setEnabled
  mod.exports.isItemsTabEnabled = Items.tabEnabled
  mod.log:info("Pokemon Bank: Items tab ready")
  return Items
end

return Module
