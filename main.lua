local STORAGE_DIR = "bank"
local STORAGE_FILE = STORAGE_DIR .. "/storage.lua"
local STORAGE_BACKUP = STORAGE_FILE .. ".bak"
local STORAGE_TMP = STORAGE_FILE .. ".tmp"
local EXPORT_FILE = STORAGE_DIR .. "/export.lua"
local EXPORT_BACKUP = EXPORT_FILE .. ".bak"
local PC_MENU_LABEL = "POKéMON BANK"
local DATA_SCREEN_ID = "PokemonBankDataOptions"

-- Every filename this mod has ever written under STORAGE_DIR. DELETE DATA (main.lua) removes the whole folder by name rather than by listing it, since the portable filesystem has no getDirectoryItems to discover them with -- only getInfo/read/write/remove/createDirectory.
local KNOWN_STORAGE_FILES = {
  "storage.lua", "storage.lua.bak", "storage.lua.tmp",
  "export.lua", "export.lua.bak",
  "stats.lua", "stats.lua.bak", "stats.lua.tmp",
}

return function(mod)
  mod.options:define({
    { key = "pc_menu_entry", label = "SHOW IN PC MENU", type = "toggle", default = true },
    { key = "pc_menu_first", label = "SHOW FIRST IN PC MENU", type = "toggle", default = false },
    { key = "show_pokemon_tab", label = "POKéMON MENU", type = "toggle", default = true },
    { key = "show_items_tab", label = "ITEMS MENU", type = "toggle", default = true },
    { key = "show_money_tab", label = "MONEY MENU", type = "toggle", default = true },
    { key = "inherit_trainer_on_withdraw", label = "INHERIT TRAINER", type = "toggle", default = false },
    { key = "auto_heal", label = "AUTO HEAL", type = "choice", default = "never",
      choices = {
        { "NEVER", "never" },
        { "ON DEPOSIT", "deposit" },
        { "ON WITHDRAW", "withdraw" },
        { "AT POKéMON CENTER", "center" },
      } },
  })
  local SaveSerializer = require("src.core.SaveSerializer")
  local SaveData = require("src.core.SaveData")
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  -- -----------------------------------------------------------------------
  -- Persistence
  -- -----------------------------------------------------------------------
  local function fs()
    return SaveData.portableFs() or love.filesystem
  end

  local function fileExists(name)
    local ok, info = pcall(function() return fs().getInfo(name) end)
    return ok and info ~= nil
  end

  local function tryRead(name)
    local ok, result = pcall(function() return fs().read(name) end)
    if ok and type(result) == "string" then return result end
    return nil
  end

  -- fs().write returns true, or false + an error message, but never throws under normal conditions; the pcall is only there for whatever an injected/headless fs might do differently.
  local function tryWrite(name, data)
    local ok, result = pcall(function() return fs().write(name, data) end)
    return ok and result ~= false
  end

  local function tryRemove(name)
    pcall(function()
      local f = fs()
      if f.remove then f.remove(name) end
    end)
  end

  local function readStorageFile(name)
    if not fileExists(name) then return nil end
    local raw = tryRead(name)
    if not raw then return nil end
    local decoded = SaveSerializer.decode(raw)
    if type(decoded) ~= "table" then return nil end
    return decoded
  end

  local STORAGE_VERSION = 3

  local function freshStorage()
    return {
      version = STORAGE_VERSION,
      boxes = { {} },
      currentBox = 1,
      items = {},
      money = 0
    }
  end

  -- Maintains the box array's one invariant after every mutation: no empty box ever sticks around except exactly one, always last -- a spare to grow into, so a deposit or a MOVE into "the next box" never has to ask permission. See API.md's Box numbering section for what this means for callers of the exported API.
  local function normalizeBoxes(s)
    local boxes = type(s.boxes) == "table" and s.boxes or {}
    local compact = {}
    for _, box in ipairs(boxes) do
      if type(box) == "table" and #box > 0 then
        compact[#compact + 1] = box
      end
    end
    compact[#compact + 1] = {} -- the one spare box, always last
    s.boxes = compact
    s.currentBox = math.max(1, math.min(#s.boxes, math.floor(tonumber(s.currentBox) or 1)))
    s.items = type(s.items) == "table" and s.items or {}
    s.money = math.max(0, math.floor(tonumber(s.money) or 0))
    
    -- Handle orphaned structure
    local orphaned = s.orphaned
    if orphaned then
      orphaned.mons = type(orphaned.mons) == "table" and orphaned.mons or {}
      orphaned.items = type(orphaned.items) == "table" and orphaned.items or {}
      for id, count in pairs(orphaned.items) do
        if not count or count <= 0 then orphaned.items[id] = nil end
      end
      -- Remove orphaned if empty (mirrors SaveData behavior)
      if #orphaned.mons == 0 and next(orphaned.items) == nil then
        s.orphaned = nil
      end
    end
  end

  local function migrateStorage(s)
    local currentVersion = tonumber(s.version) or 1
    if currentVersion >= STORAGE_VERSION then return false end
    -- Migrate from version 2 to 3: invalidPokemon/invalidItems -> orphaned
    if currentVersion < 3 then
      local orphaned = { mons = {}, items = {} }
      if type(s.invalidPokemon) == "table" then
        for _, mon in ipairs(s.invalidPokemon) do
          if type(mon) == "table" then
            orphaned.mons[#orphaned.mons + 1] = mon
          end
        end
        s.invalidPokemon = nil
      end
      if type(s.invalidItems) == "table" then
        for id, count in pairs(s.invalidItems) do
          if count and count > 0 then
            orphaned.items[id] = count
          end
        end
        s.invalidItems = nil
      end
      -- Only set orphaned if it has content
      if #orphaned.mons > 0 or next(orphaned.items) ~= nil then
        s.orphaned = orphaned
      end
    end
    s.version = STORAGE_VERSION
    return true
  end

  local storage -- in-memory cache; loaded lazily on first touch
  local dirty = false -- true when storage has mutations not yet flushed to disk

  -- Every mutator calls this instead of writing to disk directly.
  local function markDirty()
    dirty = true
  end

  -- Mirrors SaveData.load's own recovery order (source/src/core/SaveData.lua):
  -- the main file wins; a missing or corrupt one (e.g. the process died mid-write) falls back to the .tmp staging witness, then the rolling .bak. A recovered copy is only promoted back to the main filename the next time something actually flushes, not eagerly here.
  local function loadStorage()
    if storage then return storage end
    local out = readStorageFile(STORAGE_FILE)
      or readStorageFile(STORAGE_TMP)
      or readStorageFile(STORAGE_BACKUP)
    if not out then out = freshStorage() end
    local migrated = migrateStorage(out)
    normalizeBoxes(out)
    storage = out
    if migrated then markDirty() end
    return storage
  end

  -- The actual disk write, only ever called from the save.write hook below (never after a single deposit/withdraw). Mirrors SaveData.save's own backup-then-tmp-witness-then-swap discipline (see README.md's Where the data lives).
  local function flushStorage()
    if not (dirty and storage) then return end
    pcall(function() fs().createDirectory(STORAGE_DIR) end)
    local ok, encoded = pcall(SaveSerializer.encode, storage)
    if not ok then
      mod.log:warn("could not encode bank storage: %s", tostring(encoded))
      return
    end
    if fileExists(STORAGE_FILE) then
      local prev = tryRead(STORAGE_FILE)
      if prev then tryWrite(STORAGE_BACKUP, prev) end
    end
    if not tryWrite(STORAGE_TMP, encoded) then
      mod.log:warn("could not stage %s", STORAGE_TMP)
      return
    end
    tryRemove(STORAGE_FILE)
    if not tryWrite(STORAGE_FILE, encoded) then
      mod.log:warn("could not write %s", STORAGE_FILE)
      return
    end
    tryRemove(STORAGE_TMP)
    dirty = false
  end

  -- Modules require each other through V rather than package.path: a mod directory is not on it, and may live inside a mounted .love archive that plain require cannot reach. Mirrors vrm_unified_pc_system's own loader (and vrm_summary_overhaul's/vrm_battle_helper's).
  local modules = {}
  local function chunkFor(rel)
    local source = mod:read(rel)
    if not source then
      error(("vrm_pokemon_bank: %s is missing -- reinstall the mod"):format(rel), 0)
    end
    local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      error(("vrm_pokemon_bank: %s did not compile: %s"):format(rel, tostring(err)), 0)
    end
    return chunk
  end
  local V = {}
  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  local FileDialog = V.require("FileDialog")
  -- Forward-declared: installed further down (after Pokemon/Items/Money), but DATA_SCREEN_ID's VIEW STATS row and the gen1ModernUi screens table below both need to reference it before that point.
  local Stats

  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  -- EXPORT DATA/IMPORT DATA (the OPTIONS menu screen below) prefer the host's own native file dialog: the player picks exactly where the file goes, same as any other app.
  -- Where no dialog can be opened (mobile, consoles) they fall back to a fixed file next to STORAGE_FILE -- rolling any previous export into EXPORT_BACKUP first, so exporting again never loses the one before it.
  local function exportBank(game)
    loadStorage()
    local ok, encoded = pcall(SaveSerializer.encode, storage)
    if not ok then
      message(game, "Export failed.\nCouldn't encode\nthe BANK data.")
      return
    end
    if FileDialog.canDialog() then
      local path = FileDialog.chooseSave(
        "Save POKéMON BANK data", "bank_export.lua", "BANK data", "*.lua")
      if not path then return end -- the player cancelled
      if path:sub(-4):lower() ~= ".lua" then path = path .. ".lua" end
      local written, err = FileDialog.writeFile(path, encoded)
      if not written then
        message(game, "Export failed.\nCouldn't write\nthat file.")
        mod.log:warn("bank export failed: %s", tostring(err))
        return
      end
      message(game, "BANK data was\nexported.")
      return
    end
    pcall(function() fs().createDirectory(STORAGE_DIR) end)
    if fileExists(EXPORT_FILE) then
      local prev = tryRead(EXPORT_FILE)
      if prev then tryWrite(EXPORT_BACKUP, prev) end
    end
    if not tryWrite(EXPORT_FILE, encoded) then
      message(game, "Export failed.\nCouldn't write\nthe export file.")
      return
    end
    message(game, "BANK data was\nexported.")
  end

  local function applyImportedStorage(game, decoded)
    storage = decoded
    migrateStorage(storage)
    normalizeBoxes(storage)
    markDirty()
    flushStorage()
    message(game, "BANK data was\nimported.")
  end

  local function confirmImport(game, decoded)
    game.stack:push(TextBox.new(game,
      "Importing will\nreplace your\ncurrent BANK\ndata. OK?", function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if yes then applyImportedStorage(game, decoded) end
      end, { defaultNo = true }))
    end))
  end

  local function importBank(game)
    if FileDialog.canDialog() then
      local path = FileDialog.chooseOpen(
        "Choose a POKéMON BANK export", "BANK data", "*.lua")
      if not path then return end -- the player cancelled
      local raw, err = FileDialog.readFile(path)
      if not raw then
        message(game, "Import failed.\nCouldn't read\nthat file.")
        mod.log:warn("bank import failed: %s", tostring(err))
        return
      end
      local decoded = SaveSerializer.decode(raw)
      if type(decoded) ~= "table" or type(decoded.boxes) ~= "table" then
        message(game, "That file isn't a\nvalid BANK export.")
        return
      end
      confirmImport(game, decoded)
      return
    end
    if not fileExists(EXPORT_FILE) then
      message(game, "No export file\nwas found.")
      return
    end
    local raw = tryRead(EXPORT_FILE)
    local decoded = raw and SaveSerializer.decode(raw)
    if type(decoded) ~= "table" or type(decoded.boxes) ~= "table" then
      message(game, "That export file\nis invalid or\ncorrupted.")
      return
    end
    confirmImport(game, decoded)
  end

  -- Removes every file this mod is known to have written under STORAGE_DIR, then the (by then empty) folder itself -- see KNOWN_STORAGE_FILES for why this isn't a directory listing.
  local function wipeStorageDir()
    local f = fs()
    if type(f.getDirectoryItems) == "function" then
      local ok, items = pcall(f.getDirectoryItems, STORAGE_DIR)
      if ok and type(items) == "table" then
        for _, name in ipairs(items) do
          tryRemove(STORAGE_DIR .. "/" .. name)
        end
      end
    else
      for _, name in ipairs(KNOWN_STORAGE_FILES) do
        tryRemove(STORAGE_DIR .. "/" .. name)
      end
    end
    pcall(function() if f.remove then f.remove(STORAGE_DIR) end end)
  end

  local function performDelete(game)
    wipeStorageDir()
    storage = nil
    dirty = false
    Stats.reset()
    message(game, "All BANK data\nwas deleted.")
  end

  -- Double confirmation; this loses every box, every item and all the stored money in one press, with no undo.
  local function confirmDeleteBank(game)
    game.stack:push(TextBox.new(game,
      "Delete ALL BANK\ndata? POKéMON,\nITEMS and MONEY\nwill be lost.", function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if not yes then return end
        game.stack:push(TextBox.new(game,
          "Are you REALLY\nsure? This CANNOT\nbe undone.", function()
          game.stack:push(ChoiceBox.new(game, function(yesAgain)
            if yesAgain then performDelete(game) end
          end, { defaultNo = true }))
        end))
      end, { defaultNo = true }))
    end))
  end

  -- The OPTIONS submenu EXPORT/IMPORT/DELETE open into. Built on mod.ui.ListMenu -- the widget toolkit ModUI.lua calls "the stable mod-facing surface" -- rather than a hand-rolled OptionRows screen, the same way overworld_wild_spawns builds its own OPTIONS submenus (lib/settings_menus.lua): one generation-agnostic widget instead of a renderer tied to Gen 1's own OPTIONS-menu chrome.
  mod.content.screens:register(DATA_SCREEN_ID, {
    new = function(game)
      local items = {
        { label = "VIEW STATS", onSelect = function() mod.ui.push(game, Stats.screenId) end },
        { label = "EXPORT DATA", onSelect = function() exportBank(game) end },
        { label = "IMPORT DATA", onSelect = function() importBank(game) end },
        { label = "DELETE DATA", onSelect = function() confirmDeleteBank(game) end },
        { label = "CANCEL" },
      }
      return mod.ui.ListMenu.new(game, PC_MENU_LABEL, items, {
        onChoose = function(item, menu)
          if not item then return end
          if item.onSelect then
            item.onSelect()
          elseif menu and menu.close then
            menu:close()
          end
        end,
      })
    end,
  })

  -- Gen1 Modern UI reads a live ListMenu's index/scroll fields directly instead of faking D-pad presses, but the clamp-then-resync-scroll math is private to ListMenu (moveIndex/syncScroll are local there).
  -- Mirrored here so a touch/mouse action can move a live list's cursor exactly the same way a real D-pad press would, without a copy of this logic in every lib/ module.
  local function syncListScroll(list)
    local rows = list.rows or 7
    if list.index - list.scroll > rows then list.scroll = list.index - rows end
    if list.index - list.scroll < 1 then list.scroll = list.index - 1 end
  end

  local function moveListCursor(list, delta)
    local n = list.items and #list.items or 0
    if n == 0 then return end
    list.index = math.max(1, math.min(n, (list.index or 1) + delta))
    syncListScroll(list)
  end

  local function setListCursor(list, index)
    local n = list.items and #list.items or 0
    if n == 0 or index == nil then return end
    list.index = math.max(1, math.min(n, math.floor(tonumber(index) or list.index)))
    syncListScroll(list)
  end

  -- Gen1 Modern UI's row renderer reads a row's right-hand text off `value`, while every ListMenu row here carries it as `right`. Remap per row instead of passing `list.items` straight through, or ids like an item's own id would print in place of its "x5" count.
  local function publicRows(list)
    local out = {}
    for i, row in ipairs(list.items) do
      out[i] = { label = row.label, value = row.right }
    end
    return out
  end

  -- Handed to each tab's install(mod, core) instead of package-level locals, since none of loadStorage/markDirty/normalizeBoxes are reachable through require() from inside a lib/ module.
  local core = {
    loadStorage = loadStorage,
    markDirty = markDirty,
    normalizeBoxes = normalizeBoxes,
    moveListCursor = moveListCursor,
    setListCursor = setListCursor,
    publicRows = publicRows,
    fs = fs,
    fileExists = fileExists,
    tryRead = tryRead,
    tryWrite = tryWrite,
    tryRemove = tryRemove,
    STORAGE_DIR = STORAGE_DIR,
  }

  local Pokemon = V.require("Pokemon").install(mod, core)
  local Items = V.require("Items").install(mod, core)
  local Money = V.require("Money").install(mod, core)
  Stats = V.require("Stats").install(mod, core)

  mod.hooks:wrap("save.write", function(next_, game)
    local proceed = next_(game)
    if proceed ~= false then
      flushStorage()
      Stats.flush()
    end
    return proceed
  end)

  local QuarantineReport = require("src.ui.QuarantineReport")

  local function migrateLegacyGen2Money(game)
    if GameVersion.generation() ~= 2 then return 0 end
    local save = game and game.save
    if not save or save.money == nil then return 0 end
    local amount = math.max(0, math.floor(tonumber(save.money) or 0))
    save.money = nil
    if amount > 0 then mod.exports.depositMoney(amount) end
    return amount
  end

  local function validateBankStorage(game)
    if not (game and game.data) then return nil end
    loadStorage()
    local poke = Pokemon.validateStorage(game)
    local items = Items.validateStorage(game)
    local recoveredMoney = migrateLegacyGen2Money(game)
    local changed = poke.changed or items.changed
    if changed then markDirty() end
    -- lostItems merges both sources: a Pokémon's held item quarantined by Pokemon.validateStorage (an invalid mon.item) and a bank-item stack quarantined by Items.validateStorage -- both land in the same orphaned.items, so one combined list is what a player actually sees.
    local lostItems = {}
    for _, item in ipairs(poke.lostItems or {}) do lostItems[#lostItems + 1] = item end
    for _, item in ipairs(items.lostItems or {}) do lostItems[#lostItems + 1] = item end
    return {
      changed = changed,
      pokemon = poke,
      items = items,
      recoveredMoney = recoveredMoney,
      report = {
        lostMons = poke.lostMons or {},
        lostItems = lostItems,
        restoredMons = poke.restoredMons or {},
        restoredItems = items.restoredItems or {}
      }
    }
  end

  mod.exports.validateStorage = validateBankStorage

  -- =========================================================================
  -- Gen1 Modern UI compatibility (optional, soft dependency)
  -- =========================================================================
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
      match = function(state)
        return type(state) == "table" and state.screenId == id
          and type(state.gen1ModernUi) == "table"
      end,
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
      [Pokemon.transferBoxScreenId] = externalScreen(Pokemon.transferBoxScreenId,
        { "up", "down", "left", "right", "select", "back", "start", "hover" }),
      [Pokemon.moveScreenId] = externalScreen(Pokemon.moveScreenId,
        { "up", "down", "left", "right", "select", "back", "start", "hover" }),
      [Items.moveItemsScreenId] = externalScreen(Items.moveItemsScreenId,
        { "up", "down", "select", "back", "start", "hover" }),
      [Money.amountScreenId] = externalScreen(Money.amountScreenId,
        { "up", "down", "left", "right", "select", "back", "start" }),
    },
  }

  local modernUiRegistered = false
  local function registerModernUiAdapter()
    if modernUiRegistered then return end
    local host = mod.find and mod.find("gen1_modern_ui")
    if not (host and host.exports and type(host.exports.registerAdapter) == "function") then
      return
    end
    local ok = pcall(host.exports.registerAdapter,
      { owner = mod.id, contract = mod.exports.gen1ModernUi })
    if ok then modernUiRegistered = true end
  end

  mod.events:on("game.ready", function() pcall(registerModernUiAdapter) end)

  local liveGame
  mod.events:on("game.ready", function(ev)
    liveGame = ev and ev.game or liveGame
  end)

  mod.events:on("save.loaded", function()
    local game = liveGame
    if not game then return end
    local result = validateBankStorage(game)
    if result and result.report and result.changed then
      game.stack:push(QuarantineReport.new(game, result.report))
    end
    if result and result.recoveredMoney and result.recoveredMoney > 0 then
      game.stack:push(TextBox.new(game,
        Strings("¥%d from an older\nBANK version was\nmoved to the BANK.", result.recoveredMoney)))
    end
  end)

  -- Entry point: a row on the PC's main menu opening a small POKéMON / ITEMS / MONEY chooser.
  -- With two or three tabs enabled, opens a chooser listing just the enabled ones. With only one enabled, skips the chooser and opens that tab directly. Never called with none enabled.
  local function openBankMenu(game)
    local pokeOn, itemsOn, moneyOn = Pokemon.tabEnabled(), Items.tabEnabled(), Money.tabEnabled()
    local rows = {}
    if pokeOn then rows[#rows + 1] = { label = "POKéMON", onSelect = function() mod.ui.push(game, Pokemon.screenId) end } end
    if itemsOn then rows[#rows + 1] = { label = "ITEMS", onSelect = function() mod.ui.push(game, Items.screenId) end } end
    if moneyOn then rows[#rows + 1] = { label = "MONEY", onSelect = function() mod.ui.push(game, Money.screenId) end } end
    if #rows == 0 then return end
    if #rows == 1 then
      rows[1].onSelect()
      return
    end
    rows[#rows + 1] = { label = "CANCEL" }
    local th = #rows * 2 + 2
    game.stack:push(Menu.new(game, rows, { tx = 8, ty = 18 - th, tw = 12, th = th }))
  end

  -- Another mod can veto the row outright through setPcEntryEnabled(false) (see exports below) -- checked independently of, and in addition to, the player's own SHOW IN PC MENU option.
  local pcEntryEnabledByOthers = true

  local function pcEntryEnabled()
    return pcEntryEnabledByOthers and mod.options:get("pc_menu_entry") == true
  end

  mod.hooks:wrap("ui.pc.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    -- On Gold this hook fires on two different, already-nested screens (BILL's PC's own box menu, and the player's item PC).
    -- Gold gets the row through the direct CenterPcMenu patch below instead, which is the only place it should appear there -- see that patch's own comment.
    if GameVersion.generation() == 2 then return out end
    if not pcEntryEnabled() then return out end
    -- Nothing to open with every tab off -- drop the row instead of showing an empty chooser (or a chooser with nothing behind it).
    if not (Pokemon.tabEnabled() or Items.tabEnabled() or Money.tabEnabled()) then return out end
    -- keepOpen mirrors every other row already on this menu, so B in the chooser above returns to the PC menu instead of logging off.
    local row = {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function() openBankMenu(game) end,
    }
    if mod.options:get("pc_menu_first") == true then
      table.insert(out, 1, row)
      return out
    end
    return mod.ui.insertBefore(out, "PROF.OAK's PC", row)
  end)

  -- Gold's Pokémon Center PC selector has no hook of its own -- ui.pc.items above fires one level deeper there (Bill's own box menu, or the player's item PC), never on this top screen.
  -- Patched directly, gated to a Gen 2 boot, so POKéMON BANK sits as a peer of BILL's PC / PROF.OAK's PC there -- CenterPcMenu is not one of Gen2Compat's served facades, so this is real engine-internals surgery, not an adapter call.
  if GameVersion.generation() == 2 then
    local ok, CenterPcMenu = pcall(require, "src.ui.gen2.CenterPcMenu")
    if ok and type(CenterPcMenu) == "table" then
      local ROW_ID = "vrm_pokemon_bank"
      local origBuildEntries = CenterPcMenu.buildEntries
      CenterPcMenu.buildEntries = function(self)
        origBuildEntries(self)
        if not pcEntryEnabled() then return end
        if not (Pokemon.tabEnabled() or Items.tabEnabled() or Money.tabEnabled()) then return end
        local entries = self.entries
        local row = { id = ROW_ID, label = PC_MENU_LABEL }
        if mod.options:get("pc_menu_first") == true then
          table.insert(entries, 1, row)
          return
        end
        -- Ahead of TURN OFF, which CenterPcMenu:buildEntries always appends last.
        local pos = #entries + 1
        for i, e in ipairs(entries) do
          if e.id == "turnoff" then pos = i break end
        end
        table.insert(entries, pos, row)
      end
      local origChoose = CenterPcMenu.choose
      CenterPcMenu.choose = function(self)
        local entry = self.entries[self.index]
        if entry and entry.id == ROW_ID then
          self:playSfx("Sfx_ChoosePcOption")
          openBankMenu(self.game)
          return
        end
        return origChoose(self)
      end
    end
  end

  -- AUTO HEAL's "center" choice: heals the whole Bank the moment the game's own Pokémon Center heal actually happens. Real engine-internals surgery, gated per generation.
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

  -- A second entry point, independent of SHOW IN PC MENU/pcEntryEnabled above: EXPORT/IMPORT/DELETE are maintenance actions on the Bank's own file, not something a run needs a PC for, so they sit on the game's OPTIONS menu instead of behind it. ui.options.rows carries the same name and (game, rows) shape on both generations (source/docs/preparing-your-mod-for-gen2.md), so one hook reaches Red/Blue/Yellow's OPTIONS and Gold's alike.
  mod.hooks:wrap("ui.options.rows", function(next_, game, rows)
    local out = next_(game, rows)
    if type(out) ~= "table" then return out end
    local row = {
      id = "vrm_pokemon_bank_data",
      label = PC_MENU_LABEL,
      activate = function(g) mod.ui.push(g, DATA_SCREEN_ID) end,
    }
    local hasMods = false
    for _, r in ipairs(out) do
      if r.label == "MODS" then hasMods = true break end
    end
    -- Anchored on MODS where it exists (Red/Blue/Yellow); Gold's OPTIONS menu has no MODS row at all, but it does carry its own CANCEL inside `rows` (Gen 1's CANCEL is appended after the hook instead) -- insertBefore's own fallback would otherwise drop the row after CANCEL there, so this anchors on CANCEL instead.
    return mod.ui.insertBefore(out, hasMods and "MODS" or "CANCEL", row)
  end)

  mod.exports.open = function(game, tab)
    if not game then return nil, "no game" end
    if tab == "items" then return mod.ui.push(game, Items.screenId) end
    if tab == "money" then return mod.ui.push(game, Money.screenId) end
    return mod.ui.push(game, Pokemon.screenId)
  end

  mod.exports.setPcEntryEnabled = function(enabled)
    pcEntryEnabledByOthers = enabled ~= false
    return true
  end
  mod.exports.pcMenuLabel = PC_MENU_LABEL

  mod.exports.isPcEntryEnabled = function() return pcEntryEnabled() end

  mod.exports.flush = function()
    local was = dirty or Stats.isDirty()
    flushStorage()
    Stats.flush()
    return was
  end

  mod.log:info("Pokemon Bank loaded")
end
