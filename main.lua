local PC_MENU_LABEL = "POKéMON BANK"
local SCREEN_ID = "PokemonBankDataOptions"

return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local liveGame

  local function chunkFor(rel)
    local source = mod:read(rel)
    if not source then error(("vrm_pokemon_bank: %s is missing"):format(rel), 0) end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then error(("vrm_pokemon_bank: %s did not compile: %s"):format(rel, tostring(err)), 0) end
    return chunk
  end

  local OPTION_SCHEMA = chunkFor("options.lua")()
  mod.options:define(OPTION_SCHEMA)

  local ownScreens = {}
  do
    local screens = mod.content.screens
    local register = screens.register
    screens.register = function(self, id, def, ...)
      ownScreens[id] = def
      return register(self, id, def, ...)
    end
  end

  local modules = {}

  local V = {}

  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  local Widgets = V.require("Widgets")
  local Menu, TextBox, QuarantineReport = Widgets.Menu, Widgets.TextBox, Widgets.QuarantineReport
  local File = V.require("File")
  local Utils = V.require("Utils")
  local Screen = V.require("Screen")
  local Actions = V.require("Actions")
  local ModActions = V.require("ModActions").install(mod)
  local Bank = V.require("Storage").install(mod)
  local GenerationMap = V.require("GenerationMap")
  local Pickers = V.require("Pickers")
  local Stats, Lost

  local function confirmRestoreBank(game)
    local any = false
    for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
      if record.file.hasFileBackup() then any = true end
    end
    if not any then
      Actions.message(game, "No valid backup\nwas found to\011restore.")
      return
    end
    Actions.confirm(game, "Restore BANK data\nfrom the last\011backup? Current\ndata will be lost.", function(yes)
      if not yes then return end
      for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
        if record.file.restoreFileBackup() then
          record.file.markDirty()
          record.file.flushFile()
        end
      end
      Actions.message(game, "BANK data was\nrestored from\011backup.")
    end, { defaultNo = true })
  end

  local function confirmDeleteBank(game)
    Actions.confirm(game, "Delete ALL BANK\ndata? POKéMON,\11ITEMS, MONEY and\nCOINS will be lost.", function(yes)
      if not yes then return end
      Actions.confirm(game, "Are you REALLY\nsure? This CANNOT\nbe undone.", function(yesAgain)
        if yesAgain then
          local fs = File.fs()
          local swept = false
          if type(fs.getDirectoryItems) == "function" then
            local dir = Bank.CustomStorage.getCustomStorage(mod.id).file.STORAGE_DIR
            local ok, items = pcall(fs.getDirectoryItems, dir)
            if ok and type(items) == "table" then
              for _, name in ipairs(items) do File.remove(dir .. "/" .. name) end
              swept = true
            end
          end
          if not swept then
            for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
              record.file.deleteFile()
              record.statsFile.deleteFile()
            end
          end
          for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
            record.file.resetFile()
            record.statsFile.resetFile()
          end
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
    local QuantityBox = Widgets.QuantityBox
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

  local function isOptionRow(row) return row.type == "toggle" or row.type == "choice" or row.type == "number" or row.type == "text" end

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
    local wide = Widgets.active()
    local rows = {}
    for _, row in ipairs(schema) do
      if isOptionRow(row) then
        local text, description = optionValueText(row)
        rows[#rows + 1] = {
          label = wide and row.label or Utils.truncateName(row.label),
          right = wide and text or Utils.truncateName(text, 4),
          description = description, schema = row,
        }
      end
    end
    return rows
  end

  local function buildOptionsListScreen(game, targetId, schema, title, extraRows)
    local function rebuildItems()
      local items = buildOptionRows(game, targetId, schema)
      for _, row in ipairs(extraRows or {}) do items[#items + 1] = row end
      items[#items + 1] = { label = "CANCEL", description = "Close this menu." }
      return items
    end

    local list = Widgets.listMenu(mod.ui.ListMenu).new(game, title, rebuildItems(), {
      rows = 6, wrap = true,
      onChoose = function(item, menu)
        if not item then return end
        if item.schema then
          local schemaType = item.schema.type
          if schemaType == "choice" and #(item.schema.choices or {}) > 2 then openOptionChoicePopup(game, targetId, menu, item.schema, rebuildItems)
          elseif schemaType == "number" then openNumberPrompt(game, targetId, menu, item.schema, rebuildItems)
          elseif schemaType == "text" then openTextPrompt(game, targetId, menu, item.schema, rebuildItems)
          else
            cycleOptionValue(game, targetId, item.schema)
            local index = menu.index
            menu.items = rebuildItems()
            menu.index = index
            menu.footer = nil
          end
        elseif item.onSelect then item.onSelect()
        elseif menu and menu.close then menu:close() end
      end,
    })
    Screen.attachDynamicFooter(list, function(l)
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
    if existing then panels[existing] = entry
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

  local function mainExtraRows(game)
    local extraRows = {}
    local function appendRow(label, onSelect, description) extraRows[#extraRows + 1] = { label = label, onSelect = onSelect, description = description } end
    appendRow("VIEW STATS", function() mod.ui.push(game, Stats.screenId) end, "See deposit and\nwithdraw totals.")
    appendRow("VIEW LOST", function() mod.ui.push(game, Lost.screenId) end, "Browse what's\nquarantined.")
    for _, panel in ipairs(panels) do appendRow(panel.label, function() game.stack:push(buildOptionsListScreen(game, panel.id, panel.schema, panel.label)) end, panel.description) end
    appendRow("RESTORE DATA", function() confirmRestoreBank(game) end, "Roll the Bank back\nto its backup.")
    appendRow("DELETE DATA", function() confirmDeleteBank(game) end, "Erase ALL Bank\ndata for good.")
    return extraRows
  end

  local function optionsRowCount()
    local count = #mainExtraRows(nil)
    for _, row in ipairs(OPTION_SCHEMA) do if isOptionRow(row) then count = count + 1 end end
    return count
  end

  mod.content.screens:register(SCREEN_ID, {
    new = function(game) return buildOptionsListScreen(game, mod.id, OPTION_SCHEMA, PC_MENU_LABEL, mainExtraRows(game)) end,
  })

  local core = {
    getLiveGame = function() return liveGame end,
    loadStorage = Bank.loadStorage,
    markDirty = Bank.markDirty,
    flushStorage = Bank.flushStorage,
    normalizeBoxes = Bank.normalizeBoxes,
    newBox = Bank.newBox,
    ensureOrphaned = Bank.ensureOrphaned,
    reconcileCountBucket = Bank.reconcileCountBucket,
    listOrphaned = Bank.listOrphaned,
    orphanedCount = Bank.orphanedCount,
    boxCapacity = Bank.boxCapacity,
    currentBox = Bank.currentBox,
    setCurrentBox = Bank.setCurrentBox,
    STORAGE_VERSION = Bank.STORAGE_VERSION,
    getStorageId = Bank.getStorageId,
    boxLabel = Bank.boxLabel,
    pcBoxLabel = Bank.pcBoxLabel,
    pcBoxName = Bank.pcBoxName,
    pcBoxNamesTable = Bank.pcBoxNamesTable,
    Screen = Screen,
    setListCursor = Screen.setListCursor,
    chooseListCurrent = Screen.chooseListCurrent,
    drawListCounter = Screen.drawListCounter,
    drawListTitle = Screen.drawListTitle,
    listScreen = Screen.listScreen,
    listGroup = Screen.listGroup,
    entryScreen = Screen.entryScreen,
    transferGroup = Screen.transferGroup,
    pickerScreen = Screen.pickerScreen,
    isAllPage = Screen.isAllPage,
    drawTitleMark = Screen.drawTitleMark,
    drawRowMark = Screen.drawRowMark,
    gen1ModernUiListAdapter = Screen.gen1ModernUiListAdapter,
    attachLevelIcons = Screen.attachLevelIcons,
    attachHeldItemMarks = Screen.attachHeldItemMarks,
    attachDynamicFooter = Screen.attachDynamicFooter,
    monName = Screen.monName,
    moveName = Screen.moveName,
    moveEntryId = Screen.moveEntryId,
    availableCategoriesSorted = Screen.availableCategoriesSorted,
    message = Actions.message,
    confirm = Actions.confirm,
    confirmRelease = Actions.confirmRelease,
    rowActionsMenu = Actions.rowActionsMenu,
    askQuantity = Actions.askQuantity,
    confirmBulkMoveAll = Actions.confirmBulkMoveAll,
    confirmTossQuantity = Actions.confirmTossQuantity,
    cancelHandler = Actions.cancelHandler,
    pickerHandle = Actions.pickerHandle,
    openSummary = ModActions.openSummary,
    makeTabToggle = ModActions.makeTabToggle,
    playSound = Utils.playSound,
    playSaveSound = Utils.playSaveSound,
    playCry = Utils.playCry,
    truncateName = Utils.truncateName,
    currentList = Screen.currentList,
    CustomStorage = Bank.CustomStorage,
    storageHooks = Bank.hooks,
    itemName = Utils.itemName,
    sortedItemIds = Utils.sortedItemIds,
    sortedIdsByName = Utils.sortedIdsByName,
    padToRight = Utils.padToRight,
    bucketAdd = Utils.bucketAdd,
    bucketSub = Utils.bucketSub,
    idQtyPayload = Utils.idQtyPayload,
  }

  local tabToggles = {}
  core.tabToggle = function(id, key, optionKey)
    local toggle = core.makeTabToggle(optionKey)
    tabToggles[id] = tabToggles[id] or {}
    tabToggles[id][key or ""] = toggle
    return toggle
  end
  
  core.isTabEnabled = function(id, key)
    local set = tabToggles[id]
    local toggle = set and (key and set[key] or set[""])
    return toggle == nil or toggle.enabled()
  end

  core.setTabEnabled = function(id, enabled, key)
    local set = tabToggles[id]
    local toggle = set and set[key or ""]
    if not toggle then return false, "unknown custom storage" end
    return toggle.setEnabled(enabled)
  end
  
  core.isTabShown = function(id, key)
    if not core.isTabEnabled(id, key) then return false end
    local ok, unlocked = pcall(Bank.CustomStorage.isEntryUnlocked, id, key, core.getLiveGame and core.getLiveGame())
    return ok and unlocked or false
  end
  
  core.entryTab = function(key, optionKey)
    local toggle = core.tabToggle(mod.id, key, optionKey)
    return { setEnabled = toggle.setEnabled, shown = function() return core.isTabShown(mod.id, key) end }
  end
  
  core.emitAction = function(key, action, eventName, payload)
    payload = payload or {}
    if eventName then mod.events:emit("mod.vrm_pokemon_bank." .. eventName, payload) end
    Bank.CustomStorage.reportAction(mod.id, key, action, payload.qty or payload.amount or 1, payload.mon or payload.id)
  end
  
  core.emitOnSuccess = function(fn, key, action, eventName, payloadFn)
    return function(...)
      local ok, err = fn(...)
      if ok then core.emitAction(key, action, eventName, payloadFn(...)) end
      return ok, err
    end
  end

  core.gridView = function(saveKey, opts)
    local function available() return not opts.available or opts.available() == true end
    local function current() return mod.save:get(saveKey) or opts.default or "grid" end
    local function isGrid() return available() and current() == "grid" end
    local function row(label, view)
      return { label = label,
        visible = function() return available() and current() ~= view end,
        onSelect = function(_, _, rebuild) mod.save:set(saveKey, view); rebuild(true) end }
    end
    return {
      isGrid = isGrid,
      columns = function() return isGrid() and opts.columns or 1 end,
      rows = { row("LIST VIEW", "list"), row("GRID VIEW", "grid") },
    }
  end
  core.BoxAccess = V.require("BoxAccess")
  local Pokemon = V.require("Pokemon").install(mod, core)
  local Moves = V.require("Moves").install(mod, core)
  core.isMovesTabEnabled = Moves.tabEnabled
  core.moveTypeOf = Moves.moveTypeOf
  core.canRelearn = Moves.canRelearn
  core.openRelearn = Moves.openRelearn
  core.moveDetailLine = Moves.moveDetailLine
  core.movePpText = Moves.movePpText
  local Items = V.require("Items").install(mod, core)
  core.pocketOf = Items.pocketOf
  core.storeHeldItem = Items.storeHeldItem
  
  core.bankTakesItems = function(game)
    if not Items.tabEnabled() then return false end
    local ok, unlocked = pcall(core.CustomStorage.isEntryUnlocked, mod.id, "items", game)
    return ok and unlocked or false
  end

  core.pocketLabel = Items.pocketLabel
  core.itemDescriptionText = Items.itemDescriptionText
  local Money = V.require("Money").install(mod, core)
  local Coins = V.require("Coins").install(mod, core)
  Stats = V.require("Stats").install(mod, core, Bank.CustomStorage)
  core.LinkEntries = V.require("LinkEntries").install(mod, Bank.CustomStorage, core)
  Lost = V.require("Lost").install(mod, core)
  local TimeCapsule = V.require("TimeCapsule").install(mod, core, Pokemon)
  local Link = V.require("Link").install(mod, core, Pokemon, Items, Money, Coins)
  do
    local hooks = Bank.hooks
    local tabs = {
      boxes = { module = Pokemon, containers = Pokemon.containers },
      timeCapsule = { module = TimeCapsule },
      items = { module = Items, containers = Items.containers },
      moves = { module = Moves, containers = Moves.containers },
      money = { module = Money },
      coins = { module = Coins },
    }
    for key, tab in pairs(tabs) do
      local screenId = tab.module.screenId
      hooks[key .. ".menuScreen"] = function(game) mod.ui.push(game, screenId) end
      if tab.containers then
        for i, container in ipairs(tab.containers) do Bank.containers[key][i] = container end
      else
        hooks[key .. ".screen"] = hooks[key .. ".menuScreen"]
      end
    end
    hooks["boxes.validate"] = Pokemon.validateStorage
    hooks["timeCapsule.validate"] = TimeCapsule.validateStorage
    hooks["items.validate"] = Items.validateStorage
    hooks["moves.validate"] = Moves.validateStorage
  end

  mod.hooks:wrap("save.write", function(next_, game)
    local proceed = next_(game)
    if proceed ~= false then
      for _, storage in ipairs(Bank.CustomStorage.listCustomStorages()) do storage.flush() end
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
    if lostMons > 0 or lostQty > 0 then parts[#parts + 1] = Strings("%d POKéMON and\n%d items were\nset aside.", lostMons, lostQty) end
    if restoredMons > 0 or restoredQty > 0 then parts[#parts + 1] = Strings("%d POKéMON and\n%d items were\nrestored.", restoredMons, restoredQty) end
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
    local all, changed = Bank.CustomStorage.validateAll(game)
    local results = all[mod.id] or {}
    local poke, capsule, items, moves = results.boxes or {}, results.timeCapsule or {}, results.items or {}, results.moves or {}
    local recoveredMoney = migrateLegacyGen2Money()
    local report = { lostMons = {}, lostItems = {}, restoredMons = {}, restoredItems = {} }
    for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
      for _, d in ipairs(core.LinkEntries.listAll(record.id)) do
        local detail = (all[record.id] or {})[d.key]
        if type(detail) == "table" then
          for field, rows in pairs(report) do
            for _, row in ipairs(type(detail[field]) == "table" and detail[field] or {}) do
              if row.id == nil and row.species == nil and row.element ~= nil then row = { id = core.LinkEntries.labelOf(game, d, row.element), count = 1, from = row.from } end
              if row.from == nil then row.from = d.label end
              rows[#rows + 1] = row
            end
          end
        end
      end
    end
    return {
      changed = changed,
      pokemon = poke,
      timeCapsule = capsule,
      items = items,
      moves = moves,
      recoveredMoney = recoveredMoney,
      report = report,
      storages = all,
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

  local gen3Ui

  mod.events:on("game.ready", function(ev)
    liveGame = ev and ev.game or liveGame
    if GameVersion.generation() == 3 then
      local ok, facade = pcall(require, "src.core.Game")
      if ok and type(facade) == "table" then liveGame = facade end
    end
  end)

  local function reportHasContent(report) return report ~= nil and (#(report.lostMons or {}) > 0 or #(report.lostItems or {}) > 0 or #(report.restoredMons or {}) > 0 or #(report.restoredItems or {}) > 0) end

  local function logLoadReport(result)
    local report = result.report or {}
    mod.log:info("Load report: %d POKéMON set aside, %d item entries set aside, %d POKéMON restored, %d item entries restored%s%s",
      #(report.lostMons or {}), #(report.lostItems or {}), #(report.restoredMons or {}), #(report.restoredItems or {}),
      (result.recoveredMoney or 0) > 0 and (", %d money recovered"):format(result.recoveredMoney) or "",
      result.changed and "" or " (nothing changed)")
    for _, mon in ipairs(report.lostMons or {}) do mod.log:info("  set aside: %s (%s)", tostring(mon.species or "?"), tostring(mon.from or "?")) end
    for _, item in ipairs(report.lostItems or {}) do mod.log:info("  item set aside: %s x%d (%s)", tostring(item.id or "?"), item.count or 1, tostring(item.from or "?")) end
    for _, mon in ipairs(report.restoredMons or {}) do mod.log:info("  restored: %s to box %d", tostring(mon.species or "?"), mon.box or 0) end
    for _, item in ipairs(report.restoredItems or {}) do mod.log:info("  item restored: %s x%d", tostring(item.id or "?"), item.count or 1) end
  end

  mod.events:on("save.loaded", function()
    local game = liveGame
    if not game then return end
    local result = validateStorage(game)
    if not result then return end
    logLoadReport(result)
    local showReport = reportHasContent(result.report)
    local recovered = (result.recoveredMoney or 0) > 0
    if gen3Ui and (showReport or recovered) then game = gen3Ui.bridgeGame(game) end
    if showReport then
      local notice = mod.options:get("quarantine_notice")
      if notice == "report" then game.stack:push(QuarantineReport.new(game, result.report))
      elseif notice == "message" then
        local summary = quarantineSummary(result.report)
        if summary ~= "" then Actions.message(game, summary) end
      end
    end
    if recovered then game.stack:push(TextBox.new(game, Strings("¥%d from an older\nBANK version was\011moved to the BANK.", result.recoveredMoney))) end
  end)

  local function confirmLinkSave(game)
    Actions.confirm(game, "Before opening the\nlink, you have to\011SAVE the game.", function(yes)
      if yes then
        Bank.markDirty()
        if game.writeSave then game:writeSave() end
        Utils.playSaveSound(game)
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
    if action.description ~= nil and type(action.description) ~= "string" then return false, "action.description must be a string" end
    local entry = { id = action.id, label = action.label, onSelect = action.onSelect, description = action.description }
    local existing = menuActionIndex[action.id]
    if existing then menuActions[existing] = entry
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

  local function openScreen(game, screen)
    if type(screen) == "function" then Bank.CustomStorage.safeCall(screen, game)
    else game.stack:push(core.entryScreen(game, screen, { counter = true })) end
    return true
  end

  local function openStorageEntryScreen(game, entry) return openScreen(game, entry.screen) end

  local function customStorageScreenEntries(record)
    local out = {}
    for _, entry in ipairs(record.entries) do
      if entry.screen and Bank.CustomStorage.isEntryUnlocked(record.id, entry.key, liveGame) then out[#out + 1] = entry end
    end
    return out
  end

  local function openCustomStorageRecord(game, entries)
    if #entries == 1 then return openStorageEntryScreen(game, entries[1]) end
    local rows = {}
    for _, entry in ipairs(entries) do rows[#rows + 1] = { label = entry.label, keepOpen = true, onSelect = function() openStorageEntryScreen(game, entry) end } end
    rows[#rows + 1] = { label = "CANCEL" }
    if gen3Ui then
      gen3Ui.openMenu(rows)
      return true
    end
    game.stack:push(Menu.new(game, rows, { tx = 0, ty = 0, tw = 12, th = #rows * 2 + 2 }))
    return true
  end

  local function storageMenuRows()
    local out = {}
    for _, record in ipairs(Bank.CustomStorage.listCustomStorages()) do
      if record.menu == "entries" then
        for _, entry in ipairs(record.entries) do
          local screen = entry.menuScreen or entry.screen
          if screen and core.isTabShown(record.id, entry.key) then out[#out + 1] = { label = entry.label, description = entry.description, open = function(game) openScreen(game, screen) end } end
        end
      elseif not menuActionIndex[record.id] and core.isTabEnabled(record.id) then
        local entries = customStorageScreenEntries(record)
        if #entries > 0 then out[#out + 1] = { label = record.name, description = record.description, open = function(game) openCustomStorageRecord(game, entries) end } end
      end
    end
    return out
  end

  local function anyBankMenuRow() return #menuActions > 0 or #storageMenuRows() > 0 end

  local function openBankMenu(game)
    local rows = {}

    local function appendRow(label, onSelect, description, keepOpen) rows[#rows + 1] = { label = label, keepOpen = keepOpen ~= false, onSelect = onSelect, description = description } end
    
    for _, row in ipairs(storageMenuRows()) do appendRow(row.label, function() row.open(game) end, row.description) end
    if Link.tabEnabled() then appendRow("LINK", function() confirmLinkSave(game) end, "Send things to another\nplayer's BANK.") end
    for _, action in ipairs(menuActions) do appendRow(action.label, function() action.onSelect(game) end, action.description) end
    if #rows == 0 then return false end
    if #rows == 1 then
      rows[1].onSelect()
      return true
    end
    appendRow("CANCEL", nil, "Go back to the\nprevious menu.", false)
    if gen3Ui then
      gen3Ui.openMenu(rows)
      return true
    end
    local maxVisible = 8
    local th = math.min(#rows, maxVisible) * 2 + 2
    game.stack:push(Menu.new(game, rows, { tx = 0, ty = 0, tw = 12, th = th, maxVisible = maxVisible }))
    return true
  end

  local function accessBank(game)
    local text = gen3Ui and "Accessed POKéMON BANK.\fShared Storage System opened." or "Accessed POKéMON\nBANK.\fAccessed Shared\nStorage System."
    game.stack:push(TextBox.new(game, text, function() openBankMenu(game) end))
  end

  local function pcMenuPosition() return mod.options:get("pc_menu_position") or "end" end

  local pcEntryEnabledByOthers = true

  local function pcEntryEnabled() return pcEntryEnabledByOthers and pcMenuPosition() ~= "none" end

  mod.hooks:wrap("ui.pc.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    if GameVersion.generation() == 2 then return out end
    if not pcEntryEnabled() then return out end
    if not anyBankMenuRow() then return out end
    local row = {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function()
        Utils.playSound(game, "Enter_PC")
        accessBank(game)
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

  -- Patched directly, gated to a Gen 2 boot, so POKéMON BANK sits as a peer of BILL's PC / PROF.OAK's PC there
  if GameVersion.generation() == 2 then
    local ok, CenterPcMenu = pcall(require, "src.ui.gen2.CenterPcMenu")
    if ok and type(CenterPcMenu) == "table" then
      local ROW_ID = "vrm_pokemon_bank"
      local origBuildEntries = CenterPcMenu.buildEntries
      CenterPcMenu.buildEntries = function(self)
        origBuildEntries(self)
        if not pcEntryEnabled() then return end
        if not anyBankMenuRow() then return end
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

  -- FireRed's PC menu has no hook either: Gen3Ui wraps its root list and runs the Bank's screens on Game3's layer stack.
  if GameVersion.generation() == 3 then
    gen3Ui = V.require("Gen3Ui").install(mod, {
      screens = ownScreens,
      label = PC_MENU_LABEL,
      position = pcMenuPosition,
      enabled = function()
        return pcEntryEnabled() and anyBankMenuRow()
      end,
      getGame = function()
        if liveGame then return liveGame end
        local ok, facade = pcall(require, "src.core.Game")
        return ok and type(facade) == "table" and facade or nil
      end,
      openBank = function(game) return accessBank(game) end,
    })
  end

  local function healBankAtCenter()
    if mod.options:get("auto_heal") ~= "center" then return end
    if liveGame then mod.exports.healBank(liveGame) end
  end

  if GameVersion.generation() == 2 then
    local ok, Specials = pcall(require, "src.script.gen2.Specials")
    if ok and type(Specials) == "table" and type(Specials.ALL) == "table" and type(Specials.ALL.HealParty) == "function" then
      local origHealParty = Specials.ALL.HealParty
      Specials.ALL.HealParty = function(vm)
        local result = origHealParty(vm)
        healBankAtCenter()
        return result
      end
    end
  else
    local ok, OverworldController = pcall(require, "src.world.OverworldController")
    if ok and type(OverworldController) == "table" and type(OverworldController.finishNurseHeal) == "function" then
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
      value = GameVersion.generation() == 2 and function() return Strings("OPEN") end or nil,
    }
    local hasMods = false
    for _, r in ipairs(out) do
      if r.label == "MODS" then hasMods = true break end
    end
    return mod.ui.insertBefore(out, hasMods and "MODS" or "BACK", row)
  end)

  if GameVersion.generation() == 3 then
    local ok, Rows = pcall(require, "src.ui.game3.option_rows")
    if ok and type(Rows) == "table" and not Rows._vrmPokemonBankHooked then
      Rows._vrmPokemonBankHooked = true
      if type(Rows.ORDER) == "table" then
        local at = #Rows.ORDER + 1
        for i, id in ipairs(Rows.ORDER) do
          if id == "vrm_pokemon_bank_data" then at = nil break end
          if id == "mods" then at = i end
        end
        if at then table.insert(Rows.ORDER, at, "vrm_pokemon_bank_data") end
      end
      local originalBuild = Rows.build
      Rows.build = function(ctx)
        local rows = originalBuild(ctx) or {}
        rows[#rows + 1] = {
          id = "vrm_pokemon_bank_data",
          label = PC_MENU_LABEL,
          value = function() return Strings("%d OPTIONS", optionsRowCount()) end,
          activate = function(c)
            if gen3Ui and c and c.game then mod.ui.push(gen3Ui.bridgeGame(c.game), SCREEN_ID) end
          end,
        }
        return rows
      end
    end
  end

  local function uiGame(game)
    if not gen3Ui or gen3Ui.isBridged(game) then return game end
    local ok, facade = pcall(require, "src.core.Game")
    return gen3Ui.bridgeGame(liveGame or (ok and type(facade) == "table" and facade) or game)
  end

  local function guarded(fn)
    return function(game, ...)
      if not game then return nil, "no game" end
      return fn(uiGame(game), ...)
    end
  end

  local function guardedPushScreen(screenId) return guarded(function(game) return mod.ui.push(game, screenId) end) end

  local function guardedOpenPicker(picker) return guarded(function(game, opts) return picker(mod, core, game, opts) end) end

  mod.exports.pcMenuLabel = PC_MENU_LABEL
  mod.exports.openPokemonMenu = guardedPushScreen(Pokemon.screenId)
  mod.exports.openTimeCapsuleMenu = guardedPushScreen(TimeCapsule.screenId)
  mod.exports.openItemsMenu = guardedPushScreen(Items.screenId)
  mod.exports.openMovesMenu = guardedPushScreen(Moves.screenId)
  mod.exports.openMoneyMenu = guardedPushScreen(Money.screenId)
  mod.exports.openBankMenu = guarded(openBankMenu)
  mod.exports.openLinkMenu = guarded(Link.open)
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
  mod.exports.listBoxes = Bank.listBoxes
  mod.exports.getStorageId = Bank.getStorageId
  mod.exports.translateSpeciesId = GenerationMap.translateSpeciesId
  mod.exports.translateItemId = GenerationMap.translateItemId
  mod.exports.translateMoveId = GenerationMap.translateMoveId
  mod.exports.flush = function()
    local was = false
    for _, storage in ipairs(Bank.CustomStorage.listCustomStorages()) do
      if storage.flush() then was = true end
    end
    return was
  end
  mod.exports.markDirty = function() Bank.markDirty() end
  mod.exports.registerOptionsPanel = registerOptionsPanel
  mod.exports.unregisterOptionsPanel = unregisterOptionsPanel
  mod.exports.registerBankMenuAction = registerBankMenuAction
  mod.exports.unregisterBankMenuAction = unregisterBankMenuAction

  local function tabToggleInsertIndex()
    local last = 0
    for i, row in ipairs(OPTION_SCHEMA) do
      if type(row.key) == "string" and row.key:match("^show_.+_tab$") then last = i end
    end
    return last + 1
  end

  local function addTabOption(optionKey, label)
    table.insert(OPTION_SCHEMA, tabToggleInsertIndex(), {
      key = optionKey,
      label = Utils.truncateName((label .. " MENU"):upper()),
      type = "toggle",
      default = true,
      onHint = "Tab shows up.",
      offHint = "Tab is hidden."
    })
  end

  mod.exports.registerCustomStorage = function(config)
    local ok, err = Bank.CustomStorage.registerCustomStorage(config)
    if not ok then return ok, err end
    local id = config.id
    if config.menu == "entries" then
      for _, entry in ipairs(config.entries) do
        local optionKey = "show_" .. id .. "_" .. entry.key .. "_tab"
        addTabOption(optionKey, entry.label)
        core.tabToggle(id, entry.key, optionKey)
      end
    else
      local optionKey = "show_" .. id .. "_tab"
      addTabOption(optionKey, config.name)
      core.tabToggle(id, nil, optionKey)
    end
    mod.options:define(OPTION_SCHEMA)
    return true
  end

  mod.exports.isCustomStorageTabEnabled = function(id, key) return core.isTabEnabled(id, key) end

  mod.exports.setCustomStorageTabEnabled = function(id, enabled, key) return core.setTabEnabled(id, enabled, key) end

  mod.exports.openCustomStorageEntry = function(game, storageId, key)
    local record = Bank.CustomStorage.getCustomStorage(storageId)
    local entry = record and record.entryIndex[key] and record.entries[record.entryIndex[key]]
    if not (game and entry and entry.screen) then return false, "no screen" end
    return openStorageEntryScreen(uiGame(game), entry)
  end

  mod.exports.listCustomStorages = Bank.CustomStorage.listCustomStorages
  mod.exports.getCustomStorage = Bank.CustomStorage.getCustomStorage
  mod.exports.getCustomStorageOrphaned = Bank.CustomStorage.getCustomStorageOrphaned
  mod.exports.setCustomStorageEntry = Bank.CustomStorage.setCustomStorageEntry
  mod.exports.getCustomStorageEntry = Bank.CustomStorage.getCustomStorageEntry
  mod.exports.listCustomStorageFiles = Bank.CustomStorage.listCustomStorageFiles
  mod.exports.isCustomStorageEntryUnlocked = Bank.CustomStorage.isEntryUnlocked
  mod.exports.Screen = Screen
  mod.exports.MultiMap = Bank.CustomStorage.MultiMap
  mod.exports.MultiArray = Bank.CustomStorage.MultiArray
  mod.exports.Map = Bank.CustomStorage.Map
  mod.exports.Array = Bank.CustomStorage.Array
  mod.exports.Single = Bank.CustomStorage.Single
  mod.exports.AmountBox = Widgets.AmountBox
  mod.exports.askQuantity = Actions.askQuantity
  mod.log:info("Pokemon Bank loaded")
end
