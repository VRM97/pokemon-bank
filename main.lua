local PC_MENU_LABEL = "POKéMON BANK"
local SCREEN_ID = "PokemonBankDataOptions"

return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local QuarantineReport = require("src.ui.QuarantineReport")


  local function chunkFor(rel)
    local source = mod:read(rel)
    if not source then error(("vrm_pokemon_bank: %s is missing"):format(rel), 0) end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then error(("vrm_pokemon_bank: %s did not compile: %s"):format(rel, tostring(err)), 0) end
    return chunk
  end

  local OPTION_SCHEMA = chunkFor("options.lua")()
  mod.options:define(OPTION_SCHEMA)

  local modules = {}

  local V = {}

  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  local File = V.require("File")
  local Sound = V.require("Sound")
  local Utils = V.require("Utils")
  local ListUi = V.require("ListUi")
  local Actions = V.require("Actions")
  local ModActions = V.require("ModActions").install(mod)
  local Bank = V.require("Storage").install(mod, File)
  local GenerationMap = V.require("GenerationMap")
  local Pickers = V.require("Pickers")
  local Stats, Lost

  local function confirmRestoreBank(game)
    local decoded = Bank.readBackup()
    if type(decoded) ~= "table" or type(decoded.boxes) ~= "table" then
      Actions.message(game, "No valid backup\nwas found to\011restore.")
      return
    end
    Actions.confirm(game, "Restore BANK data\nfrom the last\011backup? Current\ndata will be lost.", function(yes)
      if not yes then return end
      Bank.replaceStorage(decoded)
      Bank.flushStorage()
      Actions.message(game, "BANK data was\nrestored from\011backup.")
    end, { defaultNo = true })
  end

  local function confirmDeleteBank(game)
    Actions.confirm(game, "Delete ALL BANK\ndata? POKéMON,\nITEMS and MONEY\nwill be lost.", function(yes)
      if not yes then return end
      -- Double confirmation; this loses every box, every item and all the stored money in one press, with no undo.
      Actions.confirm(game, "Are you REALLY\nsure? This CANNOT\nbe undone.", function(yesAgain)
        if yesAgain then
          local fs = File.fs()
          if type(fs.getDirectoryItems) == "function" then
            local ok, items = pcall(fs.getDirectoryItems, File.STORAGE_DIR)
            if ok and type(items) == "table" then
              for _, name in ipairs(items) do File.remove(File.STORAGE_DIR .. "/" .. name) end
            end
          else
            Bank.deleteStorage()
            Stats.deleteStats()
          end
          Bank.resetStorage()
          Stats.resetStats()
          Actions.message(game, "All BANK data\nwas deleted.")
        end
      end, { defaultNo = true })
    end, { defaultNo = true })
  end

  local function getModOption(game, targetId, schema)
    local stored = game.mods and game.mods.modOptions and game.mods.modOptions[targetId]
    if stored ~= nil and stored[schema.key] ~= nil then return stored[schema.key] end
    return schema.default
  end

  local function setModOptionFor(game, targetId, schema, value)
    local save = game.save
    if save and save.options then
      save.options.modOptions = save.options.modOptions or {}
      local t = save.options.modOptions
      t[targetId] = t[targetId] or {}
      t[targetId][schema.key] = value
    end
    local loader = game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[targetId] = loader.modOptions[targetId] or {}
      loader.modOptions[targetId][schema.key] = value
      if loader.events then loader.events:emit("mod.options_changed", { mod = targetId, key = schema.key, value = value }) end
    end
    if game.writeOptions then pcall(game.writeOptions, game) end
  end

  local function cycleOptionValue(game, targetId, schema)
    if schema.type == "toggle" then
      setModOptionFor(game, targetId, schema, not getModOption(game, targetId, schema))
      return
    end
    local choices = schema.choices or {}
    if #choices == 0 then return end
    local cur = getModOption(game, targetId, schema)
    local index = 1
    for i, choice in ipairs(choices) do
      if choice[2] == cur then index = i break end
    end
    index = (index % #choices) + 1
    setModOptionFor(game, targetId, schema, choices[index][2])
  end

  local function openOptionChoicePopup(game, targetId, menu, schema, rebuildItems)
    local choices = schema.choices or {}
    local cur = getModOption(game, targetId, schema)
    local currentIndex = 1
    local rows = {}
    for i, choice in ipairs(choices) do
      if choice[2] == cur then currentIndex = i end
      rows[#rows + 1] = {
        label = choice[1],
        onSelect = function()
          setModOptionFor(game, targetId, schema, choice[2])
          local index = menu.index
          menu.items = rebuildItems()
          menu.index = index
          menu.footer = nil
        end,
      }
    end
    rows[#rows + 1] = { label = "CANCEL", onSelect = function() game.stack:pop() end }
    local popup = Menu.new(game, rows, { tx = 0, ty = 0, tw = 10, th = #rows * 2 + 2, noSound = true })
    popup.index = currentIndex
    popup:clampScroll()
    game.stack:push(popup)
  end

  local function openNumberPrompt(game, targetId, menu, schema, rebuildItems)
    local QuantityBox = require("src.ui.QuantityBox")
    local function clamp(v)
      if schema.min then v = math.max(schema.min, v) end
      if schema.max then v = math.min(schema.max, v) end
      return v
    end
    local cur = tonumber(getModOption(game, targetId, schema)) or 0
    game.stack:push(QuantityBox.new(game, {
      max = schema.max or 99,
      start = math.max(1, cur),
      onDone = function(qty)
        if not qty then return end
        setModOptionFor(game, targetId, schema, clamp(qty))
        local index = menu.index
        menu.items = rebuildItems()
        menu.index = index
        menu.footer = nil
      end,
    }))
  end

  local function openTextPrompt(game, targetId, menu, schema, rebuildItems)
    local NamingScreen = require("src.ui.NamingScreen")
    game.stack:push(NamingScreen.new(game, {
      title = (schema.label or schema.key) .. "?",
      maxLen = schema.maxLen or 7,
      default = getModOption(game, targetId, schema),
      onDone = function(name)
        setModOptionFor(game, targetId, schema, name)
        local index = menu.index
        menu.items = rebuildItems()
        menu.index = index
        menu.footer = nil
      end,
    }))
  end

  local function buildOptionRows(game, targetId, schema)
    local function optionValueText(row)
      if row.type == "toggle" then
        if getModOption(game, targetId, row) then return "ON", row.onHint end
        return "OFF", row.offHint
      end
      if row.type == "number" then return tostring(getModOption(game, targetId, row) or 0) end
      if row.type == "text" then return tostring(getModOption(game, targetId, row) or "") end
      local cur = getModOption(game, targetId, row)
      for _, choice in ipairs(row.choices or {}) do
        if choice[2] == cur then return choice[1], choice[3] end
      end
      local first = (row.choices or {})[1]
      if first then return first[1], first[3] or "---" end
      return "---", nil
    end

    local rows = {}
    for _, row in ipairs(schema) do
      if row.type == "toggle" or row.type == "choice" or row.type == "number" or row.type == "text" then
        local text, description = optionValueText(row)
        rows[#rows + 1] = { label = Utils.truncateName(row.label), right = Utils.truncateName(text, 4), description = description, schema = row }
      end
    end
    return rows
  end

  local function buildOptionsListScreen(game, targetId, schema, title, extraRows)
      local list
      local function rebuildItems()
      local items = buildOptionRows(game, targetId, schema)
      for _, row in ipairs(extraRows or {}) do items[#items + 1] = row end
      items[#items + 1] = { label = "CANCEL", description = "Close this menu." }
        return items
      end
    list = mod.ui.ListMenu.new(game, title, rebuildItems(), {
        rows = 6, wrap = true,
        onChoose = function(item, menu)
          if not item then return end
          if item.schema then
          local schemaType = item.schema.type
          if schemaType == "choice" and #(item.schema.choices or {}) > 2 then
            openOptionChoicePopup(game, targetId, menu, item.schema, rebuildItems)
          elseif schemaType == "number" then
            openNumberPrompt(game, targetId, menu, item.schema, rebuildItems)
          elseif schemaType == "text" then
            openTextPrompt(game, targetId, menu, item.schema, rebuildItems)
          else
            cycleOptionValue(game, targetId, item.schema)
              local index = menu.index
              menu.items = rebuildItems()
              menu.index = index
              menu.footer = nil
            end
          elseif item.onSelect then
            item.onSelect()
          elseif menu and menu.close then menu:close() end
        end,
      })
      ListUi.attachDynamicFooter(list, function(l)
        local item = l.items[l.index]
        return item and item.description or nil
      end)
      return list
  end

  local panels = {}
  local panelIndex = {}

  local function registerOptionsPanel(panel)
    if type(panel) ~= "table" then return false, "panel must be a table" end
    if type(panel.id) ~= "string" or panel.id == "" then return false, "panel.id is required" end
    if type(panel.label) ~= "string" or panel.label == "" then return false, "panel.label is required" end
    if type(panel.schema) ~= "table" then return false, "panel.schema is required" end
    local entry = { id = panel.id, label = panel.label, description = panel.description, schema = panel.schema }
    local existing = panelIndex[panel.id]
    if existing then
      panels[existing] = entry
    else
      panels[#panels + 1] = entry
      panelIndex[panel.id] = #panels
    end
    return true
  end

  local function unregisterOptionsPanel(id)
    local index = panelIndex[id]
    if not index then return false end
    table.remove(panels, index)
    panelIndex[id] = nil
    for i = index, #panels do panelIndex[panels[i].id] = i end
    return true
  end

  mod.content.screens:register(SCREEN_ID, {
    new = function(game)
      local extraRows = {}
      local function appendRow(label, onSelect, description) extraRows[#extraRows + 1] = { label = label, onSelect = onSelect, description = description } end
      appendRow("VIEW STATS", function() mod.ui.push(game, Stats.screenId) end, "See deposit and\nwithdraw totals.")
      appendRow("VIEW LOST", function() mod.ui.push(game, Lost.screenId) end, "Browse what's\nquarantined.")
      for _, panel in ipairs(panels) do
        appendRow(panel.label, function() game.stack:push(buildOptionsListScreen(game, panel.id, panel.schema, panel.label)) end, panel.description)
      end
      appendRow("RESTORE DATA", function() confirmRestoreBank(game) end, "Roll the Bank back\nto its backup.")
      appendRow("DELETE DATA", function() confirmDeleteBank(game) end, "Erase ALL Bank\ndata for good.")
      return buildOptionsListScreen(game, mod.id, OPTION_SCHEMA, PC_MENU_LABEL, extraRows)
    end,
  })
  
  local core = {
    -- storage
    loadStorage = Bank.loadStorage,
    markDirty = Bank.markDirty,
    flushStorage = Bank.flushStorage,
    normalizeBoxes = Bank.normalizeBoxes,
    ensureOrphaned = Bank.ensureOrphaned,
    reconcileCountBucket = Bank.reconcileCountBucket,
    listOrphaned = Bank.listOrphaned,
    orphanedCount = Bank.orphanedCount,
    boxCapacity = Bank.boxCapacity,
    STORAGE_VERSION = Bank.STORAGE_VERSION,
    getStorageId = Bank.getStorageId,
    boxLabel = Bank.boxLabel,
    pcBoxLabel = Bank.pcBoxLabel,
    pcBoxName = Bank.pcBoxName,
    pcBoxNamesTable = Bank.pcBoxNamesTable,
    -- list/screen framework
    setListCursor = ListUi.setListCursor,
    chooseListCurrent = ListUi.chooseListCurrent,
    drawListCounter = ListUi.drawListCounter,
    drawListTitle = ListUi.drawListTitle,
    listScreen = ListUi.listScreen,
    listGroup = ListUi.listGroup,
    lostBrowser = ListUi.lostBrowser,
    gen1ModernUiListAdapter = ListUi.gen1ModernUiListAdapter,
    attachLevelIcons = ListUi.attachLevelIcons,
    attachDynamicFooter = ListUi.attachDynamicFooter,
    monName = ListUi.monName,
    moveName = ListUi.moveName,
    moveEntryId = ListUi.moveEntryId,
    cycleBoxNumber = ListUi.cycleBoxNumber,
    clampBoxState = ListUi.clampBoxState,
    cycleCategory = ListUi.cycleCategory,
    availableCategoriesSorted = ListUi.availableCategoriesSorted,
    resetCategoryIfStale = ListUi.resetCategoryIfStale,
    -- confirmation dialogs & bulk/toss/quantity action flows
    message = Actions.message,
    confirm = Actions.confirm,
    confirmRelease = Actions.confirmRelease,
    rowActionsMenu = Actions.rowActionsMenu,
    rowChooserScreen = Actions.rowChooserScreen,
    askQuantity = Actions.askQuantity,
    confirmBulkMoveAll = Actions.confirmBulkMoveAll,
    confirmTossQuantity = Actions.confirmTossQuantity,
    pendingSwapBackHandler = Actions.pendingSwapBackHandler,
    cancelHandler = Actions.cancelHandler,
    pickerHandle = Actions.pickerHandle,
    -- mod-bound actions
    openSummary = ModActions.openSummary,
    emitOnSuccess = ModActions.emitOnSuccess,
    makeTabToggle = ModActions.makeTabToggle,
    -- sound
    playSound = Sound.playSound,
    playSaveSound = Sound.playSaveSound,
    playCry = Sound.playCry,
    -- text/name utils
    truncateName = Utils.truncateName,
    itemName = Utils.itemName,
    sortedItemIds = Utils.sortedItemIds,
    sortedIdsByName = Utils.sortedIdsByName,
    padToRight = Utils.padToRight,
    bucketAdd = Utils.bucketAdd,
    bucketSub = Utils.bucketSub,
    idQtyPayload = Utils.idQtyPayload,
  }

  local Pokemon = V.require("Pokemon").install(mod, core)
  local Moves = V.require("Moves").install(mod, core)
  core.isMovesTabEnabled = Moves.tabEnabled
  core.moveTypeOf = Moves.moveTypeOf
  core.moveDetailLine = Moves.moveDetailLine
  core.movePpText = Moves.movePpText
  local Items = V.require("Items").install(mod, core)
  core.pocketOf = Items.pocketOf
  core.availablePockets = Items.availablePockets
  core.pocketLabel = Items.pocketLabel
  core.itemDescriptionText = Items.itemDescriptionText
  local Money = V.require("Money").install(mod, core)
  Stats = V.require("Stats").install(mod, core, File)
  Lost = V.require("Lost").install(mod, core)
  local TimeCapsule = V.require("TimeCapsule").install(mod, core, Pokemon)
  local Link = V.require("Link").install(mod, core, Pokemon, Items, Money)

  mod.hooks:wrap("save.write", function(next_, game)
    local proceed = next_(game)
    if proceed ~= false then
      Bank.flushStorage()
      Stats.flush()
    end
    return proceed
  end)

  mod.events:on("mod.options_changed", function(ev)
    if not (ev and ev.mod == mod.id) then return end
    if ev.key == "box_size" or ev.key == "empty_box_deletion" then Bank.reapplyBoxPolicy() end
  end)

  local function quarantineSummary(report)
    local lostMons = #(report.lostMons or {})
    local lostQty = 0
    for _, it in ipairs(report.lostItems or {}) do lostQty = lostQty + (it.count or 1) end
    local restoredMons = #(report.restoredMons or {})
    local restoredQty = 0
    for _, it in ipairs(report.restoredItems or {}) do restoredQty = restoredQty + (it.count or 1) end
    local parts = {}
    if lostMons > 0 or lostQty > 0 then
      parts[#parts + 1] = Strings("%d POKéMON and\n%d items were\nset aside.", lostMons, lostQty)
    end
    if restoredMons > 0 or restoredQty > 0 then
      parts[#parts + 1] = Strings("%d POKéMON and\n%d items were\nrestored.", restoredMons, restoredQty)
    end
    return table.concat(parts, "\011")
  end

  local function validateStorage(game)
    local function migrateLegacyGen2Money()
      if GameVersion.generation() ~= 2 then return 0 end
      local save = game and game.save
      if not save or save.money == nil then return 0 end
      local amount = math.max(0, math.floor(tonumber(save.money) or 0))
      save.money = nil
      if amount > 0 then mod.exports.depositMoney(amount) end
      return amount
    end

    if not (game and game.data) then return nil end
    Bank.loadStorage()
    local poke = Pokemon.validateStorage(game)
    local capsule = TimeCapsule.validateStorage(game)
    local items = Items.validateStorage(game)
    local moves = Moves.validateStorage(game)
    local recoveredMoney = migrateLegacyGen2Money()
    local changed = poke.changed or capsule.changed or items.changed or moves.changed
    if changed then Bank.markDirty() end
    local lostItems = {}
    for _, item in ipairs(poke.lostItems or {}) do lostItems[#lostItems + 1] = item end
    for _, item in ipairs(items.lostItems or {}) do lostItems[#lostItems + 1] = item end
    for _, item in ipairs(moves.lostItems or {}) do lostItems[#lostItems + 1] = item end
    local restoredItems = {}
    for _, item in ipairs(items.restoredItems or {}) do restoredItems[#restoredItems + 1] = item end
    for _, item in ipairs(moves.restoredItems or {}) do restoredItems[#restoredItems + 1] = item end
    local lostMons = {}
    for _, mon in ipairs(poke.lostMons or {}) do lostMons[#lostMons + 1] = mon end
    for _, mon in ipairs(capsule.lostMons or {}) do lostMons[#lostMons + 1] = mon end
    local restoredMons = {}
    for _, mon in ipairs(poke.restoredMons or {}) do restoredMons[#restoredMons + 1] = mon end
    for _, mon in ipairs(capsule.restoredMons or {}) do restoredMons[#restoredMons + 1] = mon end
    return {
      changed = changed,
      pokemon = poke,
      timeCapsule = capsule,
      items = items,
      moves = moves,
      recoveredMoney = recoveredMoney,
      report = {
        lostMons = lostMons,
        lostItems = lostItems,
        restoredMons = restoredMons,
        restoredItems = restoredItems
      }
    }
  end

  mod.exports.validateStorage = validateStorage

  local modernUi = mod.find("gen2_clean_ui") or mod.find("gen1_modern_ui")
  if (modernUi and modernUi.exports and type(modernUi.exports.registerAdapter) == "function") then

    local function externalScreen(id, capabilities)
      local actions = {}
      for _, name in ipairs(capabilities) do
        actions[name] = function(_, state, payload)
          local surface = state.gen1ModernUi
          local fn = surface and surface[name]
          if type(fn) ~= "function" then return false end
          fn(payload)
          return true
        end
      end
      return {
        canSuppressNative = true,
        match = function(state) return type(state) == "table" and state.screenId == id and type(state.gen1ModernUi) == "table" end,
        model = function(_, state)
          local surface = state.gen1ModernUi
          return {
            title = surface.title(),
            rows = surface.rows(),
            index = surface.index(),
            scroll = surface.scroll(),
            footer = surface.footer(),
          }
        end,
        actions = actions,
      }
    end

    mod.exports.gen1ModernUi = {
      apiVersion = 1,
      screens = {
        [Pokemon.transferBoxScreenId] = externalScreen(Pokemon.transferBoxScreenId, { "up", "down", "left", "right", "select", "back", "start", "hover" }),
        [Pokemon.moveScreenId] = externalScreen(Pokemon.moveScreenId, { "up", "down", "left", "right", "select", "back", "start", "hover" }),
        [Items.screenId] = externalScreen(Items.screenId, { "up", "down", "left", "right", "select", "back", "start", "hover" }),
        [Money.amountScreenId] = externalScreen(Money.amountScreenId, { "up", "down", "left", "right", "select", "back", "start" }),
        [Pickers.MON_PICKER_SCREEN_ID] = externalScreen(Pickers.MON_PICKER_SCREEN_ID, { "up", "down", "left", "right", "select", "back", "start", "hover" }),
        [Pickers.ITEM_PICKER_SCREEN_ID] = externalScreen(Pickers.ITEM_PICKER_SCREEN_ID, { "up", "down", "select", "back", "start", "hover" }),
        [Pickers.BOX_PICKER_SCREEN_ID] = externalScreen(Pickers.BOX_PICKER_SCREEN_ID, { "up", "down", "left", "right", "select", "back", "start", "hover" }),
      },
    }
    local registered = false
    mod.events:on("game.ready", function()
      if registered then return end
      local ok = pcall(modernUi.exports.registerAdapter, { owner = mod.id, contract = mod.exports.gen1ModernUi })
      if ok then registered = true end
    end)
  end

  local liveGame
  mod.events:on("game.ready", function(ev) liveGame = ev and ev.game or liveGame end)

  mod.events:on("save.loaded", function()
    local game = liveGame
    if not game then return end
    local result = validateStorage(game)
    if result and result.report and result.changed then
      local notice = mod.options:get("quarantine_notice")
      if notice == "report" then
        game.stack:push(QuarantineReport.new(game, result.report))
      elseif notice == "message" then
        local summary = quarantineSummary(result.report)
        if summary ~= "" then Actions.message(game, summary) end
      end
    end
    if result and result.recoveredMoney and result.recoveredMoney > 0 then
      game.stack:push(TextBox.new(game, Strings("¥%d from an older\nBANK version was\011moved to the BANK.", result.recoveredMoney)))
    end
  end)

  local function confirmLinkSave(game)
    Actions.confirm(game, "Before opening the\nlink, you have to\011SAVE the game.", function(yes)
      if yes then
        Bank.markDirty()
        if game.writeSave then game:writeSave() end
        Sound.playSaveSound(game)
        Link.open(game)
      end
    end)
  end

  local menuActions = {}
  local menuActionIndex = {}

  local function registerBankMenuAction(action)
    if type(action) ~= "table" then return false, "action must be a table" end
    if type(action.id) ~= "string" or action.id == "" then return false, "action.id is required" end
    if type(action.label) ~= "string" or action.label == "" then return false, "action.label is required" end
    if type(action.onSelect) ~= "function" then return false, "action.onSelect is required" end
    local entry = { id = action.id, label = action.label, onSelect = action.onSelect }
    local existing = menuActionIndex[action.id]
    if existing then
      menuActions[existing] = entry
    else
      menuActions[#menuActions + 1] = entry
      menuActionIndex[action.id] = #menuActions
    end
    return true
  end

  local function unregisterBankMenuAction(id)
    local index = menuActionIndex[id]
    if not index then return false end
    table.remove(menuActions, index)
    menuActionIndex[id] = nil
    for i = index, #menuActions do menuActionIndex[menuActions[i].id] = i end
    return true
  end

  local function openBankMenu(game)
    local rows = {}
    local function appendRow(label, onSelect) rows[#rows + 1] = { label = label, keepOpen = true, onSelect = onSelect } end
    local pokeOn, itemsOn, movesOn, moneyOn, linkOn = Pokemon.tabEnabled(), Items.tabEnabled(), Moves.tabEnabled(), Money.tabEnabled(), Link.tabEnabled()
    if pokeOn then appendRow("POKéMON", function() mod.ui.push(game, Pokemon.screenId) end) end
    if itemsOn then appendRow("ITEMS", function() mod.ui.push(game, Items.screenId) end) end
    if movesOn then appendRow("MOVES", function() mod.ui.push(game, Moves.screenId) end) end
    if moneyOn then appendRow("MONEY", function() mod.ui.push(game, Money.screenId) end) end
    if linkOn then appendRow("LINK", function() confirmLinkSave(game) end) end
    for _, action in ipairs(menuActions) do appendRow(action.label, function() action.onSelect(game) end) end
    if #rows == 0 then return false end
    if #rows == 1 then
      rows[1].onSelect()
      return true
    end
    appendRow("CANCEL")
    local th = #rows * 2 + 2
    game.stack:push(Menu.new(game, rows, { tx = 0, ty = 0, tw = 12, th = th }))
    return true
  end

  local function pcMenuPosition() return mod.options:get("pc_menu_position") or "end" end

  local pcEntryEnabledByOthers = true

  local function pcEntryEnabled() return pcEntryEnabledByOthers and pcMenuPosition() ~= "none" end

  mod.hooks:wrap("ui.pc.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    if GameVersion.generation() == 2 then return out end
    if not pcEntryEnabled() then return out end
    if not (Pokemon.tabEnabled() or Items.tabEnabled() or Moves.tabEnabled() or Money.tabEnabled() or #menuActions > 0) then return out end
    local row = {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function()
        Sound.playSound(game, "Enter_PC")
        game.stack:push(TextBox.new(game, "Accessed POKéMON\nBANK.\fAccessed Shared\nStorage System.", function() openBankMenu(game) end))
      end,
    }
    local position = pcMenuPosition()
    if position == "start" then
      table.insert(out, 1, row)
      return out
    end
    if position == "middle" then
      local i = #out
      for j, item in ipairs(out) do
        if item.label == "BILL'S PC" or item.label == "SOMEONE'S PC" then
          i = j
          break
        end
      end
      table.insert(out, i + 1, row)
      return out
    end
    return mod.ui.insertBefore(out, "PROF.OAK's PC", row)
  end)

  -- Gen 2's Pokémon Center PC selector has no hook of its own -- ui.pc.items above fires one level deeper there (Bill's own box menu, or the player's item PC), never on this top screen.
  -- Patched directly, gated to a Gen 2 boot, so POKéMON BANK sits as a peer of BILL's PC / PROF.OAK's PC there -- CenterPcMenu is not one of Gen2Compat's served facades, so this is real engine-internals surgery, not an adapter call.
  if GameVersion.generation() == 2 then
    local ok, CenterPcMenu = pcall(require, "src.ui.gen2.CenterPcMenu")
    if ok and type(CenterPcMenu) == "table" then
      local ROW_ID = "vrm_pokemon_bank"
      local origBuildEntries = CenterPcMenu.buildEntries
      CenterPcMenu.buildEntries = function(self)
        origBuildEntries(self)
        if not pcEntryEnabled() then return end
        if not (Pokemon.tabEnabled() or Items.tabEnabled() or Moves.tabEnabled() or Money.tabEnabled() or #menuActions > 0) then return end
        local entries = self.entries
        local row = { id = ROW_ID, label = PC_MENU_LABEL }
        local position = pcMenuPosition()
        if position == "start" then
          table.insert(entries, 1, row)
          return
        end
        if position == "middle" then
          local pos = #entries + 1
          for i, e in ipairs(entries) do
            if e.id == "bills" then pos = i + 1 break end
          end
          table.insert(entries, pos, row)
          return
        end
        local pos = #entries + 1
        for i, e in ipairs(entries) do
          if e.id == "players" then pos = i + 1 break end
        end
        table.insert(entries, pos, row)
      end
      local origChoose = CenterPcMenu.choose
      CenterPcMenu.choose = function(self)
        local entry = self.entries[self.index]
        if entry and entry.id == ROW_ID then
          self:playSfx("Sfx_ChoosePcOption")
          self:say({ { PC_MENU_LABEL, "accessed." }, { "Shared Storage", "System opened." } }, function() openBankMenu(self.game) end)
        else return origChoose(self) end
      end
    end
  end

  local function healBankAtCenter()
    if mod.options:get("auto_heal") ~= "center" then return end
    if liveGame then mod.exports.healBank(liveGame) end
  end

  if GameVersion.generation() == 2 then
    local ok, Specials = pcall(require, "src.script.gen2.Specials")
    if ok and type(Specials) == "table" and type(Specials.ALL) == "table"
        and type(Specials.ALL.HealParty) == "function" then
      local origHealParty = Specials.ALL.HealParty
      Specials.ALL.HealParty = function(vm)
        local result = origHealParty(vm)
        healBankAtCenter()
        return result
      end
    end
  else
    local ok, OverworldController = pcall(require, "src.world.OverworldController")
    if ok and type(OverworldController) == "table"
        and type(OverworldController.finishNurseHeal) == "function" then
      local origFinishNurseHeal = OverworldController.finishNurseHeal
      OverworldController.finishNurseHeal = function(self, bye, onDone, npc)
        healBankAtCenter()
        return origFinishNurseHeal(self, bye, onDone, npc)
      end
    end
  end

  mod.hooks:wrap("ui.options.rows", function(next_, game, rows)
    local out = next_(game, rows)
    if type(out) ~= "table" then return out end
    local row = {
      id = "vrm_pokemon_bank_data",
      label = PC_MENU_LABEL,
      activate = function(g) mod.ui.push(g, SCREEN_ID) end,
    }
    local hasMods = false
    for _, r in ipairs(out) do
      if r.label == "MODS" then hasMods = true break end
    end
    return mod.ui.insertBefore(out, hasMods and "MODS" or "BACK", row)
  end)

  local function guarded(fn)
    return function(game, ...)
      if not game then return nil, "no game" end
      return fn(game, ...)
    end
  end

  local function guardedPushScreen(screenId)
    return guarded(function(game) return mod.ui.push(game, screenId) end)
  end

  local function guardedOpenPicker(picker)
    return guarded(function(game, opts) return picker(mod, core, game, opts) end)
  end

  mod.exports.pcMenuLabel = PC_MENU_LABEL
  mod.exports.openPokemonMenu = guardedPushScreen(Pokemon.screenId)
  mod.exports.openTimeCapsuleMenu = guardedPushScreen(TimeCapsule.screenId)
  mod.exports.openItemsMenu = guardedPushScreen(Items.screenId)
  mod.exports.openMovesMenu = guardedPushScreen(Moves.screenId)
  mod.exports.openMoneyMenu = guardedPushScreen(Money.screenId)
  mod.exports.openBankMenu = guarded(openBankMenu)
  mod.exports.open = function(game, tab)
    if not game then return nil, "no game" end
    if tab == "items" then return mod.exports.openItemsMenu(game) end
    if tab == "moves" then return mod.exports.openMovesMenu(game) end
    if tab == "money" then return mod.exports.openMoneyMenu(game) end
    return mod.exports.openPokemonMenu(game)
  end
  mod.exports.openPokemonPicker = guardedOpenPicker(Pickers.openMonPicker)
  mod.exports.openMovePicker = guardedOpenPicker(Pickers.openMovePicker)
  mod.exports.openItemPicker = guardedOpenPicker(Pickers.openItemPicker)
  mod.exports.openBoxPicker = guardedOpenPicker(Pickers.openBoxPicker)
  mod.exports.setPcEntryEnabled = function(enabled)
    pcEntryEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.isPcEntryEnabled = function() return pcEntryEnabled() end
  mod.exports.setBoxSizeOverride = Bank.setBoxSizeOverride
  mod.exports.getBoxSizeOverride = Bank.getBoxSizeOverride
  mod.exports.getStorageId = Bank.getStorageId
  mod.exports.translateSpeciesId = GenerationMap.translateSpeciesId
  mod.exports.translateItemId = GenerationMap.translateItemId
  mod.exports.translateMoveId = GenerationMap.translateMoveId
  mod.exports.flush = function()
    local was = Bank.isDirty() or Stats.isDirty()
    Bank.flushStorage()
    Stats.flush()
    return was
  end
  mod.exports.registerOptionsPanel = registerOptionsPanel
  mod.exports.unregisterOptionsPanel = unregisterOptionsPanel
  mod.exports.registerBankMenuAction = registerBankMenuAction
  mod.exports.unregisterBankMenuAction = unregisterBankMenuAction
  mod.log:info("Pokemon Bank loaded")
end
