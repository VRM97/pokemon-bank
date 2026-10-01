local SCREEN_ID = "PokemonBankStats"
local SAVE_KEY = "stats"

local ACTION_FIELD = { deposit = "deposited", withdraw = "withdrawn", remove = "removed", use = false }

local Module = {}

function Module.install(mod, core, CustomStorage)
  local Stats = { screenId = SCREEN_ID }
  local QTY_FORMATS = CustomStorage.QTY_FORMATS

  local record = CustomStorage.getCustomStorage(mod.id)
  local stats = record.statsFile

  local function num(v, default) return math.max(0, math.floor(tonumber(v) or default or 0)) end

  local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deepCopy(x) end
    return out
  end

  local function ensureLinkSessions(s)
    if type(s.linkSessions) ~= "table" then s.linkSessions = { completed = 0, cancelled = 0 } end
    s.linkSessions.completed = num(s.linkSessions.completed)
    s.linkSessions.cancelled = num(s.linkSessions.cancelled)
    return s
  end

  local function loadGlobal() return ensureLinkSessions(stats.loadFile()) end

  local function entryOf(id, key)
    local r = CustomStorage.getCustomStorage(id)
    local index = r and r.entryIndex[key]
    return r, index and r.entries[index] or nil
  end

  local function saveStats()
    local s = mod.save:get(SAVE_KEY)
    if type(s) ~= "table" then
      s = {}
      mod.save:set(SAVE_KEY, s)
    end
    if type(s.basic) ~= "table" then s.basic = {} end
    if type(s.own) ~= "table" then
      local extra = type(s.extra) == "table" and s.extra or nil
      local old = type(s.entries) == "table" and s.entries or {}
      local boxes, moves = type(old.boxes) == "table" and old.boxes or {}, type(old.moves) == "table" and old.moves or {}
      s.own = { [mod.id] = {
        boxes = { species = extra and extra.species or boxes.species },
        moves = { taught = extra and extra.taught or moves.taught },
      } }
      s.extra = nil
    end
    return ensureLinkSessions(s)
  end

  local function takeLegacy(s, id, key)
    local root = id == mod.id and s.entries or (type(s.custom) == "table" and s.custom[id]) or nil
    if type(root) ~= "table" then return nil end
    local legacy = root[key]
    root[key] = nil
    if next(root) == nil then
      if id == mod.id then s.entries = nil else s.custom[id] = nil end
    end
    if type(s.custom) == "table" and next(s.custom) == nil then s.custom = nil end
    return legacy
  end

  local function saveCounters(id, entry)
    local s = saveStats()
    if type(s.basic[id]) ~= "table" then s.basic[id] = {} end
    local v = s.basic[id][entry.key]
    local legacy = type(v) ~= "table" and takeLegacy(s, id, entry.key) or nil
    s.basic[id][entry.key] = (CustomStorage.normalizeBasic(v, legacy, entry.storageFormat))
    return s.basic[id][entry.key]
  end

  local function counters(r, entry) return r.statsFile.loadFile().basic[entry.key], saveCounters(r.id, entry) end

  local function ownSave(id, entry)
    local s = saveStats()
    if type(s.own[id]) ~= "table" then s.own[id] = {} end
    local v = s.own[id][entry.key]
    if v == nil then v = CustomStorage.safeCall(entry.freshStats) or {} end
    local normalized = CustomStorage.safeCall(entry.normalizeStats, v)
    s.own[id][entry.key] = normalized ~= nil and normalized or v
    return s.own[id][entry.key]
  end

  local function ownOf(r, entry, scope)
    if scope == "player" then return ownSave(r.id, entry) end
    return r.statsFile.loadFile().entries[entry.key]
  end

  local function getOwnStats(id, key, scope)
    local r, entry = entryOf(id, key)
    if not entry then return nil end
    return ownOf(r, entry, scope)
  end

  local function setOwnStats(id, key, value, scope)
    local r, entry = entryOf(id, key)
    if not r then return false, "unknown custom storage" end
    if not entry then return false, "unknown entry" end
    if scope == "player" then
      saveStats().own[id][key] = value
    else
      r.statsFile.loadFile().entries[key] = value
      r.statsFile.markDirty()
    end
    return true
  end

  local function updateOwnStats(id, key, update)
    local r, entry = entryOf(id, key)
    if not r then return false, "unknown custom storage" end
    if not entry then return false, "unknown entry" end
    if type(update) ~= "function" then return false, "update must be a function" end
    for _, scope in ipairs({ "bank", "player" }) do
      local value = ownOf(r, entry, scope)
      local ok, result = pcall(update, value, scope)
      if not ok then
        mod.log:warn("custom storage %s: stats update failed: %s", id, tostring(result))
        return false, "update failed"
      end
      if type(result) == "table" then setOwnStats(id, key, result, scope) end
    end
    r.statsFile.markDirty()
    return true
  end

  local function raisePeak(r, entry, ...)
    if entry.storageFormat ~= "single" then return end
    local balance = num(r.file.loadFile().entries[entry.key])
    for _, c in ipairs({ ... }) do
      if balance > c.peak then c.peak = balance end
    end
  end

  local function recordAction(id, key, action, amount)
    local field = ACTION_FIELD[action]
    if field == nil then return false, "unknown action" end
    local r, entry = entryOf(id, key)
    if not entry then return false, "unknown entry" end
    local g, s = counters(r, entry)
    amount = num(amount, 1)
    for _, c in ipairs({ g, s }) do
      c.transactions = c.transactions + 1
      if not field then
      elseif QTY_FORMATS[entry.storageFormat] then
        c[field] = (c[field] or 0) + 1
        c[field .. "Qty"] = (c[field .. "Qty"] or 0) + amount
      else c[field] = (c[field] or 0) + amount end
    end
    raisePeak(r, entry, g, s)
    r.statsFile.markDirty()
    return true
  end

  local function recordCustomStorageAction(id, key, action, amount)
    if id == mod.id then return false, "unknown entry" end
    return CustomStorage.reportAction(id, key, action, amount)
  end

  mod.events:on("mod.vrm_pokemon_bank.storage_action", function(ev)
    if type(ev) == "table" then recordAction(ev.id, ev.key, ev.action, ev.amount) end
  end)

  mod.events:on("mod.vrm_pokemon_bank.link_completed", function(ev)
    local g, s = loadGlobal(), saveStats()
    g.linkSessions.completed = g.linkSessions.completed + 1
    s.linkSessions.completed = s.linkSessions.completed + 1
    stats.markDirty()
    local moved = {}
    local entries = ev and type(ev.entries) == "table" and ev.entries or {}
    for side, field in pairs({ sent = "sent", received = "received" }) do
      for id, keys in pairs(type(entries[side]) == "table" and entries[side] or {}) do
        for key, c in pairs(type(keys) == "table" and keys or {}) do
          local r, entry = entryOf(id, key)
          local count, qty = num(type(c) == "table" and c.count), num(type(c) == "table" and c.qty)
          if entry and (count > 0 or qty > 0) then
            local cg, cs = counters(r, entry)
            for _, t in ipairs({ cg, cs }) do
              t[field] = t[field] + count
              if QTY_FORMATS[entry.storageFormat] then t[field .. "Qty"] = t[field .. "Qty"] + qty end
            end
            moved[r.id .. "\0" .. key] = { r = r, entry = entry, g = cg, s = cs }
          end
        end
      end
    end
    for _, m in pairs(moved) do
      m.g.links, m.s.links = m.g.links + 1, m.s.links + 1
      raisePeak(m.r, m.entry, m.g, m.s)
      m.r.statsFile.markDirty()
    end
  end)

  mod.events:on("mod.vrm_pokemon_bank.link_cancelled", function()
    local g, s = loadGlobal(), saveStats()
    g.linkSessions.cancelled = g.linkSessions.cancelled + 1
    s.linkSessions.cancelled = s.linkSessions.cancelled + 1
    stats.markDirty()
  end)

  local function getEntryStats(id, key)
    local r, entry = entryOf(id, key)
    if not entry then return nil end
    local g, s = counters(r, entry)
    return { bank = deepCopy(g), player = deepCopy(s) }
  end

  local function publishedStats(global)
    local function c(key)
      local r, entry = entryOf(mod.id, key)
      local g, s = counters(r, entry)
      return global and g or s
    end
    local boxes, items, moves, money = c("boxes"), c("items"), c("moves"), c("money")
    local sessions = global and loadGlobal().linkSessions or saveStats().linkSessions
    local total = sessions.completed
    for _, entry in ipairs(record.entries) do total = total + c(entry.key).transactions end
    local scope = global and "bank" or "player"
    local taught = num(getOwnStats(mod.id, "moves", scope).taught)
    local out = {
      transactions = total,
      pokemon = { deposited = boxes.deposited, withdrawn = boxes.withdrawn, released = boxes.removed or 0 },
      items = {
        depositedOps = items.deposited, depositedQty = items.depositedQty, withdrawnOps = items.withdrawn,
        withdrawnQty = items.withdrawnQty, tossedOps = items.removed or 0, tossedQty = items.removedQty or 0,
      },
      moves = {
        depositedOps = moves.deposited, depositedQty = moves.depositedQty, withdrawnOps = moves.withdrawn,
        withdrawnQty = moves.withdrawnQty, taught = taught,
      },
      money = {
        depositedOps = money.deposited, depositedTotal = money.depositedQty, withdrawnOps = money.withdrawn,
        withdrawnTotal = money.withdrawnQty,
      },
      link = {
        completed = sessions.completed, cancelled = sessions.cancelled,
        sent = { pokemon = boxes.sent, items = items.sentQty, moves = moves.sentQty, money = money.sentQty },
        received = { pokemon = boxes.received, items = items.receivedQty, moves = moves.receivedQty, money = money.receivedQty },
      },
    }
    if global then
      out.peakMoney = money.peak
      out.species = deepCopy(getOwnStats(mod.id, "boxes", "bank").species)
    end
    return out
  end

  local function appendRow(rows, label, value, description) rows[#rows + 1] = { label = label, right = tostring(value), description = description } end

  local function appendBasicRows(rows, entry, c)
    local qty = QTY_FORMATS[entry.storageFormat]
    local single = entry.storageFormat == "single"
    local prefix = single and type(entry.link) == "table" and type(entry.link.prefix) == "string" and entry.link.prefix or ""
    local function amount(n) return prefix .. n end
    appendRow(rows, "ACTIONS", c.transactions, "Bank actions.")
    appendRow(rows, "DEPOSITED", c.deposited, "Deposits made.")
    if qty then appendRow(rows, "DEP. QTY", amount(c.depositedQty), "Amount deposited.") end
    appendRow(rows, "WITHDRAWN", c.withdrawn, "Withdrawals made.")
    if qty then appendRow(rows, "WDR. QTY", amount(c.withdrawnQty), "Amount withdrawn.") end
    if (c.removed or 0) > 0 then appendRow(rows, "REMOVED", c.removed, "Removals made.") end
    if qty and (c.removedQty or 0) > 0 then appendRow(rows, "REM. QTY", amount(c.removedQty), "Amount removed.") end
    if entry.linkEnabled ~= false then
      appendRow(rows, "LINKS", c.links, "LINK trades.")
      appendRow(rows, "SENT", c.sent, "Sent by LINK.")
      if qty then appendRow(rows, "SENT QTY", amount(c.sentQty), "Amount sent.") end
      appendRow(rows, "RECEIVED", c.received, "Received by LINK.")
      if qty then appendRow(rows, "RECV QTY", amount(c.receivedQty), "Amount received.") end
    end
    if single then appendRow(rows, "PEAK", amount(c.peak), "Highest balance.") end
  end

  local function appendEntryRows(rows, game, page, scope)
    if type(page.entry.stats) ~= "table" then return end
    local statsValue = ownOf(page.record, page.entry, scope)
    for _, row in ipairs(page.entry.stats) do
      local value, label = CustomStorage.safeCall(row.value, game, statsValue)
      if value ~= nil then appendRow(rows, type(label) == "string" and label or row.label, value, row.description) end
    end
  end

  local function statsPages()
    local out = {}
    for _, r in ipairs(CustomStorage.listCustomStorages()) do
      for _, entry in ipairs(r.entries) do
        out[#out + 1] = { label = #r.entries == 1 and r.name:upper() or entry.label, record = r, entry = entry }
      end
    end
    return out
  end

  local function buildStatsScreen(game)
    local pages = statsPages()
    local pageIndex = 1
    local function page() return pages[pageIndex] end
    local scopeLabel = { global = "BANK", save = "PLAYER" }

    local group
    local function flipPage(delta)
      pageIndex = ((pageIndex - 1 + delta) % #pages) + 1
      group.rebuild()
    end

    group = core.listGroup(game, {
      screenId = SCREEN_ID,
      readOnly = true,
      counter = true,
      views = { "global", "save" },
      title = function(view) return core.truncateName(scopeLabel[view] .. " " .. page().label, 16) end,
      label = function(view) return scopeLabel[view] end,
      dynamicFooter = function(view, item, nextLabel)
        local description = item and item.description or ""
        return description .. "\n" .. (nextLabel and ("SELECT: " .. nextLabel) or "")
      end,
      build = function(view)
        local rows = {}
        local global = view == "global"
        local g, s = counters(page().record, page().entry)
        appendBasicRows(rows, page().entry, global and g or s)
        appendEntryRows(rows, game, page(), global and "bank" or "player")
        return rows, { rows = 6, noSound = true, wrap = true }
      end,
      extraKeys = function(input)
        if input:wasPressed("left") then flipPage(-1) return true end
        if input:wasPressed("right") then flipPage(1) return true end
        return false
      end,
      modernUi = { left = function() flipPage(-1) end, right = function() flipPage(1) end },
    })
    return group.screen
  end

  mod.content.screens:register(SCREEN_ID, { new = buildStatsScreen })
  mod.exports.getBankStats = function() return publishedStats(true) end
  mod.exports.getSaveStats = function() return publishedStats(false) end
  mod.exports.getEntryStats = getEntryStats
  mod.exports.statsScreenId = SCREEN_ID
  mod.exports.recordCustomStorageAction = recordCustomStorageAction
  mod.exports.getCustomStorageStats = getOwnStats
  mod.exports.setCustomStorageStats = setOwnStats
  mod.exports.updateCustomStorageStats = updateOwnStats
  Stats.markDirty = stats.markDirty
  mod.log:info("Pokemon Bank: Stats ready")
  return Stats
end

return Module
