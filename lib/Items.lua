local V = ...

local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local QuantityBox = require("src.ui.QuantityBox")

local SCREEN_ID = "PokemonBankItems"

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty

  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  local function playSound(game, name)
    pcall(function() require("src.core.Sound").play(game.data, name) end)
  end

  -- HMs and key items can never enter the Bank -- a hard rule, not a preference. See API.md's blacklistItem entry for extraBlacklist's own rules.
  local extraBlacklist = {}

  local function isHM(id)
    return type(id) == "string" and id:find("^HM_") ~= nil
  end

  local function isBlacklisted(id, def)
    if extraBlacklist[id] then return true end
    if isHM(id) then return true end
    if def and def.keyItem then return true end
    return false
  end

  -- ---------------------------------------------------------------------
  -- Item storage: a flat { id = count } table, no manual ordering to maintain -- the UI below always lists it sorted by display name.
  -- ---------------------------------------------------------------------
  local function itemCount(id)
    return loadStorage().items[id] or 0
  end

  local function depositItem(id, qty, def)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    if isBlacklisted(id, def) then return false, "blacklisted" end
    local s = loadStorage()
    s.items[id] = (s.items[id] or 0) + qty
    markDirty()
    return true
  end

  local function withdrawItem(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    local s = loadStorage()
    local have = s.items[id] or 0
    if qty <= 0 or qty > have then return false, "not enough" end
    s.items[id] = have - qty
    if s.items[id] <= 0 then s.items[id] = nil end
    markDirty()
    return true
  end

  local function listItems()
    local out = {}
    for id, count in pairs(loadStorage().items) do out[id] = count end
    return out
  end

  local function isValidItem(id, data)
    return type(id) == "string" and id ~= ""
      and type(data) == "table"
      and type(data.items) == "table"
      and data.items[id] ~= nil
  end

  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0 }
    end
    local s = loadStorage()
    s.invalidItems = type(s.invalidItems) == "table" and s.invalidItems or {}
    local quarantined, restored = 0, 0

    local badIds = {}
    for id, count in pairs(s.items) do
      if not isValidItem(id, data) then badIds[#badIds + 1] = id end
    end
    for _, id in ipairs(badIds) do
      local qty = s.items[id] or 0
      if qty > 0 then
        s.items[id] = nil
        s.invalidItems[id] = (s.invalidItems[id] or 0) + qty
        quarantined = quarantined + qty
      end
    end

    local goodIds = {}
    for id, count in pairs(s.invalidItems) do
      if isValidItem(id, data) then goodIds[#goodIds + 1] = id end
    end
    for _, id in ipairs(goodIds) do
      local qty = s.invalidItems[id] or 0
      if qty > 0 then
        s.invalidItems[id] = nil
        s.items[id] = (s.items[id] or 0) + qty
        restored = restored + qty
      end
    end

    return {
      changed = quarantined > 0 or restored > 0,
      quarantined = quarantined,
      restored = restored,
    }
  end

  local function listInvalidItems()
    local out = {}
    for id, count in pairs(loadStorage().invalidItems) do out[id] = count end
    return out
  end

  local function invalidItemCount(id)
    if id ~= nil then return loadStorage().invalidItems[id] or 0 end
    local n = 0
    for _, count in pairs(loadStorage().invalidItems) do n = n + count end
    return n
  end

  -- =========================================================================
  -- Item UI
  -- =========================================================================
  local function itemName(game, id)
    local def = game.data.items[id]
    return def and def.name or id
  end

  local function sortedItemIds(game, counts)
    local ids = {}
    for id, count in pairs(counts) do
      if count and count > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return itemName(game, a) < itemName(game, b) end)
    return ids
  end

  local function bankItemRows(game)
    local s = loadStorage()
    local rows = {}
    for _, id in ipairs(sortedItemIds(game, s.items)) do
      rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(s.items[id]) }
    end
    return rows
  end

  local function bagItemRowsForBank(game)
    local inv = game.save.inventory
    local counts = {}
    for _, id in ipairs(Bag.order(game.save)) do counts[id] = inv[id] end
    local rows = {}
    for _, id in ipairs(sortedItemIds(game, counts)) do
      rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(inv[id]) }
    end
    return rows
  end

  -- Updates or drops `id`'s row after its count changed, keeping the list
  -- open and the cursor valid (vanilla PlayerPC's own refreshRow).
  local function refreshItemRow(list, count, id)
    for i, row in ipairs(list.items) do
      if row.value == id then
        if count and count > 0 then
          row.right = "x" .. tostring(count)
        else
          table.remove(list.items, i)
        end
        break
      end
    end
    list.index = math.max(1, math.min(list.index, #list.items))
  end

  local function askItemQuantity(game, list, count, cb)
    list.footer = "How many?"
    game.stack:push(QuantityBox.new(game, {
      max = count,
      onDone = function(qty)
        if qty then cb(qty) else list.footer = nil end
      end,
    }))
  end

  local function openWithdrawItemsList(game)
    local list
    list = ListMenu.new(game, "WITHDRAW ITEM", bankItemRows(game), {
      messageBox = true, noSound = true,
      onChoose = function(item)
        local count = itemCount(item.value)
        if count <= 0 then
          list.footer = "The selection changed."
          return
        end
        askItemQuantity(game, list, count, function(qty)
          if not Bag.add(game.save, item.value, qty, game.data) then
            list.footer = "You can't carry\nany more items."
            return
          end
          withdrawItem(item.value, qty)
          mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = item.value, qty = qty })
          refreshItemRow(list, itemCount(item.value), item.value)
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("Withdrew\n%s.", itemName(game, item.value))
        end)
      end,
    })
    game.stack:push(list)
  end

  local function openDepositItemsList(game)
    local list
    list = ListMenu.new(game, "DEPOSIT ITEM", bagItemRowsForBank(game), {
      messageBox = true, noSound = true,
      onChoose = function(item)
        local def = game.data.items[item.value]
        if isBlacklisted(item.value, def) then
          list.footer = "That can't be\nstored in BANK!"
          return
        end
        local count = game.save.inventory[item.value]
        if not count then
          list.footer = "The selection changed."
          return
        end
        askItemQuantity(game, list, count, function(qty)
          Bag.remove(game.save, item.value, qty)
          depositItem(item.value, qty, def)
          mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = item.value, qty = qty })
          refreshItemRow(list, game.save.inventory[item.value], item.value)
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("%s was\nstored in BANK.", itemName(game, item.value))
        end)
      end,
    })
    game.stack:push(list)
  end

  -- WITHDRAW ITEM / DEPOSIT ITEM / CANCEL -- vanilla also has TOSS ITEM, but tossing isn't the Bank's job (the real Bag/PC already do it); keepOpen so each list leaves this menu underneath it.
  local function BankItemMenu(game)
    local rows = {
      { label = "WITHDRAW ITEM", keepOpen = true, onSelect = function() openWithdrawItemsList(game) end },
      { label = "DEPOSIT ITEM", keepOpen = true, onSelect = function() openDepositItemsList(game) end },
      { label = "CANCEL" },
    }
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankItemMenu })

  -- Tab visibility: ITEMS MENU option AND setItemsTabEnabled override.
  local tabEnabledByOthers = true

  local function tabEnabled()
    return tabEnabledByOthers and mod.options:get("show_items_tab") == true
  end

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.depositItem = function(id, qty, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    local ok, err = depositItem(id, qty, def)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = id, qty = qty })
    end
    return ok, err
  end

  mod.exports.withdrawItem = function(id, qty)
    local ok, err = withdrawItem(id, qty)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = id, qty = qty })
    end
    return ok, err
  end

  mod.exports.itemCount = function(id) return itemCount(id) end
  mod.exports.listItems = function() return listItems() end

  mod.exports.isValidItem = function(id, game)
    return isValidItem(id, game and game.data)
  end
  mod.exports.validateItemsStorage = function(game) return validateStorage(game) end
  mod.exports.listInvalidItems = function() return listInvalidItems() end
  mod.exports.invalidItemCount = function(id) return invalidItemCount(id) end

  mod.exports.isBlacklisted = function(id, game)
    local def = game and game.data and game.data.items and game.data.items[id]
    return isBlacklisted(id, def)
  end

  mod.exports.blacklistItem = function(id)
    if type(id) ~= "string" or id == "" then return false end
    extraBlacklist[id] = true
    return true
  end

  mod.exports.itemsScreenId = SCREEN_ID

  mod.exports.setItemsTabEnabled = function(enabled)
    tabEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.isItemsTabEnabled = function() return tabEnabled() end

  mod.log:info("Pokemon Bank: Items tab ready")

  return {
    screenId = SCREEN_ID,
    tabEnabled = tabEnabled,
    validateStorage = validateStorage,
  }
end

return Module
