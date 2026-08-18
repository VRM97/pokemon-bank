local V = ...

local Bag = require("src.inventory.Bag")
local Boxes = require("src.pokemon.Boxes")
local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local Pickers = V.require("Pickers")

local SCREEN_ID = "PokemonBankMoves"

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local autoFillRecoveredMoves
  local message = core.message
  local playSound = core.playSound
  local itemName = core.itemName
  local askQuantity = core.askQuantity

  local function tmItemId(moveId)
    return "TM_" .. moveId
  end

  local function tmMoveId(id, def)
    if type(id) ~= "string" or id:sub(1, 3) ~= "TM_" then return nil end
    if def and def.machine and def.machine.kind == "TM" and def.machine.move then return def.machine.move end
    if def and def.teaches then return def.teaches end
    return id:sub(4)
  end

  -- A move can only leave the Bank as a real TM item while the active game actually sells one for it. WITHDRAW MOVE's own list uses this, and so does the exported isValidMachine.
  local function isValidMachine(id, data)
    if type(id) ~= "string" or id == "" then return false end
    if not (data and data.moves and data.moves[id]) then return false end
    local itemDef = data.items and data.items[tmItemId(id)]
    return itemDef ~= nil and tmMoveId(tmItemId(id), itemDef) == id
  end

  -- Species-only, mirrors isValidPokemon: a banked move stays banked as long as it's still a real move, even if this game version currently has no TM for it, so a move only missing its TM stays put and teachable.
  local function isValidMove(id, data)
    return type(id) == "string" and id ~= "" and data and data.moves and data.moves[id] ~= nil
  end

  -- Move storage: a flat { id = count } table of banked TM uses.
  local function moveCount(id)
    return loadStorage().moves[id] or 0
  end

  local function depositMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    if type(id) ~= "string" or id == "" or qty <= 0 then return false, "bad request" end
    local s = loadStorage()
    s.moves[id] = (s.moves[id] or 0) + qty
    markDirty()
    return true
  end

  local function withdrawMove(id, qty)
    qty = math.floor(tonumber(qty) or 0)
    local s = loadStorage()
    local have = s.moves[id] or 0
    if qty <= 0 or qty > have then return false, "not enough" end
    s.moves[id] = have - qty
    if s.moves[id] <= 0 then s.moves[id] = nil end
    markDirty()
    return true
  end

  local function listMoves()
    local out = {}
    for id, count in pairs(loadStorage().moves) do out[id] = count end
    return out
  end

  -- Bidirectional pass: a move id the active game no longer recognizes at all moves to orphaned.moves; one that's real again moves back. A move that's still real but merely lacks a TM right stays banked.
  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostItems = {}, restoredItems = {}, monMovesRestored = 0 }
    end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local quarantined, restored = 0, 0
    local lostItems, restoredItems = {}, {}
    local badIds = {}
    for id in pairs(s.moves) do
      if not isValidMove(id, data) then badIds[#badIds + 1] = id end
    end
    for _, id in ipairs(badIds) do
      local qty = s.moves[id] or 0
      if qty > 0 then
        s.moves[id] = nil
        orphaned.moves[id] = (orphaned.moves[id] or 0) + qty
        quarantined = quarantined + qty
        lostItems[#lostItems + 1] = { id = id, count = qty, from = "POKéMON BANK MOVES" }
      end
    end
    local goodIds = {}
    for id in pairs(orphaned.moves) do
      if isValidMove(id, data) then goodIds[#goodIds + 1] = id end
    end
    for _, id in ipairs(goodIds) do
      local qty = orphaned.moves[id] or 0
      if qty > 0 then
        orphaned.moves[id] = nil
        s.moves[id] = (s.moves[id] or 0) + qty
        restored = restored + qty
        restoredItems[#restoredItems + 1] = { id = id, count = qty }
      end
    end
    local monMovesRestored = autoFillRecoveredMoves(game)
    return {
      changed = quarantined > 0 or restored > 0 or monMovesRestored > 0,
      quarantined = quarantined,
      restored = restored,
      lostItems = lostItems,
      restoredItems = restoredItems,
      monMovesRestored = monMovesRestored,
    }
  end

  local function listInvalidMoves()
    local out = {}
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.moves or {}
    for id, count in pairs(orphaned) do out[id] = count end
    return out
  end

  local function invalidMoveCount(id)
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.moves or {}
    if id ~= nil then return orphaned[id] or 0 end
    local n = 0
    for _, count in pairs(orphaned) do n = n + count end
    return n
  end

  -- =========================================================================
  -- Move UI
  -- =========================================================================

  local function sortedMoveIds(game, counts, filter)
    return core.sortedIdsByName(function(id) return core.moveName(game, id) end, counts, filter)
  end

  -- Every banked move, TM or not right now -- TEACH MOVE's own list: teaching never touches an item, so a move that's still real but currently has no TM (see isValidMove in validateStorage above) belongs here just the same.
  local function bankMoveRows(game)
    local counts = loadStorage().moves
    local rows = {}
    for _, id in ipairs(sortedMoveIds(game, counts)) do
      rows[#rows + 1] = { value = id, label = core.truncateName(core.moveName(game, id)), right = "x" .. tostring(counts[id]) }
    end
    return rows
  end

  -- DEPOSIT MOVE's own bag view: only TM stacks (never HMs -- those stay in the ITEMS tab), listed by move name.
  local function bagTmRowsForBank(game)
    local inv = game.save.inventory
    local rows = {}
    for id, count in pairs(inv) do
      if count and count > 0 then
        local moveId = tmMoveId(id, game.data.items[id])
        if moveId and game.data.moves[moveId] then
          rows[#rows + 1] = { value = id, moveId = moveId, label = core.truncateName(itemName(game, id)), right = "x" .. tostring(count) }
        end
      end
    end
    table.sort(rows, function(a, b) return a.label < b.label end)
    return rows
  end

  local function typeDisplayName(game, typeId)
    local types = game.data.type_chart and game.data.type_chart.types
    local record = types and types[typeId]
    local name = record and record.name or typeId or "?"
    if name == "PSYCHIC_TYPE" then name = "PSYCHIC" end
    return tostring(name)
  end

  local function moveDetailFooter(game, id)
    local def = id and game.data.moves[id]
    if not def then return nil end
    local pp = tostring(math.floor(tonumber(def.pp) or 0))
    local power = (tonumber(def.power) or 0) > 0 and tostring(math.floor(def.power)) or "--"
    local accuracy = (tonumber(def.accuracy) or 0) > 0 and tostring(math.floor(def.accuracy)) or "--"
    return Strings("%s PP:%s\nPWR:%s ACC:%s", typeDisplayName(game, def.type), pp, power, accuracy)
  end

  local function refreshMoveDetailFooter(list, game, moveIdOf)
    list._footerIndex = list.index
    local item = list.items[list.index]
    local id = item and moveIdOf(item)
    local detail = id and moveDetailFooter(game, id)
    if detail then list.footer = detail end
  end

  local function attachMoveDetailFooter(list, game, moveIdOf)
    refreshMoveDetailFooter(list, game, moveIdOf)
    local baseUpdate = list.update
    function list:update(dt)
      baseUpdate(self, dt)
      if self.index ~= self._footerIndex or self.footer == nil then
        refreshMoveDetailFooter(self, game, moveIdOf)
      end
    end
  end

  local function openDepositMovesList(game)
    local list
    list = ListMenu.new(game, "DEPOSIT MOVE", bagTmRowsForBank(game), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item)
        local id = item.value
        local moveId = item.moveId
        local count = game.save.inventory[id]
        if not (moveId and count and count > 0) then
          list.footer = "The selection changed."
          return
        end
        askQuantity(game, list, count, function(qty)
          Bag.remove(game.save, id, qty)
          depositMove(moveId, qty)
          mod.events:emit("mod.vrm_pokemon_bank.move_deposited", { id = moveId, qty = qty })
          list.items = bagTmRowsForBank(game)
          list.index = math.min(list.index, math.max(1, #list.items))
          list._footerIndex = list.index
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("%s was\nstored in BANK.", core.moveName(game, moveId))
        end)
      end,
    })
    attachMoveDetailFooter(list, game, function(item) return item.moveId end)
    game.stack:push(list)
  end

  local function openWithdrawMovesList(game)
    local list
    list = ListMenu.new(game, "WITHDRAW MOVE", bankMoveRows(game), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item)
        local moveId = item.value
        if not isValidMachine(moveId, game.data) then
          list.footer = "There's no TM\nfor that move!"
          return
        end
        local count = moveCount(moveId)
        if count <= 0 then
          list.footer = "The selection changed."
          return
        end
        askQuantity(game, list, count, function(qty)
          local itemId = tmItemId(moveId)
          if not Bag.add(game.save, itemId, qty, game.data) then
            list.footer = "You can't carry\nany more items."
            return
          end
          withdrawMove(moveId, qty)
          mod.events:emit("mod.vrm_pokemon_bank.move_withdrawn", { id = moveId, qty = qty })
          list.items = bankMoveRows(game)
          list.index = math.min(list.index, math.max(1, #list.items))
          list._footerIndex = list.index
          playSound(game, "Withdraw_Deposit")
          list.footer = Strings("Withdrew\n%s.", itemName(game, itemId))
        end)
      end,
    })
    attachMoveDetailFooter(list, game, function(item) return item.value end)
    game.stack:push(list)
  end

  -- TEACH MOVE: spends one banked use teaching moveId to a mon picked from BANK/PARTY/PC.
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

  -- The species an evolutions[] row leads to. Gen 1's own extractor (RomExtractor.lua) writes that species onto `species`; Gen 2's (RomExtractorGen2.lua) writes it onto `into` instead -- both are checked so this reads either generation's data without a GameVersion branch of its own.
  local function evolvesInto(evo)
    return evo and (evo.into or evo.species)
  end

  -- The direct prevolution of a species: whichever other species' own evolutions[] list leads to it. game.data.pokemon also carries a couple of non-species rows (growthRates, tmhmMoves) that ride the same table with no evolutions of their own -- the `def.evolutions` table type check already skips those.
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

  -- ABLE for TEACH MOVE: true when mon's own species knows moveId by speciesKnowsMove above, OR any species it evolved from does -- checked one prevolution at a time (CHARMELEON, then CHARMANDER, stopping the moment one knows it) rather than building the whole chain up front, on the same "could this line ever legitimately know it" logic a real TM's own tmhm list already extends across a whole family via CanLearnTMHMMove in vanilla, just widened here to every ABLE source instead of tmhm alone. `seen` guards a cyclical evolutions table (bad data from some other mod) from looping forever.
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

  -- Mirrors ItemEffects.use's own TM/HM branch (already-knows check) and BagMenu.lua's teach()/Game2:useFieldItem's own learn call for the actual slot-management -- canLearn above is deliberately broader than what a real TM alone would allow, see its own comment.
  local function attemptTeach(game, mon, moveId, onDone)
    mon.moves = mon.moves or {}
    local mdef = game.data.moves[moveId]
    local moveLabel = mdef and mdef.name or moveId
    local speciesDef = game.data.pokemon[mon.species]
    local name = mon.nickname or mon.name or (speciesDef and speciesDef.name) or tostring(mon.species)
    if not canLearn(game, mon, moveId) then
      return onDone(false, Strings("%s can't\nlearn %s!", name, moveLabel))
    end
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == moveId then
        return onDone(false, Strings("%s already\nknows %s!", name, moveLabel))
      end
    end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, moveId, function(learned)
        if learned then
          pcall(function() require("src.core.gen2.Happiness").change(mon, "LEARNMOVE") end)
        end
        onDone(learned)
      end)
      return
    end
    local function taught()
      pcall(function()
        require("src.world.PikachuFollower").modifyHappiness(game.save, "USEDTMHM", mon)
      end)
    end
    if #mon.moves < 4 then
      table.insert(mon.moves, { id = moveId, pp = mdef.pp })
      playSound(game, "Get_Item1")
      taught()
      onDone(true, Strings("%s learned\n%s!", name, moveLabel))
    else
      require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId, function(learned)
        if learned then taught() end
        onDone(learned)
      end)
    end
  end

  local function reusableMachinesActive()
    return mod.find and mod.find("reusable_machines") ~= nil
  end

  local function openTeachTargetList(game, moveId)
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
        if not reusableMachinesActive() then
          local s = loadStorage()
          s.moves[moveId] = (s.moves[moveId] or 0) - 1
          if s.moves[moveId] <= 0 then s.moves[moveId] = nil end
          markDirty()
        end
        mod.events:emit("mod.vrm_pokemon_bank.move_taught", { id = moveId, mon = mon })
        if moveCount(moveId) <= 0 then
          handle.close()
          if msg then message(game, msg) end
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

  -- RELEARN MOVE: recovers a move set aside on orphaned.monMoves (a species-valid mon that briefly held an id the active game didn't recognize), then which of its recoverable moves to bring back. bankId survives a withdraw, so the mon showing ABLE here may not even still be in the Bank.
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
      for _, mon in ipairs(box) do
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

  local function hasAnyRelearnable(game)
    return scanMons(game, function(mon) return canRelearn(game, mon) end)
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
      local already = false
      for _, mv in ipairs(mon.moves) do
        if mv.id == id then already = true break end
      end
      if already then
        consumeRecoveredMove(mon.bankId, id)
      else
        local mdef = game.data.moves[id]
        local entry = {}
        if type(mvEntry) == "table" then
          for k, v in pairs(mvEntry) do entry[k] = v end
        else
          entry.id, entry.pp = id, (mdef and mdef.pp or 0)
        end
        table.insert(mon.moves, entry)
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
    local mdef = game.data.moves[id]
    local moveLabel = mdef and mdef.name or id
    local speciesDef = game.data.pokemon[mon.species]
    local name = mon.nickname or mon.name or (speciesDef and speciesDef.name) or tostring(mon.species)
    for _, mv in ipairs(mon.moves) do
      if mv.id == id then
        return onDone(false, Strings("%s already\nknows %s!", name, moveLabel))
      end
    end
    if GameVersion.generation() == 2 then
      game:learnMoveOn(mon, id, function(learned) onDone(learned) end)
      return
    end
    if #mon.moves < 4 then
      local entry = {}
      if type(mvEntry) == "table" then
        for k, v in pairs(mvEntry) do entry[k] = v end
      else
        entry.id, entry.pp = id, (mdef and mdef.pp or 0)
      end
      table.insert(mon.moves, entry)
      playSound(game, "Get_Item1")
      onDone(true, Strings("%s remembered\n%s!", name, moveLabel))
    else
      require("src.ui.Screens").push(game, "MoveLearnMenu", mon, id, function(learned)
        onDone(learned)
      end)
    end
  end

  local function openRelearnMovesList(game, mon, onClose)
    local list
    local function rebuildRows()
      local moves = recoverableMoves(game, mon.bankId)
      local rows = {}
      for _, mv in ipairs(moves) do
        rows[#rows + 1] = { value = mv, label = core.truncateName(core.moveName(game, entryMoveId(mv))) }
      end
      return rows
    end
    list = ListMenu.new(game, "RELEARN MOVE", rebuildRows(), {
      messageBox = true, noSound = true, wrap = true,
      onCancel = onClose,
      onChoose = function(item)
        attemptRelearn(game, mon, item.value, function(learned, msg)
          if not learned then
            list.footer = msg
            return
          end
          consumeRecoveredMove(mon.bankId, entryMoveId(item.value))
          list.items = rebuildRows()
          list.index = math.min(list.index, math.max(1, #list.items))
          list.footer = msg
          if #list.items == 0 then
            list:close()
            if onClose then onClose() end
          end
        end)
      end,
    })
    game.stack:push(list)
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

  local function openTeachMoveList(game)
    local list
    list = ListMenu.new(game, "TEACH MOVE", bankMoveRows(game), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item)
        if moveCount(item.value) <= 0 then
          list.footer = "The selection changed."
          return
        end
        list:close()
        openTeachTargetList(game, item.value)
      end,
    })
    attachMoveDetailFooter(list, game, function(item) return item.value end)
    game.stack:push(list)
  end

  local function BankMoveMenu(game)
    local rows = {
      { label = "TEACH MOVE", keepOpen = true, onSelect = function() openTeachMoveList(game) end },
      { label = "DEPOSIT MOVE", keepOpen = true, onSelect = function() openDepositMovesList(game) end },
      { label = "WITHDRAW MOVE", keepOpen = true, onSelect = function() openWithdrawMovesList(game) end },
    }
    if hasAnyRelearnable(game) then
      rows[#rows + 1] = { label = "RELEARN MOVE", keepOpen = true, onSelect = function() openRelearnTargetList(game) end }
    end
    rows[#rows + 1] = { label = "CANCEL" }
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = #rows * 2 + 2, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankMoveMenu })

  local movesTab = core.makeTabToggle("show_moves_tab")
  local tabEnabled = movesTab.enabled

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.depositMove = function(id, qty)
    local ok, err = depositMove(id, qty)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.move_deposited", { id = id, qty = qty })
    end
    return ok, err
  end

  mod.exports.withdrawMove = function(id, qty)
    local ok, err = withdrawMove(id, qty)
    if ok then
      mod.events:emit("mod.vrm_pokemon_bank.move_withdrawn", { id = id, qty = qty })
    end
    return ok, err
  end

  mod.exports.moveCount = moveCount
  mod.exports.listMoves = listMoves

  mod.exports.isValidMachine = function(id, game)
    return isValidMachine(id, game and game.data)
  end
  mod.exports.validateMovesStorage = validateStorage
  mod.exports.listInvalidMoves = listInvalidMoves
  mod.exports.invalidMoveCount = invalidMoveCount

  mod.exports.tmItemForMove = tmItemId

  mod.exports.movesScreenId = SCREEN_ID

  mod.exports.setMovesTabEnabled = movesTab.setEnabled
  mod.exports.isMovesTabEnabled = tabEnabled

  mod.log:info("Pokemon Bank: Moves tab ready")

  return {
    screenId = SCREEN_ID,
    tabEnabled = tabEnabled,
    validateStorage = validateStorage,
  }
end

return Module
