local V = ...

local SCREEN_ID = "PokemonBankItems"

local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")
local ChoiceBox = require("src.ui.ChoiceBox")

local Module = {}

function Module.install(mod, core)
  local GenerationMap = V.require("GenerationMap")
  local loadStorage = core.loadStorage
  local itemName = core.itemName

  local Items = { screenId = SCREEN_ID }

  local function startsWith(text, prefix) return type(text) == "string" and text:find("^" .. prefix) ~= nil end

  local function isHM(id) return startsWith(id, "HM_") end

  local function isTM(id) return startsWith(id, "TM_") end

  local tmItemDepositOverride = nil

  local function blockTmDeposit(id)
    if not isTM(id) then return false end
    if tmItemDepositOverride ~= nil then return not tmItemDepositOverride end
    return not core.isMovesTabEnabled or core.isMovesTabEnabled()
  end

  local function isKeyItem(def)
    return def ~= nil and (def.keyItem == true or def.pocket == "KEY_ITEM")
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
    core.bucketAdd(loadStorage().items, id, qty)
    core.markDirty()
    return true
  end

  local function withdrawItem(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if not core.bucketSub(loadStorage().items, id, qty) then return false, "not enough" end
    core.markDirty()
    return true
  end

  local function listItems()
    local out = {}
    for id, count in pairs(loadStorage().items) do out[id] = count end
    return out
  end

  local function isValidItem(id, data)
    return type(id) == "string" and id ~= "" and type(data) == "table" and type(data.items) == "table" and data.items[id] ~= nil
  end

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
      normalizeItemKeys(s.items, data)
      normalizeItemKeys(orphaned.items, data)
    end
    local function isValid(id) return isValidItem(id, data) and not isBlacklisted(id, data.items[id]) end
    local result = core.reconcileCountBucket(s.items, orphaned.items, isValid, "POKéMON BANK")
    result.changed = result.quarantined > 0 or result.restored > 0
    return result
  end

  local function listInvalidItems() return core.listOrphaned("items") end

  local function invalidItemCount(id) return core.orphanedCount("items", id) end

  -- =========================================================================
  -- Item UI
  -- =========================================================================
  local ITEM_POCKETS = {
    { id = "ITEM", label = "Items" },
    { id = "BALL", label = "Balls" },
    { id = "KEY_ITEM", label = "Key Items" },
    { id = "TM_HM", label = "TM/HM" },
  }

  function Items.pocketOf(game, id)
    local def = game.data.items[id]
    return def and def.pocket
  end

  function Items.availablePockets(game, counts)
    local present = {}
    for id, count in pairs(counts) do
      if count and count > 0 then
        local p = Items.pocketOf(game, id)
        if p then present[p] = true end
      end
    end
    local list = { "ALL" }
    for _, entry in ipairs(ITEM_POCKETS) do
      if present[entry.id] then list[#list + 1] = entry.id end
    end
    return list
  end

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

  local function itemRow(game, id, count)
    return { value = id, label = core.truncateName(itemName(game, id)), right = "x" .. tostring(count) }
  end

  local function itemRows(game, items)
    local rows = {}
    for _, id in ipairs(core.sortedItemIds(game, items)) do
      rows[#rows + 1] = itemRow(game, id, items[id])
    end
    return rows
  end

  local function bagItemRowsOrdered(game)
    local inv = game.save.inventory
    local rows = {}
    for _, id in ipairs(Bag.order(game.save)) do
      if inv[id] and inv[id] > 0 then
        rows[#rows + 1] = itemRow(game, id, inv[id])
      end
    end
    return rows
  end

  local function pcItemFull(game, id)
    local pc = game.save.pcItems
    if pc[id] then return false end
    local cap = (game.data.field and game.data.field.pcItemCap) or 50
    local stacks = 0
    for _ in pairs(pc) do stacks = stacks + 1 end
    return stacks >= cap
  end

  local function pageLabel(view)
    if view == "bank" then return "BANK" end
    if view == "pc" then return "PC" end
    return "BAG"
  end

  local function BankItemMenu(game)
    game.save.pcItems = game.save.pcItems or {}
    local state = {
      view = "bank",
      pocket = "ALL",
      pendingSwap = nil
    }
    local group

    local function storeFor(view)
      if view == "bank" then return loadStorage().items
      elseif view == "bag" then return game.save.inventory
      else return game.save.pcItems end
    end

    local function currentStore() return storeFor(state.view) end

    local function rawRows(view)
      if view == "bag" then return bagItemRowsOrdered(game) end
      return itemRows(game, storeFor(view))
    end

    local function filteredItemRows(view)
      local rows = rawRows(view)
      if state.pocket == "ALL" then return rows end
      local filtered = {}
      for _, row in ipairs(rows) do
        if Items.pocketOf(game, row.value) == state.pocket then filtered[#filtered + 1] = row end
      end
      return filtered
    end

    local function cyclePocket(delta)
      if state.pendingSwap then return end
      local avail = Items.availablePockets(game, currentStore())
      local nextPocket = core.cycleCategory(state.pocket, avail, delta)
      if nextPocket == state.pocket then return end
      state.pocket = nextPocket
      group.rebuild()
    end

    local function successMsg(destView, id)
      local name = itemName(game, id)
      if destView == "bank" then return Strings("%s was\nstored in BANK.", name)
      elseif destView == "pc" then return Strings("%s was\nstored via PC.", name)
      else return Strings("Withdrew\n%s.", name) end
    end

    local function bankDepositBlockReason(id)
      if blockTmDeposit(id) then return "TMs go through\nthe MOVES tab!" end
      if isBlacklisted(id, game.data.items[id]) then return "That can't be\nstored in BANK!" end
      return nil
    end

    local function moveItem(destView, id, qty)
      local srcView = state.view
      local pc = game.save.pcItems
      if destView == "bag" then
        if not Bag.add(game.save, id, qty, game.data) then return false, "You can't carry\nany more items." end
      elseif destView == "bank" then
        local reason = bankDepositBlockReason(id)
        if reason then return false, reason end
      elseif destView == "pc" then
        if pcItemFull(game, id) then return false, "No room left to\nstore items." end
      end
      if srcView == "bag" then
        Bag.remove(game.save, id, qty)
      elseif srcView == "bank" then
        withdrawItem(id, qty)
      elseif srcView == "pc" then
        core.bucketSub(pc, id, qty)
      end
      if destView == "bank" then
        depositItem(id, qty, game.data.items[id])
      elseif destView == "pc" then
        core.bucketAdd(pc, id, qty)
      end
      if destView == "bank" then mod.events:emit("mod.vrm_pokemon_bank.item_deposited", { id = id, qty = qty }) end
      if srcView == "bank" then mod.events:emit("mod.vrm_pokemon_bank.item_withdrawn", { id = id, qty = qty }) end
      core.playSound(game, "Withdraw_Deposit")
      return true, successMsg(destView, id)
    end

    local function startMove(destView, id)
      local count = currentStore()[id]
      if not count then
        group.screen.list.footer = "The selection changed."
        return
      end
      if destView == "bank" then
        local reason = bankDepositBlockReason(id)
        if reason then
          group.screen.list.footer = reason
          return
        end
      end
      core.askQuantity(game, group.screen.list, count, function(qty)
        local _, msg = moveItem(destView, id, qty)
        group.rebuild(true)
        group.screen.list.footer = msg
      end)
    end

    local function startMoveAll()
      if state.pendingSwap then return end
      local rows = filteredItemRows(state.view)
      local destView = state.view == "bank" and "bag" or "bank"
      core.confirmBulkMoveAll(game, {
        count = #rows,
        verb = destView == "bag" and "Withdraw" or "Deposit",
        resultVerb = destView == "bag" and "Withdrew" or "Deposited",
        noun = "items",
        -- moveItem already plays Withdraw_Deposit per successful row
        playSound = false,
        run = function()
          local moved, refused = 0, 0
          for _, row in ipairs(rows) do
            local count = currentStore()[row.value]
            if count and count > 0 then
              local ok = moveItem(destView, row.value, count)
              if ok then moved = moved + 1 else refused = refused + 1 end
            end
          end
          return moved, refused
        end,
        rebuild = function() group.rebuild(true) end,
        setFooter = function(msg) group.screen.list.footer = msg end,
      })
    end

    local function startToss(id)
      local count = currentStore()[id]
      if not count then
        group.screen.list.footer = "The selection changed."
        return
      end
      if state.view ~= "bank" then
        local def = game.data.items[id]
        if isKeyItem(def) or isHM(id) then
          group.screen.list.footer = "That's too impor-\ntant to toss!"
          return
        end
      end
      core.confirmTossQuantity(game, group.screen.list, {
        count = count,
        name = itemName(game, id),
        choice = function(prompt, onYes)
          group.screen.list.footer = prompt
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then
              group.screen.list.footer = nil
              return
            end
            onYes()
          end, { noSound = true }))
        end,
        onToss = function(qty)
          if state.view == "bank" then
            withdrawItem(id, qty)
            mod.events:emit("mod.vrm_pokemon_bank.item_tossed", { id = id, qty = qty })
          elseif state.view == "bag" then
            Bag.remove(game.save, id, qty)
          else
            core.bucketSub(game.save.pcItems, id, qty)
          end
        end,
        rebuild = function() group.rebuild(true) end,
      })
    end

    local function completeSwitch(targetId)
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
          core.playSound(game, "Swap")
        end
      end
      group.rebuild(true)
    end

    local function openItemActions(id)
      local view = state.view
      local rows = {}
      local function addRow(label, onSelect) rows[#rows + 1] = { label = label, onSelect = onSelect } end
      if view ~= "bank" then addRow("TO BANK", function() startMove("bank", id) end) end
      if view ~= "bag" then addRow("TO BAG", function() startMove("bag", id) end) end
      if view ~= "pc" then addRow("TO PC", function() startMove("pc", id) end) end
      if view == "bag" then
        addRow("SWITCH", function()
          state.pendingSwap = { id = id }
          group.rebuild(true)
          for i, row in ipairs(group.screen.list.items) do
            if row.value == state.pendingSwap.id then
              group.screen.list.swapIndex = i
              break
            end
          end
        end)
      end
      addRow("TOSS", function() startToss(id) end)
      addRow("CANCEL")
      core.rowActionsMenu(game, rows)
    end

    local backHandler = core.pendingSwapBackHandler(state, function(preserve) group.rebuild(preserve) end, function() game.stack:pop() end)

    group = core.listGroup(game, {
      screenId = SCREEN_ID,
      counter = true,
      views = { "bank", "bag", "pc" },
      state = state,
      label = pageLabel,
      title = function(view)
        local base = pageLabel(view)
        if state.pocket == "ALL" then return base end
        return Strings("%s (%s)", base, Items.pocketLabel(state.pocket))
      end,
      dynamicFooter = function(view, item, nextLabel)
        if state.pendingSwap then return "Choose an ITEM\nto switch with." end
        local detail = item and Items.itemDescriptionText(game, item.value)
        return detail or ("\nSELECT: " .. nextLabel)
      end,
      build = function(view)
        local avail = Items.availablePockets(game, storeFor(view))
        state.pocket = core.resetCategoryIfStale(state.pocket, avail)
        return filteredItemRows(view), {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item)
            if state.pendingSwap then
              completeSwitch(item.value)
              return
            end
            openItemActions(item.value)
          end,
        }
      end,
      onClose = backHandler,
      extraKeys = function(input)
        if state.pendingSwap then
          if input:wasPressed("select") or input:wasPressed("left")
              or input:wasPressed("right") or input:wasPressed("start") then return true end
          return false
        end
        if input:wasPressed("left") then cyclePocket(-1); return true end
        if input:wasPressed("right") then cyclePocket(1); return true end
        if input:wasPressed("start") then startMoveAll(); return true end
        return false
      end,
      modernUi = {
        left = function() cyclePocket(-1) end,
        right = function() cyclePocket(1) end,
        start = function() if not state.pendingSwap then group.cycleView() end end,
        select = function(payload)
          if payload then core.setListCursor(group.screen.list, payload) end
          core.chooseListCurrent(group.screen.list, function() game.stack:pop() end)
        end,
        back = function() backHandler() end,
      },
    })

    return group.screen
  end

  mod.content.screens:register(SCREEN_ID, { new = BankItemMenu })

  local itemsTab = core.makeTabToggle("show_items_tab")
  Items.tabEnabled = itemsTab.enabled

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

  mod.exports.withdrawItem = core.emitOnSuccess(withdrawItem, "mod.vrm_pokemon_bank.item_withdrawn", core.idQtyPayload)
  mod.exports.tossItem = core.emitOnSuccess(withdrawItem, "mod.vrm_pokemon_bank.item_tossed", core.idQtyPayload)
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
    if value == nil then
      tmItemDepositOverride = nil
    else
      tmItemDepositOverride = value ~= false
    end
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
