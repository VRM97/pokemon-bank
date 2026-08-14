local V = ...

local SaveSerializer = require("src.core.SaveSerializer")
local ListMenu = require("src.ui.ListMenu")

local SCREEN_ID = "PokemonBankStats"
local STATS_VERSION = 1
local SAVE_KEY = "stats"

local Module = {}

function Module.install(mod, core)
  local FILE = core.STORAGE_DIR .. "/stats.lua"
  local BACKUP = FILE .. ".bak"
  local TMP = FILE .. ".tmp"

  local function freshTotals()
    return {
      deposited = 0, withdrawn = 0, released = 0,
    }
  end

  local function freshItemTotals()
    return {
      depositedOps = 0, depositedQty = 0,
      withdrawnOps = 0, withdrawnQty = 0,
      tossedOps = 0, tossedQty = 0,
    }
  end

  local function freshMoneyTotals()
    return {
      depositedOps = 0, depositedTotal = 0,
      withdrawnOps = 0, withdrawnTotal = 0,
    }
  end

  -- Shape shared by the global file and each save's own bucket -- species/peakMoney only make sense at the shared-Bank level, so they're added on top of this in freshGlobal.
  local function freshCounters()
    return {
      transactions = 0,
      pokemon = freshTotals(),
      items = freshItemTotals(),
      money = freshMoneyTotals(),
    }
  end

  local function freshGlobal()
    local g = freshCounters()
    g.version = STATS_VERSION
    g.peakMoney = 0
    g.species = {} -- [speciesId] = times deposited, across every save that ever used this Bank
    return g
  end

  local function num(v, default)
    return math.max(0, math.floor(tonumber(v) or default or 0))
  end

  local function normalizeCounters(c)
    c.transactions = num(c.transactions)
    c.pokemon = type(c.pokemon) == "table" and c.pokemon or {}
    c.pokemon.deposited = num(c.pokemon.deposited)
    c.pokemon.withdrawn = num(c.pokemon.withdrawn)
    c.pokemon.released = num(c.pokemon.released)
    c.items = type(c.items) == "table" and c.items or {}
    for _, key in ipairs({ "depositedOps", "depositedQty", "withdrawnOps", "withdrawnQty", "tossedOps", "tossedQty" }) do
      c.items[key] = num(c.items[key])
    end
    c.money = type(c.money) == "table" and c.money or {}
    for _, key in ipairs({ "depositedOps", "depositedTotal", "withdrawnOps", "withdrawnTotal" }) do
      c.money[key] = num(c.money[key])
    end
    return c
  end

  local function normalizeGlobal(g)
    normalizeCounters(g)
    g.version = STATS_VERSION
    g.peakMoney = num(g.peakMoney)
    local species = type(g.species) == "table" and g.species or {}
    local clean = {}
    for id, count in pairs(species) do
      if type(id) == "string" and count and count > 0 then clean[id] = num(count) end
    end
    g.species = clean
    return g
  end

  local function fileExists(name) return core.fileExists(name) end
  local function tryRead(name) return core.tryRead(name) end
  local function tryWrite(name, data) return core.tryWrite(name, data) end
  local function tryRemove(name) return core.tryRemove(name) end

  local function readFile(name)
    if not fileExists(name) then return nil end
    local raw = tryRead(name)
    if not raw then return nil end
    local decoded = SaveSerializer.decode(raw)
    if type(decoded) ~= "table" then return nil end
    return decoded
  end

  local global -- in-memory cache; loaded lazily on first touch
  local dirty = false

  -- Mirrors main.lua's loadStorage/flushStorage recovery-and-swap discipline (main file wins, then the .tmp staging witness, then the rolling .bak), so a crash mid-write behaves the same way the Bank's own storage.lua already does.
  local function loadGlobal()
    if global then return global end
    local out = readFile(FILE) or readFile(TMP) or readFile(BACKUP) or freshGlobal()
    normalizeGlobal(out)
    global = out
    return global
  end

  local function markDirty() dirty = true end

  local function flushGlobal()
    local was = dirty
    if not (dirty and global) then return was end
    pcall(function() core.fs().createDirectory(core.STORAGE_DIR) end)
    local ok, encoded = pcall(SaveSerializer.encode, global)
    if not ok then
      mod.log:warn("could not encode bank stats: %s", tostring(encoded))
      return was
    end
    if fileExists(FILE) then
      local prev = tryRead(FILE)
      if prev then tryWrite(BACKUP, prev) end
    end
    if not tryWrite(TMP, encoded) then
      mod.log:warn("could not stage %s", TMP)
      return was
    end
    tryRemove(FILE)
    if not tryWrite(FILE, encoded) then
      mod.log:warn("could not write %s", FILE)
      return was
    end
    tryRemove(TMP)
    dirty = false
    return was
  end

  local function resetGlobal()
    global = freshGlobal()
    dirty = false
  end

  -- Per-save counters, backed by save.modData (mod.save) -- mod.save:get returns the same live table it stores, so mutating it in place is enough; :set only runs once, on first creation, matching this platform's own get-or-create idiom (see vrm_o_power's State.lua).
  local function saveCounters()
    local s = mod.save:get(SAVE_KEY)
    if type(s) ~= "table" then
      s = freshCounters()
      mod.save:set(SAVE_KEY, s)
    end
    normalizeCounters(s)
    return s
  end

  -- =========================================================================
  -- Recording: one listener per Bank transaction event (API.md's Events section). Every mutation path in lib/Pokemon.lua, lib/Items.lua and lib/Money.lua -- this mod's own UI and the exported bulk helpers alike -- already funnels through these, so nothing else here needs to hook into the transaction logic itself.
  -- =========================================================================
  local function bumpSpecies(species)
    if species == nil then return end
    local g = loadGlobal()
    local id = tostring(species)
    g.species[id] = (g.species[id] or 0) + 1
  end

  mod.events:on("mod.vrm_pokemon_bank.pokemon_deposited", function(ev)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.pokemon.deposited, s.pokemon.deposited = g.pokemon.deposited + 1, s.pokemon.deposited + 1
    bumpSpecies(ev and ev.mon and ev.mon.species)
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.pokemon_withdrawn", function()
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.pokemon.withdrawn, s.pokemon.withdrawn = g.pokemon.withdrawn + 1, s.pokemon.withdrawn + 1
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.pokemon_released", function()
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.pokemon.released, s.pokemon.released = g.pokemon.released + 1, s.pokemon.released + 1
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_deposited", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.items.depositedOps, s.items.depositedOps = g.items.depositedOps + 1, s.items.depositedOps + 1
    g.items.depositedQty, s.items.depositedQty = g.items.depositedQty + qty, s.items.depositedQty + qty
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_withdrawn", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.items.withdrawnOps, s.items.withdrawnOps = g.items.withdrawnOps + 1, s.items.withdrawnOps + 1
    g.items.withdrawnQty, s.items.withdrawnQty = g.items.withdrawnQty + qty, s.items.withdrawnQty + qty
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_tossed", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.items.tossedOps, s.items.tossedOps = g.items.tossedOps + 1, s.items.tossedOps + 1
    g.items.tossedQty, s.items.tossedQty = g.items.tossedQty + qty, s.items.tossedQty + qty
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.money_deposited", function(ev)
    local amount = num(ev and ev.amount)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.money.depositedOps, s.money.depositedOps = g.money.depositedOps + 1, s.money.depositedOps + 1
    g.money.depositedTotal, s.money.depositedTotal = g.money.depositedTotal + amount, s.money.depositedTotal + amount
    local balance = core.loadStorage().money or 0
    if balance > g.peakMoney then g.peakMoney = balance end
    markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.money_withdrawn", function(ev)
    local amount = num(ev and ev.amount)
    local g, s = loadGlobal(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    g.money.withdrawnOps, s.money.withdrawnOps = g.money.withdrawnOps + 1, s.money.withdrawnOps + 1
    g.money.withdrawnTotal, s.money.withdrawnTotal = g.money.withdrawnTotal + amount, s.money.withdrawnTotal + amount
    markDirty()
  end)

  -- =========================================================================
  -- Read side: deep-ish copies, same "a copy, not a live reference" contract as listItems()/getBox() elsewhere in this mod.
  -- =========================================================================
  local function copyCounters(c)
    return {
      transactions = c.transactions,
      pokemon = { deposited = c.pokemon.deposited, withdrawn = c.pokemon.withdrawn, released = c.pokemon.released },
      items = {
        depositedOps = c.items.depositedOps, depositedQty = c.items.depositedQty,
        withdrawnOps = c.items.withdrawnOps, withdrawnQty = c.items.withdrawnQty,
        tossedOps = c.items.tossedOps, tossedQty = c.items.tossedQty,
      },
      money = {
        depositedOps = c.money.depositedOps, depositedTotal = c.money.depositedTotal,
        withdrawnOps = c.money.withdrawnOps, withdrawnTotal = c.money.withdrawnTotal,
      },
    }
  end

  local function getGlobalStats()
    local g = loadGlobal()
    local out = copyCounters(g)
    out.peakMoney = g.peakMoney
    out.species = {}
    for id, count in pairs(g.species) do out.species[id] = count end
    return out
  end

  local function getSaveStats()
    return copyCounters(saveCounters())
  end

  local function topSpecies()
    local g = loadGlobal()
    local bestId, bestCount = nil, 0
    for id, count in pairs(g.species) do
      if count > bestCount then bestId, bestCount = id, count end
    end
    return bestId, bestCount
  end

  -- =========================================================================
  -- UI: one screen, SELECT toggles between the shared Bank's all-time totals and this save's own contribution to them. Mirrors lib/Items.lua's openMoveItemsList -- a small custom screen wrapping a rebuilt ListMenu -- since the two pages need their own title/footer, and ListMenu itself has no such paging.
  -- =========================================================================
  local function fmtMoney(n) return ("¥%d"):format(n) end
  local function fmtQty(n) return "x" .. tostring(n) end

  local function globalRows(game)
    local g = loadGlobal()
    local rows = {
      { label = "ACTIONS", right = tostring(g.transactions) },
      { label = "PKMN IN", right = tostring(g.pokemon.deposited) },
      { label = "PKMN OUT", right = tostring(g.pokemon.withdrawn) },
      { label = "PKMN REL", right = tostring(g.pokemon.released) },
      { label = "ITEM IN", right = fmtQty(g.items.depositedQty) },
      { label = "ITEM OUT", right = fmtQty(g.items.withdrawnQty) },
      { label = "ITEM TOSS", right = fmtQty(g.items.tossedQty) },
      { label = "¥ IN", right = fmtMoney(g.money.depositedTotal) },
      { label = "¥ OUT", right = fmtMoney(g.money.withdrawnTotal) },
      { label = "¥ PEAK", right = fmtMoney(g.peakMoney) },
    }
    local topId, topCount = topSpecies()
    if topId then
      local def = game and game.data and game.data.pokemon and game.data.pokemon[topId]
      local name = (def and def.name) or topId
      rows[#rows + 1] = { label = "TOP " .. name, right = fmtQty(topCount) }
    end
    return rows
  end

  local function saveRows()
    local s = saveCounters()
    return {
      { label = "ACTIONS", right = tostring(s.transactions) },
      { label = "PKMN IN", right = tostring(s.pokemon.deposited) },
      { label = "PKMN OUT", right = tostring(s.pokemon.withdrawn) },
      { label = "PKMN REL", right = tostring(s.pokemon.released) },
      { label = "ITEM IN", right = fmtQty(s.items.depositedQty) },
      { label = "ITEM OUT", right = fmtQty(s.items.withdrawnQty) },
      { label = "ITEM TOSS", right = fmtQty(s.items.tossedQty) },
      { label = "¥ IN", right = fmtMoney(s.money.depositedTotal) },
      { label = "¥ OUT", right = fmtMoney(s.money.withdrawnTotal) },
    }
  end

  -- SELECT: BANK (every save that ever used this Bank) <-> THIS SAVE (just the active playthrough's own contribution). Read-only -- A and B both just close, same as the engine's own QuarantineReport.
  local function buildStatsScreen(game)
    local state = { view = "global" }
    local screen = { isOpaque = true }
    local list, rebuild, close

    local function viewTitle()
      return state.view == "global" and "BANK STATS" or "SAVE STATS"
    end

    local function nextViewName()
      return state.view == "global" and "SAVE" or "BANK"
    end

    local function cycleView()
      state.view = (state.view == "global") and "save" or "global"
      rebuild()
    end

    rebuild = function()
      local rows = state.view == "global" and globalRows(game) or saveRows()
      list = ListMenu.new(game, viewTitle(), rows, { noSound = true })
      list.footer = "SELECT: " .. nextViewName()
    end

    close = function() game.stack:pop() end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("a") or input:wasPressed("b") then
        close()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
    end

    screen.screenId = SCREEN_ID
    screen.gen1ModernUi = {
      title = function() return viewTitle() end,
      rows = function() return core.publicRows(list) end,
      index = function() return list.index end,
      scroll = function() return list.scroll end,
      footer = function() return list.footer end,
      up = function() core.moveListCursor(list, -1) end,
      down = function() core.moveListCursor(list, 1) end,
      -- "select" is the A-equivalent here (mirrors AmountBox's own confirm/cancel mapping in lib/Money.lua), so it closes the same as A does natively; the physical SELECT button's cycleView is repurposed onto "start" instead, the same way lib/Items.lua's openMoveItemsList does when a screen has no real START use of its own.
      select = function() close() end,
      back = function() close() end,
      start = function() cycleView() end,
      hover = function(payload) core.setListCursor(list, payload) end,
    }

    rebuild()
    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = buildStatsScreen })

  mod.exports.getBankStats = function() return getGlobalStats() end
  mod.exports.getSaveStats = function() return getSaveStats() end
  mod.exports.statsScreenId = SCREEN_ID

  mod.log:info("Pokemon Bank: Stats ready")

  return {
    screenId = SCREEN_ID,
    flush = flushGlobal,
    reset = resetGlobal,
    isDirty = function() return dirty end,
  }
end

return Module
