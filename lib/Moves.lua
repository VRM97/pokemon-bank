local V = ...

local GameVersion = require("src.core.GameVersion")
local Bag = require("src.inventory.Bag")
local Boxes = require("src.pokemon.Boxes")
local Strings = require("src.core.Strings")
local Menu = require("src.ui.Menu")
local Pickers = V.require("Pickers")

local SCREEN_ID = "PokemonBankMoves"

local Module = {}

function Module.install(mod, core)
  local Moves = { screenId = SCREEN_ID }
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local autoFillRecoveredMoves
  local playSound = core.playSound
  local askQuantity = core.askQuantity

  local function tmItemId(moveId) return "TM_" .. moveId end

  local function tmMoveId(id, def)
    if type(id) ~= "string" or id:sub(1, 3) ~= "TM_" then return nil end
    if def and def.machine and def.machine.kind == "TM" and def.machine.move then return def.machine.move end
    if def and def.teaches then return def.teaches end
    return id:sub(4)
  end

  local function isValidMachine(id, data)
    if type(id) ~= "string" or id == "" then return false end
    if not (data and data.moves and data.moves[id]) then return false end
    local itemDef = data.items and data.items[tmItemId(id)]
    return itemDef ~= nil and tmMoveId(tmItemId(id), itemDef) == id
  end

  local function isValidMove(id, data) return type(id) == "string" and id ~= "" and data and data.moves and data.moves[id] ~= nil end

  local function moveCount(id) return loadStorage().moves[id] or 0 end

  local function depositMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    core.bucketAdd(loadStorage().moves, id, qty)
    markDirty()
    return true
  end

  local function withdrawMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if not core.bucketSub(loadStorage().moves, id, qty) then return false, "not enough" end
    markDirty()
    return true
  end

  local function listMoves()
    local out = {}
    for id, count in pairs(loadStorage().moves) do out[id] = count end
    return out
  end

  function Moves.validateStorage(game)
    local data = game and game.data
    if not data then return { changed = false, quarantined = 0, restored = 0, lostItems = {}, restoredItems = {}, monMovesRestored = 0 } end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local result = core.reconcileCountBucket(s.moves, orphaned.moves, function(id) return isValidMove(id, data) end, "POKéMON BANK MOVES")
    result.monMovesRestored = autoFillRecoveredMoves(game)
    result.changed = result.quarantined > 0 or result.restored > 0 or result.monMovesRestored > 0
    return result
  end

  local function listInvalidMoves() return core.listOrphaned("moves") end

  local function invalidMoveCount(id) return core.orphanedCount("moves", id) end

  -- =========================================================================
  -- Move UI
  -- =========================================================================

  local function sortedMoveIds(game, counts, filter) return core.sortedIdsByName(function(id) return core.moveName(game, id) end, counts, filter) end

  local function tmRowsForBank(game, counts)
    local rows = {}
    for id, count in pairs(counts) do
      if count and count > 0 then
        local moveId = tmMoveId(id, game.data.items[id])
        if moveId and game.data.moves[moveId] then
          rows[#rows + 1] = { value = id, moveId = moveId, label = core.truncateName(core.moveName(game, moveId)), right = "x" .. tostring(count) }
        end
      end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
  end

  local function typeDisplayName(game, typeId)
    local types = game.data.type_chart and game.data.type_chart.types
    local record = types and types[typeId]
    local name = record and record.name or typeId or "UNKNOWN"
    if name == "PSYCHIC_TYPE" then name = "PSYCHIC" end
    return tostring(name)
  end

  local TYPE_ABBR = {
    NORMAL = "NOR", FIGHTING = "FIG", FLYING = "FLY", POISON = "POI", GROUND = "GRD",
    ROCK = "ROK", BUG = "BUG", GHOST = "GHO", FIRE = "FIR", WATER = "WTR", GRASS = "GRS",
    ELECTRIC = "ELC", PSYCHIC = "PSY", ICE = "ICE", DRAGON = "DRG", DARK = "DRK",
    STEEL = "STL", FAIRY = "FRY", UNKNOWN = "UNK",
  }

  local function typeAbbr(name) return TYPE_ABBR[tostring(name):upper()] or "UNK" end

  function Moves.moveDetailLine(game, id)
    local def = id and game.data.moves[id]
    if not def then return nil end
    local power = (tonumber(def.power) or 0) > 0 and tostring(math.floor(def.power)) or "--"
    local accuracy = (tonumber(def.accuracy) or 0) > 0 and tostring(math.floor(def.accuracy)) or "--"
    return Strings("%s PWR%s ACC%s", typeAbbr(typeDisplayName(game, def.type)), power, accuracy)
  end

  function Moves.movePpText(game, id)
    local def = id and game.data.moves[id]
    return def and ("PP" .. tostring(math.floor(tonumber(def.pp) or 0))) or nil
  end

  function Moves.moveTypeOf(game, id)
    local def = id and game.data.moves[id]
    return def and typeDisplayName(game, def.type)
  end

  local function moveMoveRows(game, view)
    if view == "bag" then return tmRowsForBank(game, game.save.inventory) end
    if view == "pc" then return tmRowsForBank(game, game.save.pcItems) end
    local counts = loadStorage().moves
    local rows = {}
    for _, id in ipairs(sortedMoveIds(game, counts)) do
      rows[#rows + 1] = { value = id, label = core.truncateName(core.moveName(game, id)), right = "x" .. tostring(counts[id]) }
    end
    return rows
  end

  local function moveMoveIdOf(view, item)
    if not item then return nil end
    return (view == "bag" or view == "pc") and item.moveId or item.value
  end

  local function availableMoveTypes(game, view)
    local ids = {}
    for _, row in ipairs(moveMoveRows(game, view)) do
      local id = moveMoveIdOf(view, row)
      if id then ids[id] = 1 end
    end
    return core.availableCategoriesSorted(ids, function(id) return Moves.moveTypeOf(game, id) end)
  end

  local function pageLabel(view)
    if view == "bank" then return "BANK" end
    if view == "pc" then return "PC" end
    return "BAG"
  end

  local function speciesKnowsMove(def, moveId)
    if not def then return false end
    for _, m in ipairs(def.tmhm or {}) do
      if m == moveId then return true end
    end
    if GameVersion.generation() == 2 then
      for _, entry in ipairs(def.levelMoves or {}) do
        if entry.move == moveId then return true end
      end
      for _, m in ipairs(def.eggMoves or {}) do
        if m == moveId then return true end
      end
    else
      for _, m in ipairs(def.level1Moves or {}) do
        if m == moveId then return true end
      end
      for _, entry in ipairs(def.learnset or {}) do
        if entry.move == moveId then return true end
      end
    end
    return false
  end

  local function evolvesInto(evo) return evo and (evo.into or evo.species) end

  local prevolutionCache = {}
  local function prevolutionOf(game, species)
    local cached = prevolutionCache[species]
    if cached ~= nil then return cached or nil end
    local prev
    for id, def in pairs(game.data.pokemon) do
      if type(def) == "table" and type(def.evolutions) == "table" then
        for _, evo in ipairs(def.evolutions) do
          if evolvesInto(evo) == species then
            prev = id
            break
          end
        end
      end
      if prev then break end
    end
    prevolutionCache[species] = prev or false
    return prev
  end

  local function canLearn(game, mon, moveId)
    if type(mon) ~= "table" or mon.isEgg then return false end
    local species = mon.species
    local seen = { [species] = true }
    while species do
      if speciesKnowsMove(game.data.pokemon[species], moveId) then return true end
      local prev = prevolutionOf(game, species)
      if not prev or seen[prev] then break end
      seen[prev] = true
      species = prev
    end
    return false
  end

  local function moveTeachContext(game, mon, id)
    local mdef = game.data.moves[id]
    local moveLabel = mdef and mdef.name or id
    local speciesDef = game.data.pokemon[mon.species]
    local name = mon.nickname or mon.name or (speciesDef and speciesDef.name) or tostring(mon.species)
    return mdef, moveLabel, name
  end

  local function knowsMove(mon, id)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == id then return true end
    end
    return false
  end

  local function insertOrOverflowMove(game, mon, moveId, entry, successMsg, onDone, afterLearn)
    if #mon.moves < 4 then
      table.insert(mon.moves, entry)
      playSound(game, "Get_Item1")
      if afterLearn then afterLearn() end
      onDone(true, successMsg)
    else
      require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId, function(learned)
        if learned and afterLearn then afterLearn() end
        onDone(learned)
      end)
    end
  end

  local function attemptTeach(game, mon, moveId, onDone)
    mon.moves = mon.moves or {}
    local mdef, moveLabel, name = moveTeachContext(game, mon, moveId)
    if not canLearn(game, mon, moveId) then
      return onDone(false, Strings("%s can't\nlearn %s!", name, moveLabel))
    end
    if knowsMove(mon, moveId) then
      return onDone(false, Strings("%s already\nknows %s!", name, moveLabel))
    end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, moveId, function(learned)
        if learned then pcall(function() require("src.core.gen2.Happiness").change(mon, "LEARNMOVE") end) end
        onDone(learned)
      end)
      return
    end
    insertOrOverflowMove(game, mon, moveId, { id = moveId, pp = mdef.pp },
      Strings("%s learned\n%s!", name, moveLabel), onDone, function()
        pcall(function() require("src.world.PikachuFollower").modifyHappiness(game.save, "USEDTMHM", mon) end)
      end)
  end

  local function spendMoveUses()
    return not mod.find("infinite_tms") and not mod.find("reusable_machines") and not mod.find("reusable_machines_gen2")
  end

  local function openTeachTargetList(game, moveId, onTaught)
    local handle
    local function doTeach(mon)
      if moveCount(moveId) <= 0 then
        handle.refresh()
        handle.setFooter("No uses left.")
        return
      end
      attemptTeach(game, mon, moveId, function(learned, msg)
        if not learned then
          handle.refresh()
          handle.setFooter(msg)
          return
        end
        if spendMoveUses() then
          core.bucketSub(loadStorage().moves, moveId, 1)
          markDirty()
        end
        mod.events:emit("mod.vrm_pokemon_bank.move_taught", { id = moveId, mon = mon })
        if onTaught then onTaught() end
        if moveCount(moveId) <= 0 then
          handle.close()
          if msg then core.message(game, msg) end
        else
          handle.refresh()
          handle.setFooter(msg)
        end
      end)
    end
    handle = Pickers.openMovePicker(mod, core, game, {
      compatible = function(mon) return canLearn(game, mon, moveId) end,
      onChoose = function(mon) doTeach(mon) end,
    })
  end

  local entryMoveId = core.moveEntryId

  local function recoverableMoves(game, bankId)
    if bankId == nil then return {} end
    local s = loadStorage()
    local bucket = s.orphaned and s.orphaned.monMoves and s.orphaned.monMoves[bankId]
    if type(bucket) ~= "table" then return {} end
    local out = {}
    for _, mv in ipairs(bucket) do
      local id = entryMoveId(mv)
      if id and game.data.moves[id] then out[#out + 1] = mv end
    end
    return out
  end

  local function canRelearn(game, mon)
    if type(mon) ~= "table" or mon.bankId == nil then return false end
    return #recoverableMoves(game, mon.bankId) > 0
  end

  local function consumeRecoveredMove(bankId, id)
    local s = loadStorage()
    local bucket = s.orphaned and s.orphaned.monMoves and s.orphaned.monMoves[bankId]
    if type(bucket) ~= "table" then return end
    for i, mv in ipairs(bucket) do
      if entryMoveId(mv) == id then table.remove(bucket, i) break end
    end
    core.normalizeBoxes(s)
    markDirty()
  end

  local function scanMons(game, fn)
    local s = loadStorage()
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box.content) do
        if fn(mon) then return true end
      end
    end
    for _, mon in ipairs(game.save.party or {}) do
      if fn(mon) then return true end
    end
    Boxes.ensure(game.save)
    for _, box in ipairs(game.save.boxes) do
      for _, mon in ipairs(box) do
        if fn(mon) then return true end
      end
    end
    return false
  end

  local function hasAnyRelearnable(game) return scanMons(game, function(mon) return canRelearn(game, mon) end) end

  local function recoveredMoveEntry(mvEntry, id, mdef)
    local entry = {}
    if type(mvEntry) == "table" then
      for k, v in pairs(mvEntry) do entry[k] = v end
    else entry.id, entry.pp = id, (mdef and mdef.pp or 0) end
    return entry
  end

  local function fillMonSlots(game, mon)
    if type(mon) ~= "table" or mon.bankId == nil then return 0 end
    mon.moves = mon.moves or {}
    local filled = 0
    while #mon.moves < 4 do
      local moves = recoverableMoves(game, mon.bankId)
      if #moves == 0 then break end
      local mvEntry = moves[1]
      local id = entryMoveId(mvEntry)
      if knowsMove(mon, id) then
        consumeRecoveredMove(mon.bankId, id)
      else
        table.insert(mon.moves, recoveredMoveEntry(mvEntry, id, game.data.moves[id]))
        consumeRecoveredMove(mon.bankId, id)
        filled = filled + 1
      end
    end
    return filled
  end

  function autoFillRecoveredMoves(game)
    local filled = 0
    scanMons(game, function(mon)
      filled = filled + fillMonSlots(game, mon)
      return false
    end)
    return filled
  end

  local function attemptRelearn(game, mon, mvEntry, onDone)
    mon.moves = mon.moves or {}
    local id = entryMoveId(mvEntry)
    local mdef, moveLabel, name = moveTeachContext(game, mon, id)
    if knowsMove(mon, id) then return onDone(false, Strings("%s already\nknows %s!", name, moveLabel)) end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, id, function(learned) onDone(learned) end)
      return
    end
    insertOrOverflowMove(game, mon, id, recoveredMoveEntry(mvEntry, id, mdef), Strings("%s remembered\n%s!", name, moveLabel), onDone)
  end

  local function openRelearnMovesList(game, mon, onClose)
    local function rebuildRows()
      local moves = recoverableMoves(game, mon.bankId)
      local rows = {}
      for _, mv in ipairs(moves) do
        rows[#rows + 1] = { value = mv, label = core.truncateName(core.moveName(game, entryMoveId(mv))) }
      end
      return rows
    end
    local function closeScreen()
      game.stack:pop()
      if onClose then onClose() end
    end
    local screen = core.listScreen(game, { counter = true, onClose = closeScreen })
    screen:rebuild("RELEARN MOVE", rebuildRows(), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item, list)
        attemptRelearn(game, mon, item.value, function(learned, msg)
          if not learned then
            list.footer = msg
            return
          end
          consumeRecoveredMove(mon.bankId, entryMoveId(item.value))
          list.items = rebuildRows()
          list.index = math.min(list.index, math.max(1, #list.items))
          list.footer = msg
          if #list.items == 0 then closeScreen() end
        end)
      end,
    })
    game.stack:push(screen)
  end

  local function openRelearnTargetList(game)
    local handle
    handle = Pickers.openMovePicker(mod, core, game, {
      compatible = function(mon) return canRelearn(game, mon) end,
      onChoose = function(mon)
        if canRelearn(game, mon) then
          openRelearnMovesList(game, mon, function() handle.refresh() end)
        else
          handle.setFooter("It has nothing\nto remember.")
        end
      end,
    })
  end

  local function buildManageMovesScreen(game)
    game.save.pcItems = game.save.pcItems or {}
    local state = { moveType = "ALL" }
    local group

    local function cycleMoveType(delta)
      local avail = availableMoveTypes(game, state.view)
      local nextType = core.cycleCategory(state.moveType, avail, delta)
      if nextType == state.moveType then return end
      state.moveType = nextType
      group.rebuild()
    end

    local function startTeach(moveId)
      if moveCount(moveId) <= 0 then
        group.screen.list.footer = "The selection changed."
        return
      end
      openTeachTargetList(game, moveId, function() group.rebuild(true) end)
    end

    local function startWithdraw(moveId)
      if not isValidMachine(moveId, game.data) then
        group.screen.list.footer = "There's no TM\nfor that move!"
        return
      end
      local count = moveCount(moveId)
      if count <= 0 then
        group.screen.list.footer = "The selection changed."
        return
      end
      askQuantity(game, group.screen.list, count, function(qty)
        local itemId = tmItemId(moveId)
        if not Bag.add(game.save, itemId, qty, game.data) then
          group.screen.list.footer = "You can't carry\nany more items."
          return
        end
        withdrawMove(moveId, qty)
        mod.events:emit("mod.vrm_pokemon_bank.move_withdrawn", { id = moveId, qty = qty })
        playSound(game, "Withdraw_Deposit")
        group.rebuild(true)
        group.screen.list.footer = Strings("Withdrew\n%s.", core.itemName(game, itemId))
      end)
    end

    local function startDeposit(view, itemId, moveId)
      local store = view == "pc" and game.save.pcItems or game.save.inventory
      local count = store[itemId]
      if not (moveId and count and count > 0) then
        group.screen.list.footer = "The selection changed."
        return
      end
      askQuantity(game, group.screen.list, count, function(qty)
        if view == "pc" then
          core.bucketSub(store, itemId, qty)
        else Bag.remove(game.save, itemId, qty) end
        depositMove(moveId, qty)
        mod.events:emit("mod.vrm_pokemon_bank.move_deposited", { id = moveId, qty = qty })
        playSound(game, "Withdraw_Deposit")
        group.rebuild(true)
        group.screen.list.footer = Strings("%s was\nstored in BANK.", core.moveName(game, moveId))
      end)
    end

    local function startToss(view, item, moveId)
      local name = core.moveName(game, moveId)
      if view == "bank" then
        core.confirmTossQuantity(game, group.screen.list, {
          count = moveCount(moveId),
          name = name,
          onToss = function(qty)
            withdrawMove(moveId, qty)
            mod.events:emit("mod.vrm_pokemon_bank.move_tossed", { id = moveId, qty = qty })
          end,
          rebuild = function() group.rebuild(true) end,
        })
      else
        local itemId = item.value
        local store = view == "pc" and game.save.pcItems or game.save.inventory
        core.confirmTossQuantity(game, group.screen.list, {
          count = store[itemId],
          name = name,
          onToss = function(qty)
            if view == "pc" then
              core.bucketSub(store, itemId, qty)
            else Bag.remove(game.save, itemId, qty) end
          end,
          rebuild = function() group.rebuild(true) end,
        })
      end
    end

    local function openMoveRowActions(view, item)
      local moveId = moveMoveIdOf(view, item)
      local rows = {}
      if moveCount(moveId) > 0 then
        rows[#rows + 1] = { label = "TEACH", onSelect = function() startTeach(moveId) end }
      end
      if view == "bank" then
        rows[#rows + 1] = { label = "WITHDRAW", onSelect = function() startWithdraw(moveId) end }
      else
        rows[#rows + 1] = { label = "DEPOSIT", onSelect = function() startDeposit(view, item.value, moveId) end }
      end
      rows[#rows + 1] = { label = "TOSS", onSelect = function() startToss(view, item, moveId) end }
      rows[#rows + 1] = { label = "CANCEL" }
      core.rowActionsMenu(game, rows)
    end

    local function filteredMoveRows(view)
      local rows = moveMoveRows(game, view)
      if state.moveType == "ALL" then return rows end
      local filtered = {}
      for _, row in ipairs(rows) do
        if Moves.moveTypeOf(game, moveMoveIdOf(view, row)) == state.moveType then filtered[#filtered + 1] = row end
      end
      return filtered
    end

    local function startMoveAll()
      local view = state.view
      local rows = filteredMoveRows(view)
      core.confirmBulkMoveAll(game, {
        count = #rows,
        verb = view == "bank" and "Withdraw" or "Deposit",
        resultVerb = view == "bank" and "Withdrew" or "Deposited",
        noun = "moves",
        run = function()
          local moved, refused = 0, 0
          if view == "bank" then
            for _, row in ipairs(rows) do
              local moveId = row.value
              local count = moveCount(moveId)
              if count > 0 and isValidMachine(moveId, game.data) and Bag.add(game.save, tmItemId(moveId), count, game.data) then
                withdrawMove(moveId, count)
                mod.events:emit("mod.vrm_pokemon_bank.move_withdrawn", { id = moveId, qty = count })
                moved = moved + 1
              else
                refused = refused + 1
              end
            end
          else
            local store = view == "pc" and game.save.pcItems or game.save.inventory
            for _, row in ipairs(rows) do
              local itemId, moveId = row.value, row.moveId
              local count = store[itemId]
              if moveId and count and count > 0 then
                if view == "pc" then store[itemId] = nil else Bag.remove(game.save, itemId, count) end
                depositMove(moveId, count)
                mod.events:emit("mod.vrm_pokemon_bank.move_deposited", { id = moveId, qty = count })
                moved = moved + 1
              else
                refused = refused + 1
              end
            end
          end
          return moved, refused
        end,
        rebuild = function() group.rebuild(true) end,
        setFooter = function(msg) group.screen.list.footer = msg end,
      })
    end

    group = core.listGroup(game, {
      counter = true,
      views = { "bank", "bag", "pc" },
      state = state,
      label = pageLabel,
      title = function(view)
        local base = pageLabel(view)
        if state.moveType == "ALL" then return base end
        return Strings("%s (%s)", base, state.moveType)
      end,
      dynamicFooter = function(view, item, nextLabel)
        local id = moveMoveIdOf(view, item)
        local detail = Moves.moveDetailLine(game, id)
        local pp = Moves.movePpText(game, id)
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or nil
        local line2 = (selectLine and pp) and core.padToRight(selectLine, pp) or (selectLine or pp)
        if not line2 then return detail end
        return (detail or "") .. "\n" .. line2
      end,
      build = function(view)
        local avail = availableMoveTypes(game, view)
        state.moveType = core.resetCategoryIfStale(state.moveType, avail)
        return filteredMoveRows(view), {
          messageBox = true, noSound = true, wrap = true,
          onChoose = function(item) openMoveRowActions(view, item) end,
        }
      end,
      extraKeys = function(input)
        if input:wasPressed("left") then cycleMoveType(-1); return true end
        if input:wasPressed("right") then cycleMoveType(1); return true end
        if input:wasPressed("start") then startMoveAll(); return true end
        return false
      end,
      modernUi = {
        left = function() cycleMoveType(-1) end,
        right = function() cycleMoveType(1) end,
      },
    })

    return group.screen
  end

  local function openManageMovesScreen(game)
    game.stack:push(buildManageMovesScreen(game))
  end

  local function BankMoveMenu(game)
    if not hasAnyRelearnable(game) then return buildManageMovesScreen(game) end
    local rows = {
      { label = "MANAGE MOVES", keepOpen = true, onSelect = function() openManageMovesScreen(game) end },
      { label = "RELEARN MOVE", keepOpen = true, onSelect = function() openRelearnTargetList(game) end },
      { label = "CANCEL" },
    }
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankMoveMenu })

  local movesTab = core.makeTabToggle("show_moves_tab")
  Moves.tabEnabled = movesTab.enabled

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.depositMove = core.emitOnSuccess(depositMove, "mod.vrm_pokemon_bank.move_deposited", core.idQtyPayload)
  mod.exports.withdrawMove = core.emitOnSuccess(withdrawMove, "mod.vrm_pokemon_bank.move_withdrawn", core.idQtyPayload)
  mod.exports.tossMove = core.emitOnSuccess(withdrawMove, "mod.vrm_pokemon_bank.move_tossed", core.idQtyPayload)
  mod.exports.moveCount = moveCount
  mod.exports.listMoves = listMoves
  mod.exports.isValidMachine = function(id, game) return isValidMachine(id, game and game.data) end
  mod.exports.validateMovesStorage = Moves.validateStorage
  mod.exports.listInvalidMoves = listInvalidMoves
  mod.exports.invalidMoveCount = invalidMoveCount
  mod.exports.tmItemForMove = tmItemId
  mod.exports.canLearn = canLearn
  mod.exports.speciesKnowsMove = speciesKnowsMove
  mod.exports.prevolutionOf = prevolutionOf
  mod.exports.movesScreenId = SCREEN_ID
  mod.exports.setMovesTabEnabled = movesTab.setEnabled
  mod.exports.isMovesTabEnabled = Moves.tabEnabled
  mod.log:info("Pokemon Bank: Moves tab ready")
  return Moves
end

return Module
