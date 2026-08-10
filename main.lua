local STORAGE_DIR = "bank"
local STORAGE_FILE = STORAGE_DIR .. "/storage.lua"
local STORAGE_BACKUP = STORAGE_FILE .. ".bak"
local STORAGE_TMP = STORAGE_FILE .. ".tmp"
local PC_MENU_LABEL = "POKéMON BANK"

return function(mod)
  mod.options:define({
    { key = "pc_menu_entry", label = "SHOW IN PC MENU", type = "toggle", default = true },
    { key = "show_pokemon_tab", label = "POKéMON MENU", type = "toggle", default = true },
    { key = "show_items_tab", label = "ITEMS MENU", type = "toggle", default = true },
    { key = "show_money_tab", label = "MONEY MENU", type = "toggle", default = true },
  })
  local SaveSerializer = require("src.core.SaveSerializer")
  local SaveData = require("src.core.SaveData")
  local Menu = require("src.ui.Menu")
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

  -- Ties the Bank's own disk write to the game's. A veto earlier in the save.write chain (an ephemeral tool session, source/docs/modding.md) means the save itself won't happen, so the Bank doesn't flush either.
  mod.hooks:wrap("save.write", function(next_, game)
    local proceed = next_(game)
    if proceed ~= false then
      flushStorage()
    end
    return proceed
  end)

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

  -- Handed to each tab's install(mod, core) instead of package-level locals, since none of loadStorage/markDirty/normalizeBoxes are reachable through require() from inside a lib/ module.
  local core = {
    loadStorage = loadStorage,
    markDirty = markDirty,
    normalizeBoxes = normalizeBoxes,
  }

  local Pokemon = V.require("Pokemon").install(mod, core)
  local Items = V.require("Items").install(mod, core)
  local Money = V.require("Money").install(mod, core)

  local QuarantineReport = require("src.ui.QuarantineReport")

  local function validateBankStorage(game)
    if not (game and game.data) then return nil end
    loadStorage()
    local poke = Pokemon.validateStorage(game)
    local items = Items.validateStorage(game)
    local changed = poke.changed or items.changed
    if changed then markDirty() end
    return {
      changed = changed,
      pokemon = poke,
      items = items,
      report = {
        lostMons = poke.lostMons or {},
        lostItems = items.lostItems or {},
        restoredMons = poke.restoredMons or {},
        restoredItems = items.restoredItems or {}
      }
    }
  end

  mod.exports.validateStorage = validateBankStorage

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
    if not pcEntryEnabled() then return out end
    -- Nothing to open with every tab off -- drop the row instead of showing an empty chooser (or a chooser with nothing behind it).
    if not (Pokemon.tabEnabled() or Items.tabEnabled() or Money.tabEnabled()) then return out end
    -- keepOpen mirrors every other row already on this menu, so B in the chooser above returns to the PC menu instead of logging off.
    return mod.ui.insertBefore(out, "PROF.OAK's PC", {
      label = PC_MENU_LABEL,
      keepOpen = true,
      onSelect = function() openBankMenu(game) end,
    })
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
    local was = dirty
    flushStorage()
    return was
  end

  mod.log:info("Pokemon Bank loaded")
end
