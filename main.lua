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

local OPTION_SCHEMA = {
  { key = "pc_menu_position", label = "SHOW IN PC MENU", type = "choice", default = "end",
    choices = {
      { "NONE", "none" },
      { "START", "start" },
      { "MIDDLE", "middle" },
      { "END", "end" },
    } },
  { key = "show_pokemon_tab", label = "POKéMON MENU", type = "toggle", default = true },
  { key = "show_items_tab", label = "ITEMS MENU", type = "toggle", default = true },
  { key = "show_moves_tab", label = "MOVES MENU", type = "toggle", default = true },
  { key = "show_money_tab", label = "MONEY MENU", type = "toggle", default = true },
  { key = "inherit_trainer_on_withdraw", label = "INHERIT TRAINER", type = "toggle", default = false },
  { key = "auto_heal", label = "AUTO HEAL", type = "choice", default = "never",
    choices = {
      { "NEVER", "never" },
      { "ON DEPOSIT", "deposit" },
      { "ON WITHDRAW", "withdraw" },
      { "AT POKéMON CENTER", "center" },
    } },
  { key = "quarantine_notice", label = "LOAD REPORT", type = "choice", default = "report",
    choices = {
      { "NONE", "none" },
      { "MESSAGE", "message" },
      { "REPORT", "report" },
    } },
}

