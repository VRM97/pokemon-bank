local V = ...

local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local QuantityBox = require("src.ui.QuantityBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local Font = require("src.render.Font")

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

  local function ensureOrphaned(s)
    if not s.orphaned then
      s.orphaned = { mons = {}, items = {} }
    end
    s.orphaned.mons = s.orphaned.mons or {}
    s.orphaned.items = s.orphaned.items or {}
    return s.orphaned
  end

  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostItems = {}, restoredItems = {} }
    end
    local s = loadStorage()
    local orphaned = ensureOrphaned(s)
    local quarantined, restored = 0, 0
    local lostItems, restoredItems = {}, {}
    local badIds = {}
    for id, count in pairs(s.items) do
      if not isValidItem(id, data) then badIds[#badIds + 1] = id end
    end
    for _, id in ipairs(badIds) do
      local qty = s.items[id] or 0
      if qty > 0 then
        s.items[id] = nil
        orphaned.items[id] = (orphaned.items[id] or 0) + qty
        quarantined = quarantined + qty
        lostItems[#lostItems + 1] = { id = id, count = qty, from = "POKéMON BANK" }
      end
    end
    local goodIds = {}
    for id, count in pairs(orphaned.items) do
      if isValidItem(id, data) then goodIds[#goodIds + 1] = id end
    end
    for _, id in ipairs(goodIds) do
      local qty = orphaned.items[id] or 0
      if qty > 0 then
        orphaned.items[id] = nil
        s.items[id] = (s.items[id] or 0) + qty
        restored = restored + qty
        restoredItems[#restoredItems + 1] = { id = id, count = qty }
      end
    end
    return {
      changed = quarantined > 0 or restored > 0,
      quarantined = quarantined,
      restored = restored,
      lostItems = lostItems,
      restoredItems = restoredItems,
    }
  end

  local function listInvalidItems()
    local out = {}
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.items or {}
    for id, count in pairs(orphaned) do out[id] = count end
    return out
  end

  local function invalidItemCount(id)
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.items or {}
    if id ~= nil then return orphaned[id] or 0 end
    local n = 0
    for _, count in pairs(orphaned) do n = n + count end
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

  local function itemRows(game, items)
    local rows = {}
    for _, id in ipairs(sortedItemIds(game, items)) do
      rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(items[id]) }
    end
    return rows
  end

  local function bankItemRows(game)
    local s = loadStorage()
    return itemRows(game, s.items)
  end

  local function bagItemRowsForBank(game)
    local inv = game.save.inventory
    local counts = {}
    for _, id in ipairs(Bag.order(game.save)) do counts[id] = inv[id] end
    return itemRows(game, counts)
  end

  -- MOVE ITEM's own bag view, for its SWITCH option only: shows real Bag menu order.
  local function bagItemRowsOrdered(game)
    local inv = game.save.inventory
    local rows = {}
    for _, id in ipairs(Bag.order(game.save)) do
      if inv[id] and inv[id] > 0 then
        rows[#rows + 1] = { value = id, label = itemName(game, id), right = "x" .. tostring(inv[id]) }
      end
    end
    return rows
  end

  local function pcItemsRowsForBank(game)
    game.save.pcItems = game.save.pcItems or {}
    return itemRows(game, game.save.pcItems)
  end

  -- wNumBoxItems capacity (players_pc.asm): 50 distinct stacks, mirroring PlayerPC.lua's own pcFull -- growing an existing stack is always fine.
  local function pcItemFull(game, id)
    local pc = game.save.pcItems
    if pc[id] then return false end
    local cap = (game.data.field and game.data.field.pcItemCap) or 50
    local stacks = 0
    for _ in pairs(pc) do stacks = stacks + 1 end
    return stacks >= cap
  end

  -- Updates or drops `id`'s row after its count changed, keeping the list open and the cursor valid (vanilla PlayerPC's own refreshRow).
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

  -- WITHDRAW ITEM's own per-item flow, factored out so MOVE ITEM's bank-side view can reuse it verbatim instead of duplicating it.
  local function withdrawItemChoice(game, list, item)
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
  end

  -- DEPOSIT ITEM's own per-item flow, factored out so MOVE ITEM's bag-side view can reuse it verbatim instead of duplicating it.
  local function depositItemChoice(game, list, item)
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
  end

  local function openWithdrawItemsList(game)
    local list
    list = ListMenu.new(game, "WITHDRAW ITEM", bankItemRows(game), {
      messageBox = true, noSound = true,
      onChoose = function(item) withdrawItemChoice(game, list, item) end,
    })
    game.stack:push(list)
  end

  local function openDepositItemsList(game)
    local list
    list = ListMenu.new(game, "DEPOSIT ITEM", bagItemRowsForBank(game), {
      messageBox = true, noSound = true,
      onChoose = function(item) depositItemChoice(game, list, item) end,
    })
    game.stack:push(list)
  end

  -- MOVE ITEM: SELECT cycles BANK > BAG > PC. A opens TO <the other two>, SWITCH (BAG only -- reorders Bag.order; BANK and PC both always list alphabetically), TOSS and CANCEL.
  local function openMoveItemsList(game)
    game.save.pcItems = game.save.pcItems or {}
    local state = { view = "bank", pendingSwap = nil }
    local screen = { isOpaque = true }
    local list
    local rebuild, openItemActions, completeSwitch

    local function currentStore()
      if state.view == "bank" then return loadStorage().items
      elseif state.view == "bag" then return game.save.inventory
      else return game.save.pcItems end
    end

    local function currentRows()
      if state.view == "bank" then return bankItemRows(game)
      elseif state.view == "bag" then return bagItemRowsOrdered(game)
      else return pcItemsRowsForBank(game) end
    end

    local function viewTitle()
      if state.view == "bank" then return "BANK"
      elseif state.view == "bag" then return "BAG"
      else return "PC" end
    end

    -- BANK > BAG > PC > BANK, matching cycleView below -- what SELECT switches TO from the current view, for the footer hint.
    local function nextViewName()
      if state.view == "bank" then return "BAG"
      elseif state.view == "bag" then return "PC"
      else return "BANK" end
    end

    local function cycleView()
      if state.pendingSwap then return end
      if state.view == "bank" then state.view = "bag"
      elseif state.view == "bag" then state.view = "pc"
      else state.view = "bank" end
      rebuild()
    end

    local function successMsg(destView, id)
      local name = itemName(game, id)
      if destView == "bank" then return Strings("%s was\nstored in BANK.", name)
      elseif destView == "pc" then return Strings("%s was\nstored via PC.", name)
      else return Strings("Withdrew\n%s.", name) end
    end

    -- destination capacity/blacklist check, then move qty of id out of the current view and into destView.
    -- Only destView == "bank" or srcView == "bank" ever touches the Bank's own storage/events -- a BAG <-> PC move is entirely between two vanilla save structures.
    local function moveItem(destView, id, qty)
      local srcView = state.view
      local pc = game.save.pcItems

      if destView == "bag" then
        if not Bag.add(game.save, id, qty, game.data) then
          return false, "You can't carry\nany more items."
        end
      elseif destView == "bank" then
        if isBlacklisted(id, game.data.items[id]) then
          return false, "That can't be\nstored in BANK!"
        end
      elseif destView == "pc" then
        if pcItemFull(game, id) then
          return false, "No room left to\nstore items."
        end
      end

      if srcView == "bag" then
        Bag.remove(game.save, id, qty)
      elseif srcView == "bank" then
        withdrawItem(id, qty)
      elseif srcView == "pc" then
        pc[id] = pc[id] - qty
        if pc[id] <= 0 then pc[id] = nil end
      end

      if destView == "bank" then
        depositItem(id, qty, game.data.items[id])
      elseif destView == "pc" then
        pc[id] = (pc[id] or 0) + qty
      end

      if destView == "bank" then
        mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = id, qty = qty })
      elseif srcView == "bank" then
        mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = id, qty = qty })
      end
      playSound(game, "Withdraw_Deposit")
      return true, successMsg(destView, id)
    end

    local function startMove(destView, id)
      local count = currentStore()[id]
      if not count then
        list.footer = "The selection changed."
        return
      end
      askItemQuantity(game, list, count, function(qty)
        local _, msg = moveItem(destView, id, qty)
        rebuild()
        list.footer = msg
      end)
    end

    -- Tosses out of whichever storage is currently shown. The Bank can never hold an HM/key item (depositItem refuses them), but the Bag and the PC both can.
    -- Bag and PC get the same tossability guard their own vanilla TOSS uses before the quantity prompt even opens.
    local function startToss(id)
      local count = currentStore()[id]
      if not count then
        list.footer = "The selection changed."
        return
      end
      if state.view ~= "bank" then
        local def = game.data.items[id]
        if (def and def.keyItem) or isHM(id) then
          list.footer = "That's too impor-\ntant to toss!"
          return
        end
      end
      askItemQuantity(game, list, count, function(qty)
        list.footer = Strings("Toss %s?", itemName(game, id))
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then
            list.footer = nil
            return
          end
          if state.view == "bank" then
            withdrawItem(id, qty)
            mod.events:emit("mod.vrm_pokemon_bank.item_tossed", { id = id, qty = qty })
          elseif state.view == "bag" then
            Bag.remove(game.save, id, qty)
          else -- pc
            local pc = game.save.pcItems
            pc[id] = pc[id] - qty
            if pc[id] <= 0 then pc[id] = nil end
          end
          list.footer = Strings("Threw away\n%s.", itemName(game, id))
          rebuild()
        end, { noSound = true }))
      end)
    end

    completeSwitch = function(targetId)
      local pending = state.pendingSwap
      state.pendingSwap = nil
      if pending and pending.id ~= targetId then
        local order = Bag.order(game.save)
        local srcIdx, destIdx
        for i, id in ipairs(order) do
          if id == pending.id then srcIdx = i end
          if id == targetId then destIdx = i end
        end
        if srcIdx and destIdx then
          order[srcIdx], order[destIdx] = order[destIdx], order[srcIdx]
          playSound(game, "Swap")
        end
      end
      rebuild()
    end

    openItemActions = function(id)
      local view = state.view
      local rows = {}
      if view ~= "bank" then
        rows[#rows + 1] = { label = "TO BANK", onSelect = function() startMove("bank", id) end }
      end
      if view ~= "bag" then
        rows[#rows + 1] = { label = "TO BAG", onSelect = function() startMove("bag", id) end }
      end
      if view ~= "pc" then
        rows[#rows + 1] = { label = "TO PC", onSelect = function() startMove("pc", id) end }
      end
      if view == "bag" then
        rows[#rows + 1] = { label = "SWITCH", onSelect = function()
          state.pendingSwap = { id = id }
          rebuild()
        end }
      end
      rows[#rows + 1] = { label = "TOSS", onSelect = function() startToss(id) end }
      rows[#rows + 1] = { label = "CANCEL" }
      local th = #rows * 2 + 2
      game.stack:push(Menu.new(game, rows, { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th, noSound = true }))
    end

    rebuild = function()
      list = ListMenu.new(game, viewTitle(), currentRows(), {
        messageBox = true, noSound = true,
        onChoose = function(item)
          if state.pendingSwap then
            completeSwitch(item.value)
            return
          end
          openItemActions(item.value)
        end,
      })
      if state.pendingSwap then
        for i, row in ipairs(list.items) do
          if row.value == state.pendingSwap.id then
            list.swapIndex = i
            break
          end
        end
        list.footer = "Choose an ITEM\nto switch with."
      else
        list.footer = "SELECT: " .. nextViewName()
      end
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("b") and state.pendingSwap then
        state.pendingSwap = nil
        rebuild()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      local total = #list.items
      local text = Strings("%d/%d", total > 0 and list.index or 0, total)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, 160 - 8 - Font.width(text), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end

    rebuild()
    game.stack:push(screen)
  end

  local function openTossItemsList(game)
    local list
    list = ListMenu.new(game, "TOSS ITEM", bankItemRows(game), {
      messageBox = true, noSound = true,
      onChoose = function(item)
        local count = itemCount(item.value)
        if count <= 0 then
          list.footer = "The selection changed."
          return
        end
        askItemQuantity(game, list, count, function(qty)
          list.footer = Strings("Toss %s?", itemName(game, item.value))
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              list.footer = nil
              return
            end
            withdrawItem(item.value, qty)
            mod.events:emit("mod.vrm_pokemon_bank.item_tossed", { id = item.value, qty = qty })
            refreshItemRow(list, itemCount(item.value), item.value)
            list.footer = Strings("Threw away\n%s.", itemName(game, item.value))
          end, { noSound = true }))
        end)
      end,
    })
    game.stack:push(list)
  end

  -- WITHDRAW ITEM / DEPOSIT ITEM / MOVE ITEM / TOSS ITEM / CANCEL; keepOpen
  -- so each list leaves this menu underneath it.
  local function BankItemMenu(game)
    local rows = {
      { label = "MOVE ITEM", keepOpen = true, onSelect = function() openMoveItemsList(game) end },
      { label = "WITHDRAW ITEM", keepOpen = true, onSelect = function() openWithdrawItemsList(game) end },
      { label = "DEPOSIT ITEM", keepOpen = true, onSelect = function() openDepositItemsList(game) end },
      { label = "TOSS ITEM", keepOpen = true, onSelect = function() openTossItemsList(game) end },
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

  -- Same storage-level effect as withdrawItem (decrements the Bank's own
  -- count) -- the difference is purely what the caller does next: withdrawItem
  -- assumes the item is headed into a bag, tossItem assumes it is gone for
  -- good, and each fires its own event so another mod can tell the two apart
  -- (mirrors releasePokemon vs withdrawPokemon in lib/Pokemon.lua).
  mod.exports.tossItem = function(id, qty)
    local ok, err = withdrawItem(id, qty)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.item_tossed", { id = id, qty = qty })
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
