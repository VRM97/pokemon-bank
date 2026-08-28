local V = ...

local SCREEN_ID = "PokemonBankStats"
local STATS_VERSION = 1
local SAVE_KEY = "stats"

local Module = {}

function Module.install(mod, core, File)
  local Stats = {
    STATS_VERSION = STATS_VERSION,
    screenId = SCREEN_ID,
  }

  local function freshLinkCartTotals()
    return { pokemon = 0, items = 0, moves = 0, money = 0 }
  end

  local function freshCounters()
    return {
      transactions = 0,
      pokemon = {
        deposited = 0,
        withdrawn = 0,
        released = 0
      },
      items = {
        depositedOps = 0,
        depositedQty = 0,
        withdrawnOps = 0,
        withdrawnQty = 0,
        tossedOps = 0,
        tossedQty = 0
      },
      moves = {
        depositedOps = 0,
        depositedQty = 0,
        withdrawnOps = 0,
        withdrawnQty = 0,
        taught = 0
      },
      money = {
        depositedOps = 0,
        depositedTotal = 0,
        withdrawnOps = 0,
        withdrawnTotal = 0
      },
      link = {
        completed = 0,
        cancelled = 0,
        sent = freshLinkCartTotals(),
        received = freshLinkCartTotals()
      },
    }
  end

  local function freshStats()
    local s = freshCounters()
    s.version = STATS_VERSION
    s.peakMoney = 0
    s.species = {}
    return s
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
    c.moves = type(c.moves) == "table" and c.moves or {}
    for _, key in ipairs({ "depositedOps", "depositedQty", "withdrawnOps", "withdrawnQty", "taught" }) do
      c.moves[key] = num(c.moves[key])
    end
    c.money = type(c.money) == "table" and c.money or {}
    for _, key in ipairs({ "depositedOps", "depositedTotal", "withdrawnOps", "withdrawnTotal" }) do
      c.money[key] = num(c.money[key])
    end
    c.link = type(c.link) == "table" and c.link or {}
    c.link.completed = num(c.link.completed)
    c.link.cancelled = num(c.link.cancelled)
    for _, side in ipairs({ "sent", "received" }) do
      c.link[side] = type(c.link[side]) == "table" and c.link[side] or {}
      for _, key in ipairs({ "pokemon", "items", "moves", "money" }) do
        c.link[side][key] = num(c.link[side][key])
      end
    end
    return c
  end

  local function normalizeStats(s)
    normalizeCounters(s)
    s.version = STATS_VERSION
    s.peakMoney = num(s.peakMoney)
    local species = type(s.species) == "table" and s.species or {}
    local clean = {}
    for id, count in pairs(species) do
      if type(id) == "string" and count and count > 0 then clean[id] = num(count) end
    end
    s.species = clean
    return s
  end

  local stats = File.new(mod, "stats.lua", freshStats, normalizeStats)

  local function saveCounters()
    local s = mod.save:get(SAVE_KEY)
    if type(s) ~= "table" then
      s = freshCounters()
      mod.save:set(SAVE_KEY, s)
    end
    normalizeCounters(s)
    return s
  end

  local function bumpSpecies(species)
    if species == nil then return end
    local g = stats.loadFile()
    local id = tostring(species)
    g.species[id] = (g.species[id] or 0) + 1
  end

  local function bumpTransaction()
    local g, s = stats.loadFile(), saveCounters()
    g.transactions, s.transactions = g.transactions + 1, s.transactions + 1
    return g, s
  end

  mod.events:on("mod.vrm_pokemon_bank.pokemon_deposited", function(ev)
    local g, s = bumpTransaction()
    g.pokemon.deposited, s.pokemon.deposited = g.pokemon.deposited + 1, s.pokemon.deposited + 1
    bumpSpecies(ev and ev.mon and ev.mon.species)
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.pokemon_withdrawn", function()
    local g, s = bumpTransaction()
    g.pokemon.withdrawn, s.pokemon.withdrawn = g.pokemon.withdrawn + 1, s.pokemon.withdrawn + 1
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.pokemon_released", function()
    local g, s = bumpTransaction()
    g.pokemon.released, s.pokemon.released = g.pokemon.released + 1, s.pokemon.released + 1
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_deposited", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = bumpTransaction()
    g.items.depositedOps, s.items.depositedOps = g.items.depositedOps + 1, s.items.depositedOps + 1
    g.items.depositedQty, s.items.depositedQty = g.items.depositedQty + qty, s.items.depositedQty + qty
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_withdrawn", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = bumpTransaction()
    g.items.withdrawnOps, s.items.withdrawnOps = g.items.withdrawnOps + 1, s.items.withdrawnOps + 1
    g.items.withdrawnQty, s.items.withdrawnQty = g.items.withdrawnQty + qty, s.items.withdrawnQty + qty
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.item_tossed", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = bumpTransaction()
    g.items.tossedOps, s.items.tossedOps = g.items.tossedOps + 1, s.items.tossedOps + 1
    g.items.tossedQty, s.items.tossedQty = g.items.tossedQty + qty, s.items.tossedQty + qty
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.move_deposited", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = bumpTransaction()
    g.moves.depositedOps, s.moves.depositedOps = g.moves.depositedOps + 1, s.moves.depositedOps + 1
    g.moves.depositedQty, s.moves.depositedQty = g.moves.depositedQty + qty, s.moves.depositedQty + qty
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.move_withdrawn", function(ev)
    local qty = num(ev and ev.qty)
    local g, s = bumpTransaction()
    g.moves.withdrawnOps, s.moves.withdrawnOps = g.moves.withdrawnOps + 1, s.moves.withdrawnOps + 1
    g.moves.withdrawnQty, s.moves.withdrawnQty = g.moves.withdrawnQty + qty, s.moves.withdrawnQty + qty
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.move_taught", function()
    local g, s = bumpTransaction()
    g.moves.taught, s.moves.taught = g.moves.taught + 1, s.moves.taught + 1
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.money_deposited", function(ev)
    local amount = num(ev and ev.amount)
    local g, s = bumpTransaction()
    g.money.depositedOps, s.money.depositedOps = g.money.depositedOps + 1, s.money.depositedOps + 1
    g.money.depositedTotal, s.money.depositedTotal = g.money.depositedTotal + amount, s.money.depositedTotal + amount
    local balance = core.loadStorage().money or 0
    if balance > g.peakMoney then g.peakMoney = balance end
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.money_withdrawn", function(ev)
    local amount = num(ev and ev.amount)
    local g, s = bumpTransaction()
    g.money.withdrawnOps, s.money.withdrawnOps = g.money.withdrawnOps + 1, s.money.withdrawnOps + 1
    g.money.withdrawnTotal, s.money.withdrawnTotal = g.money.withdrawnTotal + amount, s.money.withdrawnTotal + amount
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.link_completed", function(ev)
    local g, s = bumpTransaction()
    g.link.completed, s.link.completed = g.link.completed + 1, s.link.completed + 1
    for _, side in ipairs({ "sent", "received" }) do
      local counts = ev and ev[side]
      for _, key in ipairs({ "pokemon", "items", "moves", "money" }) do
        local v = num(counts and counts[key])
        g.link[side][key], s.link[side][key] = g.link[side][key] + v, s.link[side][key] + v
      end
    end
    stats.markDirty()
  end)

  mod.events:on("mod.vrm_pokemon_bank.link_cancelled", function()
    local g, s = stats.loadFile(), saveCounters()
    g.link.cancelled, s.link.cancelled = g.link.cancelled + 1, s.link.cancelled + 1
    stats.markDirty()
  end)

  local function copyCounters(c)
    return {
      transactions = c.transactions,
      pokemon = { deposited = c.pokemon.deposited, withdrawn = c.pokemon.withdrawn, released = c.pokemon.released },
      items = {
        depositedOps = c.items.depositedOps, depositedQty = c.items.depositedQty,
        withdrawnOps = c.items.withdrawnOps, withdrawnQty = c.items.withdrawnQty,
        tossedOps = c.items.tossedOps, tossedQty = c.items.tossedQty,
      },
      moves = {
        depositedOps = c.moves.depositedOps, depositedQty = c.moves.depositedQty,
        withdrawnOps = c.moves.withdrawnOps, withdrawnQty = c.moves.withdrawnQty,
        taught = c.moves.taught,
      },
      money = {
        depositedOps = c.money.depositedOps, depositedTotal = c.money.depositedTotal,
        withdrawnOps = c.money.withdrawnOps, withdrawnTotal = c.money.withdrawnTotal,
      },
      link = {
        completed = c.link.completed, cancelled = c.link.cancelled,
        sent = { pokemon = c.link.sent.pokemon, items = c.link.sent.items, moves = c.link.sent.moves, money = c.link.sent.money },
        received = { pokemon = c.link.received.pokemon, items = c.link.received.items, moves = c.link.received.moves, money = c.link.received.money },
      },
    }
  end

  local function getGlobalStats()
    local g = stats.loadFile()
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
    local g = stats.loadFile()
    local bestId, bestCount = nil, 0
    for id, count in pairs(g.species) do
      if count > bestCount then bestId, bestCount = id, count end
    end
    return bestId, bestCount
  end

  local function fmtMoney(n) return ("¥%d"):format(n) end

  local function appendRow(rows, label, value, description) rows[#rows + 1] = { label = label, right = tostring(value), description = description } end

  local function appendPokemonRows(rows, pokemon)
    appendRow(rows, "<PK><MN> IN", pokemon.deposited, "Deposited count.")
    appendRow(rows, "<PK><MN> OUT", pokemon.withdrawn, "Withdrawn count.")
    appendRow(rows, "<PK><MN> REL", pokemon.released, "Released count.")
  end

  local function appendItemRows(rows, items)
    appendRow(rows, "ITEM IN", items.depositedQty, "Items deposited.")
    appendRow(rows, "ITEM OUT", items.withdrawnQty, "Items withdrawn.")
    appendRow(rows, "ITEM TOSS", items.tossedQty, "Items tossed.")
  end

  local function appendMoveRows(rows, moves)
    appendRow(rows, "MOVE IN", moves.depositedQty, "Moves deposited.")
    appendRow(rows, "MOVE OUT", moves.withdrawnQty, "Moves withdrawn.")
    appendRow(rows, "TAUGHT", moves.taught, "Moves taught.")
  end

  local function appendMoneyRows(rows, money)
    appendRow(rows, "¥ IN", fmtMoney(money.depositedTotal), "Money deposited.")
    appendRow(rows, "¥ OUT", fmtMoney(money.withdrawnTotal), "Money withdrawn.")
  end

  local function appendLinkRows(rows, link)
    appendRow(rows, "LINK OK", link.completed, "Completed LINKs.")
    appendRow(rows, "LINK CANCEL", link.cancelled, "Cancelled LINKs.")
    appendRow(rows, "SENT <PK><MN>", link.sent.pokemon, "POKéMON sent.")
    appendRow(rows, "SENT ITEM", link.sent.items, "Items sent.")
    appendRow(rows, "SENT MOVE", link.sent.moves, "Moves sent.")
    appendRow(rows, "SENT ¥", fmtMoney(link.sent.money), "Money sent.")
    appendRow(rows, "RECV <PK><MN>", link.received.pokemon, "POKéMON received.")
    appendRow(rows, "RECV ITEM", link.received.items, "Items received.")
    appendRow(rows, "RECV MOVE", link.received.moves, "Moves received.")
    appendRow(rows, "RECV ¥", fmtMoney(link.received.money), "Money received.")
  end

  local function globalRows(game)
    local g = stats.loadFile()
    local rows = {}
    appendRow(rows, "ACTIONS", g.transactions, "Total actions.")
    appendPokemonRows(rows, g.pokemon)
    appendItemRows(rows, g.items)
    appendMoveRows(rows, g.moves)
    appendMoneyRows(rows, g.money)
    appendRow(rows, "¥ PEAK", fmtMoney(g.peakMoney), "Highest balance.")
    appendLinkRows(rows, g.link)
    local topId, topCount = topSpecies()
    if topId then
      local def = game and game.data and game.data.pokemon and game.data.pokemon[topId]
      local name = (def and def.name) or topId
      appendRow(rows, "TOP " .. name, topCount, "Most deposited.")
    end
    return rows
  end

  local function saveRows()
    local s = saveCounters()
    local rows = {}
    appendRow(rows, "ACTIONS", s.transactions, "Total actions.")
    appendPokemonRows(rows, s.pokemon)
    appendItemRows(rows, s.items)
    appendMoveRows(rows, s.moves)
    appendMoneyRows(rows, s.money)
    appendLinkRows(rows, s.link)
    return rows
  end

  local function buildStatsScreen(game)
    local group = core.listGroup(game, {
      screenId = SCREEN_ID,
      readOnly = true,
      counter = true,
      views = { "global", "save" },
      title = function(view) return view == "global" and "BANK STATS" or "PLAYER STATS" end,
      label = function(view) return view == "global" and "BANK" or "PLAYER" end,
      dynamicFooter = function(view, item, nextLabel)
        local description = item and item.description or ""
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or ""
        return description .. "\n" .. selectLine
      end,
      build = function(view)
        local rows = view == "global" and globalRows(game) or saveRows()
        return rows, { rows = 6, noSound = true, wrap = true }
      end,
    })
    return group.screen
  end

  mod.content.screens:register(SCREEN_ID, { new = buildStatsScreen })
  mod.exports.getBankStats = function() return getGlobalStats() end
  mod.exports.getSaveStats = function() return getSaveStats() end
  mod.exports.statsScreenId = SCREEN_ID
  Stats.markDirty = stats.markDirty
  Stats.isDirty = stats.isDirty
  Stats.loadStats = stats.loadFile
  Stats.flushStats = stats.flushFile
  Stats.replaceStats = stats.replaceFile
  Stats.resetStats = stats.resetFile
  Stats.readBackup = stats.readFileBackup
  Stats.deleteStats = stats.deleteFile
  mod.log:info("Pokemon Bank: Stats ready")
  return Stats
end

return Module