return function(mod)
  mod.options:define(OPTION_SCHEMA)
  local SaveSerializer = require("src.core.SaveSerializer")
  local SaveData = require("src.core.SaveData")
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local GameVersion = require("src.core.GameVersion")
  local Strings = require("src.core.Strings")
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local QuantityBox = require("src.ui.QuantityBox")

  local function truncateName(name, maxLen)
    maxLen = maxLen or 12
    name = tostring(name)
    local spans = Font.split(name)
    if #spans <= maxLen then return name end
    local cut = name:sub(1, spans[maxLen - 1].to):gsub("%s+$", "")
    return cut .. "…"
  end

  -- SaveData.persistenceFs: the mod's own love facade blocks .filesystem, but this resolves the same standard/portable backend from inside the engine, where that block doesn't apply.
  local function fs()
    return SaveData.persistenceFs()
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

  local STORAGE_VERSION = 4

  local function freshStorage()
    return {
      version = STORAGE_VERSION,
      boxes = { {} },
      currentBox = 1,
      items = {},
      moves = {},
      money = 0,
    }
  end

  local function ensureOrphaned(s)
    if not s.orphaned then
      s.orphaned = { mons = {}, items = {}, moves = {}, monMoves = {} }
    end
    s.orphaned.mons = type(s.orphaned.mons) == "table" and s.orphaned.mons or {}
    s.orphaned.items = type(s.orphaned.items) == "table" and s.orphaned.items or {}
    s.orphaned.moves = type(s.orphaned.moves) == "table" and s.orphaned.moves or {}
    s.orphaned.monMoves = type(s.orphaned.monMoves) == "table" and s.orphaned.monMoves or {}
    return s.orphaned
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
    s.moves = type(s.moves) == "table" and s.moves or {}
    s.money = math.max(0, math.floor(tonumber(s.money) or 0))

    if s.orphaned then
      ensureOrphaned(s)
      local orphaned = s.orphaned
      for id, count in pairs(orphaned.items) do
        if not count or count <= 0 then orphaned.items[id] = nil end
      end
      for id, count in pairs(orphaned.moves) do
        if not count or count <= 0 then orphaned.moves[id] = nil end
      end
      for bankId, moves in pairs(orphaned.monMoves) do
        if type(moves) ~= "table" or #moves == 0 then orphaned.monMoves[bankId] = nil end
      end
      -- Remove orphaned if empty (mirrors SaveData behavior)
      if #orphaned.mons == 0 and next(orphaned.items) == nil and next(orphaned.moves) == nil and next(orphaned.monMoves) == nil then
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
  local Pickers = V.require("Pickers")
  -- Forward-declared: installed further down (after Pokemon/Items/Money), but DATA_SCREEN_ID's VIEW STATS/VIEW LOST rows and the gen1ModernUi screens table below both need to reference them before that point.
  local Stats
  local Lost

  local function message(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  -- EXPORT DATA/IMPORT DATA (the OPTIONS menu screen below) would prefer the host's own native file dialog, but FileDialog.canDialog() is always false under the mod sandbox (no io, no love.system) -- see FileDialog.lua's own header. They always take the fixed-file path below: a file next to STORAGE_FILE, rolling any previous export into EXPORT_BACKUP first so exporting again never loses the one before it.
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

  local function optionValueText(schemaRow)
    if schemaRow.type == "toggle" then
      return mod.options:get(schemaRow.key) and "ON" or "OFF"
    end
    local cur = mod.options:get(schemaRow.key)
    for _, choice in ipairs(schemaRow.choices or {}) do
      if choice[2] == cur then return choice[1] end
    end
    local first = (schemaRow.choices or {})[1]
    return first and first[1] or "----"
  end

  local function setModOption(game, key, value)
    local save = game.save
    if save and save.options then
      save.options.modOptions = save.options.modOptions or {}
      local t = save.options.modOptions
      t[mod.id] = t[mod.id] or {}
      t[mod.id][key] = value
    end
    local loader = game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id][key] = value
      if loader.events then
        loader.events:emit("mod.options_changed", { mod = mod.id, key = key, value = value })
      end
    end
    if game.writeOptions then pcall(game.writeOptions, game) end
  end

  local function cycleOptionValue(game, schemaRow)
    if schemaRow.type == "toggle" then
      setModOption(game, schemaRow.key, not mod.options:get(schemaRow.key))
      return
    end
    local choices = schemaRow.choices or {}
    if #choices == 0 then return end
    local cur = mod.options:get(schemaRow.key)
    local index = 1
    for i, choice in ipairs(choices) do
      if choice[2] == cur then index = i break end
    end
    index = (index % #choices) + 1
    setModOption(game, schemaRow.key, choices[index][2])
  end

  local function buildOptionRows()
    local rows = {}
    for _, schemaRow in ipairs(OPTION_SCHEMA) do
      if schemaRow.type == "toggle" or schemaRow.type == "choice" then
        rows[#rows + 1] = { label = truncateName(schemaRow.label), right = optionValueText(schemaRow), schema = schemaRow }
      end
    end
    return rows
  end

  -- The OPTIONS submenu holding this mod's own settings, above VIEW STATS/EXPORT/IMPORT/DELETE. Built on mod.ui.ListMenu -- the widget toolkit ModUI.lua calls "the stable mod-facing surface" -- rather than a hand-rolled OptionRows screen, the same way overworld_wild_spawns builds its own OPTIONS submenus (lib/settings_menus.lua): one generation-agnostic widget instead of a renderer tied to Gen 1's own OPTIONS-menu chrome. That does mean A cycles a value here instead of Left/Right stepping it the way the real OPTIONS menu's own rows do -- ListMenu has no stepper of its own to borrow.
  mod.content.screens:register(DATA_SCREEN_ID, {
    new = function(game)
      local list
      local function rebuildItems()
        local items = buildOptionRows()
        items[#items + 1] = { label = "VIEW STATS", onSelect = function() mod.ui.push(game, Stats.screenId) end }
        items[#items + 1] = { label = "VIEW LOST", onSelect = function() mod.ui.push(game, Lost.screenId) end }
        -- items[#items + 1] = { label = "EXPORT DATA", onSelect = function() exportBank(game) end }
        -- items[#items + 1] = { label = "IMPORT DATA", onSelect = function() importBank(game) end }
        items[#items + 1] = { label = "DELETE DATA", onSelect = function() confirmDeleteBank(game) end }
        items[#items + 1] = { label = "CANCEL" }
        return items
      end
      list = mod.ui.ListMenu.new(game, PC_MENU_LABEL, rebuildItems(), {
        wrap = true,
        onChoose = function(item, menu)
          if not item then return end
          if item.schema then
            cycleOptionValue(game, item.schema)
            local index = menu.index
            menu.items = rebuildItems()
            menu.index = index
          elseif item.onSelect then
            item.onSelect()
          elseif menu and menu.close then
            menu:close()
          end
        end,
      })
      return list
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

  -- Clamps a browser's own {bankBox, pcBox} state after the Bank's own box count (or a resize elsewhere) may have moved -- shared by every BANK/PC box browser in lib/Pokemon.lua and lib/Pickers.lua so the clamp exists once. pcBoxCount is the caller's own Boxes.COUNT, passed in rather than required here to avoid a new dependency on src.pokemon.Boxes from main.lua.
  local function clampBoxState(state, loadStorage, pcBoxCount)
    local st = loadStorage()
    state.bankBox = math.max(1, math.min(#st.boxes, state.bankBox))
    state.pcBox = math.max(1, math.min(pcBoxCount, state.pcBox))
  end

  -- Whatever pressing A on a ListMenu-driven screen's highlighted row would do -- shared by every gen1ModernUi "select" action across lib/Pokemon.lua, lib/Items.lua and lib/Pickers.lua. An empty list mirrors ListMenu:update's own empty-list branch (A closes exactly like B), via onEmpty -- what "close" means differs per screen (some pop the stack outright, some also run opts.onCancel).
  local function chooseListCurrent(list, onEmpty)
    if #list.items == 0 then
      onEmpty()
      return
    end
    local item = list.items[list.index]
    if item and list.onChoose then list.onChoose(item, list) end
  end

  -- The part of a gen1ModernUi surface identical across every ListMenu-driven screen in this mod -- rows/index/scroll/footer/up/down/hover all just read or move `list`. title/left/right/select/back/start are each screen's own and go in `actions`. getList returns the screen's current list rather than the table itself, since every screen below rebuilds (and reassigns) it on view/box changes.
  local function gen1ModernUiListAdapter(getList, actions)
    local surface = {
      rows = function() return publicRows(getList()) end,
      index = function() return getList().index end,
      scroll = function() return getList().scroll end,
      footer = function() return getList().footer end,
      up = function() moveListCursor(getList(), -1) end,
      down = function() moveListCursor(getList(), 1) end,
      hover = function(payload) setListCursor(getList(), payload) end,
    }
    for k, v in pairs(actions) do surface[k] = v end
    return surface
  end

  local function playSound(game, name)
    pcall(function() require("src.core.Sound").play(game.data, name) end)
  end

  local function itemName(game, id)
    local def = game.data.items[id]
    return def and def.name or id
  end

  -- Sorts ids by display name, optionally filtered -- shared by main.lua's own sortedItemIds and lib/Moves.lua's sortedMoveIds, which differ only in which name lookup and whether a filter applies.
  local function sortedIdsByName(nameFn, counts, filter)
    local ids = {}
    for id, count in pairs(counts) do
      if count and count > 0 and (not filter or filter(id)) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return nameFn(a) < nameFn(b) end)
    return ids
  end

  local function sortedItemIds(game, counts)
    return sortedIdsByName(function(id) return itemName(game, id) end, counts)
  end

  local function askQuantity(game, list, count, cb)
    list.footer = "How many?"
    game.stack:push(QuantityBox.new(game, {
      max = count,
      onDone = function(qty)
        if qty then cb(qty) else list.footer = nil end
      end,
    }))
  end

  -- Level icon for a mon-list ListMenu row: ListMenu just draws item.label as plain text, and embedding " :L" in it renders as a literal colon and L, not the level tile -- only a direct HudTiles.tile(0x6E, ...) draws it reliably, the same way PartyMenu.lua's own party rows do. `gap` is the blank space (px) between the name and the tile, one glyph (8) by default; Pickers.lua's own picker passes 0, trading it for width its rowRight column needs more.
  local function attachLevelIcons(list, mons, gap)
    gap = gap or 8
    local origDraw = list.draw
    function list:draw()
      origDraw(self)
      love.graphics.setColor(0, 0, 0, 1)
      for row = 1, self.rows do
        local item = self.items[self.scroll + row]
        local mon = item and mons[self.scroll + row]
        if mon then
          local y = 8 + row * 16
          local x = 16 + Font.width(item.label) + gap
          HudTiles.tile(0x6E, x, y)
          Font.draw(tostring(mon.level), x + 8, y)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local function monName(game, mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or mon.name or (def and def.name) or tostring(mon.species)
  end

  -- A move slot's own id, whichever shape it's stored in: a plain string in most tables, or `{ id = ..., pp = ... }` on a mon's own moves/orphaned.monMoves entries. Shared by lib/Pokemon.lua and lib/Moves.lua.
  local function moveEntryId(mv)
    return type(mv) == "table" and mv.id or mv
  end

  local function makeTabToggle(optionKey)
    local enabledByOthers = true
    local function enabled()
      return enabledByOthers and mod.options:get(optionKey) == true
    end
    local function setEnabled(value)
      enabledByOthers = value ~= false
      return true
    end
    return { enabled = enabled, setEnabled = setEnabled }
  end

  -- Handed to each tab's install(mod, core) instead of package-level locals, since none of loadStorage/markDirty/normalizeBoxes are reachable through require() from inside a lib/ module.
  local core = {
    loadStorage = loadStorage,
    markDirty = markDirty,
    normalizeBoxes = normalizeBoxes,
    ensureOrphaned = ensureOrphaned,
    moveListCursor = moveListCursor,
    setListCursor = setListCursor,
    publicRows = publicRows,
    message = message,
    playSound = playSound,
    itemName = itemName,
    sortedItemIds = sortedItemIds,
    sortedIdsByName = sortedIdsByName,
    clampBoxState = clampBoxState,
    chooseListCurrent = chooseListCurrent,
    gen1ModernUiListAdapter = gen1ModernUiListAdapter,
    moveEntryId = moveEntryId,
    askQuantity = askQuantity,
    attachLevelIcons = attachLevelIcons,
    monName = monName,
    makeTabToggle = makeTabToggle,
    fs = fs,
    fileExists = fileExists,
    tryRead = tryRead,
    tryWrite = tryWrite,
    tryRemove = tryRemove,
    STORAGE_DIR = STORAGE_DIR,
    truncateName = truncateName,
  }

  local Pokemon = V.require("Pokemon").install(mod, core)
  local Moves = V.require("Moves").install(mod, core)
  core.isMovesTabEnabled = Moves.tabEnabled
  local Items = V.require("Items").install(mod, core)
  local Money = V.require("Money").install(mod, core)
  Stats = V.require("Stats").install(mod, core)
  Lost = V.require("Lost").install(mod, core)

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
    return table.concat(parts, "\n\n")
  end

  local function validateBankStorage(game)
    if not (game and game.data) then return nil end
    loadStorage()
    local poke = Pokemon.validateStorage(game)
    local items = Items.validateStorage(game)
    local moves = Moves.validateStorage(game)
    local recoveredMoney = migrateLegacyGen2Money(game)
    local changed = poke.changed or items.changed or moves.changed
    if changed then markDirty() end
    -- lostItems merges every source: a Pokémon's held item quarantined by Pokemon.validateStorage (an invalid mon.item), a bank-item stack quarantined by Items.validateStorage, and a banked TM use quarantined by Moves.validateStorage (a move the active game can no longer turn back into a TM) -- all land in the same orphaned tables, so one combined list is what a player actually sees.
    local lostItems = {}
    for _, item in ipairs(poke.lostItems or {}) do lostItems[#lostItems + 1] = item end
    for _, item in ipairs(items.lostItems or {}) do lostItems[#lostItems + 1] = item end
    for _, item in ipairs(moves.lostItems or {}) do lostItems[#lostItems + 1] = item end
    local restoredItems = {}
    for _, item in ipairs(items.restoredItems or {}) do restoredItems[#restoredItems + 1] = item end
    for _, item in ipairs(moves.restoredItems or {}) do restoredItems[#restoredItems + 1] = item end
    return {
      changed = changed,
      pokemon = poke,
      items = items,
      moves = moves,
      recoveredMoney = recoveredMoney,
      report = {
        lostMons = poke.lostMons or {},
        lostItems = lostItems,
        restoredMons = poke.restoredMons or {},
        restoredItems = restoredItems
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
      [Pickers.MON_PICKER_SCREEN_ID] = externalScreen(Pickers.MON_PICKER_SCREEN_ID,
        { "up", "down", "left", "right", "select", "back", "start", "hover" }),
      [Pickers.ITEM_PICKER_SCREEN_ID] = externalScreen(Pickers.ITEM_PICKER_SCREEN_ID,
        { "up", "down", "select", "back", "start", "hover" }),
      [Pickers.BOX_PICKER_SCREEN_ID] = externalScreen(Pickers.BOX_PICKER_SCREEN_ID,
        { "up", "down", "left", "right", "select", "back", "start", "hover" }),
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

  mod.events:on("game.ready", registerModernUiAdapter)

  local liveGame
  mod.events:on("game.ready", function(ev)
    liveGame = ev and ev.game or liveGame
  end)

  mod.events:on("save.loaded", function()
    local game = liveGame
    if not game then return end
    local result = validateBankStorage(game)
    if result and result.report and result.changed then
      local notice = mod.options:get("quarantine_notice")
      if notice == "report" then
        game.stack:push(QuarantineReport.new(game, result.report))
      elseif notice == "message" then
        local summary = quarantineSummary(result.report)
        if summary ~= "" then message(game, summary) end
      end
    end
    if result and result.recoveredMoney and result.recoveredMoney > 0 then
      game.stack:push(TextBox.new(game,
        Strings("¥%d from an older\nBANK version was\nmoved to the BANK.", result.recoveredMoney)))
    end
  end)

  -- Entry point: a row on the PC's main menu opening a small POKéMON / ITEMS / MOVES / MONEY chooser.
  -- With two or more tabs enabled, opens a chooser listing just the enabled ones. With only one enabled, skips the chooser and opens that tab directly. Never called with none enabled. Returns true when it opened something (the chooser or, with just one tab on, that tab directly), false when every tab was off and there was nothing to open -- mod.exports.openBankMenu below just forwards this.
  local function openBankMenu(game)
    local pokeOn, itemsOn, movesOn, moneyOn = Pokemon.tabEnabled(), Items.tabEnabled(), Moves.tabEnabled(), Money.tabEnabled()
    local rows = {}
    if pokeOn then rows[#rows + 1] = { label = "POKéMON", onSelect = function() mod.ui.push(game, Pokemon.screenId) end } end
    if itemsOn then rows[#rows + 1] = { label = "ITEMS", onSelect = function() mod.ui.push(game, Items.screenId) end } end
    if movesOn then rows[#rows + 1] = { label = "MOVES", onSelect = function() mod.ui.push(game, Moves.screenId) end } end
    if moneyOn then rows[#rows + 1] = { label = "MONEY", onSelect = function() mod.ui.push(game, Money.screenId) end } end
    if #rows == 0 then return false end
    if #rows == 1 then
      rows[1].onSelect()
      return true
    end
    rows[#rows + 1] = { label = "CANCEL" }
    local th = #rows * 2 + 2
    game.stack:push(Menu.new(game, rows, { tx = 8, ty = 18 - th, tw = 12, th = th }))
    return true
  end

  -- Another mod can veto the row outright through setPcEntryEnabled(false) (see exports below) -- checked independently of, and in addition to, the player's own SHOW IN PC MENU option.
  local pcEntryEnabledByOthers = true

  local function pcMenuPosition()
    return mod.options:get("pc_menu_position") or "end"
  end

  local function pcEntryEnabled()
    return pcEntryEnabledByOthers and pcMenuPosition() ~= "none"
  end

  -- BILL's/SOMEONE's PC is always the first row OverworldState:openPC builds, before any hook runs -- but its label flips on EVENT_MET_BILL, so MIDDLE below has to check for either instead of a single anchor.
  local function billsPcIndex(items)
    for i, item in ipairs(items) do
      if item.label == "BILL'S PC" or item.label == Strings("SOMEONE'S PC") then return i end
    end
    return nil
  end

  mod.hooks:wrap("ui.pc.items", function(next_, game, items)
    local out = next_(game, items)
    if type(out) ~= "table" then return out end
    -- On Gold this hook fires on two different, already-nested screens (BILL's PC's own box menu, and the player's item PC).
    -- Gold gets the row through the direct CenterPcMenu patch below instead, which is the only place it should appear there -- see that patch's own comment.
    if GameVersion.generation() == 2 then return out end
    if not pcEntryEnabled() then return out end
    -- Nothing to open with every tab off -- drop the row instead of showing an empty chooser (or a chooser with nothing behind it).
    if not (Pokemon.tabEnabled() or Items.tabEnabled() or Moves.tabEnabled() or Money.tabEnabled()) then return out end
    -- keepOpen mirrors every other row already on this menu, so B in the chooser above returns to the PC menu instead of logging off.
    -- Sound.play("Enter_PC") matches BILL's/the player's/PROF.OAK's own rows (OverworldState:openPC), which each play it before pushing their own screen -- without it, this row was the only one on the menu that opened silently.
    local row = {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function()
        playSound(game, "Enter_PC")
        openBankMenu(game)
      end,
    }
    local position = pcMenuPosition()
    if position == "start" then
      table.insert(out, 1, row)
      return out
    end
    if position == "middle" then
      local i = billsPcIndex(out)
      table.insert(out, i and (i + 1) or (#out + 1), row)
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
        if not (Pokemon.tabEnabled() or Items.tabEnabled() or Moves.tabEnabled() or Money.tabEnabled()) then return end
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

  mod.exports.openPokemonMenu = function(game)
    if not game then return nil, "no game" end
    return mod.ui.push(game, Pokemon.screenId)
  end

  mod.exports.openItemsMenu = function(game)
    if not game then return nil, "no game" end
    return mod.ui.push(game, Items.screenId)
  end

  mod.exports.openMovesMenu = function(game)
    if not game then return nil, "no game" end
    return mod.ui.push(game, Moves.screenId)
  end

  mod.exports.openMoneyMenu = function(game)
    if not game then return nil, "no game" end
    return mod.ui.push(game, Money.screenId)
  end

  mod.exports.openBankMenu = function(game)
    if not game then return nil, "no game" end
    return openBankMenu(game)
  end

  mod.exports.open = function(game, tab)
    if not game then return nil, "no game" end
    if tab == "items" then return mod.exports.openItemsMenu(game) end
    if tab == "moves" then return mod.exports.openMovesMenu(game) end
    if tab == "money" then return mod.exports.openMoneyMenu(game) end
    return mod.exports.openPokemonMenu(game)
  end

  mod.exports.openPokemonPicker = function(game, opts)
    if not game then return nil, "no game" end
    return Pickers.openMonPicker(mod, core, game, opts)
  end

  mod.exports.openMovePicker = function(game, opts)
    if not game then return nil, "no game" end
    return Pickers.openMovePicker(mod, core, game, opts)
  end

  mod.exports.openItemPicker = function(game, opts)
    if not game then return nil, "no game" end
    return Pickers.openItemPicker(mod, core, game, opts)
  end

  mod.exports.openBoxPicker = function(game, opts)
    if not game then return nil, "no game" end
    return Pickers.openBoxPicker(mod, core, game, opts)
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
