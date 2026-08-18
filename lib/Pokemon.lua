local V = ...

local GameVersion = require("src.core.GameVersion")
local Stats = require("src.pokemon.Stats")
local Party = require("src.pokemon.Party")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local Boxes = require("src.pokemon.Boxes")
local Font = require("src.render.Font")

local BOX_CAPACITY = 20
local SCREEN_ID = "PokemonBankBox"
local TRANSFER_BOX_SCREEN_ID = "PokemonBankTransferBox"
local MOVE_SCREEN_ID = "PokemonBankMovePkmn"

local Module = {}

function Module.install(mod, core)
  local loadStorage = core.loadStorage
  local markDirty = core.markDirty
  local normalizeBoxes = core.normalizeBoxes
  local message = core.message
  local monName = core.monName
  local attachLevelIcons = core.attachLevelIcons
  local openSummary = core.openSummary

  local function playCry(game, species)
    pcall(function() require("src.core.Sound").playCry(game.data, species) end)
  end

  local function ensureStats(game, mon)
    local def = game.data.pokemon[mon.species]
    if def then Stats.ensure(def, mon) end
    return mon
  end

  local function healMon(game, mon)
    if type(mon) ~= "table" then return mon end
    if type(mon.stats) == "table" and mon.stats.hp then mon.hp = mon.stats.hp end
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    local movesData = game and game.data and game.data.moves
    if movesData and type(mon.moves) == "table" then
      local gen = GameVersion.generation()
      for _, mv in ipairs(mon.moves) do
        if type(mv) == "table" and mv.id then
          local def = movesData[mv.id]
          if def then
            if gen == 2 then
              mv.pp = mv.maxPp or def.pp
            else
              mv.pp = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)
            end
          end
        end
      end
    end
    return mon
  end

  local function healBank(game)
    if not (game and game.data) then return 0 end
    local s = loadStorage()
    local count = 0
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box) do
        healMon(game, mon)
        count = count + 1
      end
    end
    if count > 0 then markDirty() end
    return count
  end

  local function autoHealMon(trigger, game, mon)
    if game and mod.options:get("auto_heal") == trigger then healMon(game, mon) end
  end

  -- CRYSTAL_251 gives a mon its own held item on mon.heldItem instead of Gold's mon.item -- kept as a single field, whichever the active generation actually reads, cleared off the other so the id never sits duplicated on both.
  local function mirrorHeldItem(mon)
    if type(mon) ~= "table" then return end
    local value = mon.item or mon.heldItem
    if value == nil then return end
    if GameVersion.generation() == 2 then
      mon.item, mon.heldItem = value, nil
    else
      mon.heldItem, mon.item = value, nil
    end
  end

  -- An Egg's remaining incubation is Gold's mon.eggSteps or CRYSTAL_251's mon.eggCycles -- kept as a single field matching the active generation, not both, so a hatch on either side always finds it there.
  -- CRYSTAL_251 also keeps the moves an Egg already inherited off mon.moves and stashes them on mon.eggMoves instead; Gold puts them straight on mon.moves from the moment the Egg is made and has no eggMoves field at all. Reshaped to whichever shape the destination expects, so a hatch on either side always finds the real moveset on mon.moves.
  local function mirrorEggFields(mon)
    if type(mon) ~= "table" or mon.isEgg ~= true then return end
    local crystal251 = mod.find and mod.find("CRYSTAL_251")
    if mon.eggSteps ~= nil or mon.eggCycles ~= nil then
      local cycles = math.min(mon.eggSteps or mon.eggCycles, mon.eggCycles or mon.eggSteps)
      if GameVersion.generation() == 2 then
        mon.eggSteps, mon.eggCycles = cycles, nil
      else
        mon.eggCycles, mon.eggSteps = cycles, nil
      end
    end
    if crystal251 and GameVersion.generation() == 1 then
      if type(mon.moves) == "table" and #mon.moves > 0 then
        mon.eggMoves = mon.eggMoves or mon.moves
        mon.moves = {}
      end
    elseif type(mon.eggMoves) == "table" and #mon.eggMoves > 0
        and (type(mon.moves) ~= "table" or #mon.moves == 0) then
      mon.moves = mon.eggMoves
      mon.eggMoves = nil
    end
  end

  -- Gen1 keeps a move's PP Up count on mon.moves[i].ppUps and recomputes the raised cap on every read; Gen2 instead stores that raised cap directly as mon.moves[i].maxPp and never keeps a ppUps counter at all.
  local function reshapeMoves(game, mon)
    local movesData = game and game.data and game.data.moves
    if not (movesData and type(mon.moves) == "table") then return end
    local gen = GameVersion.generation()
    for _, mv in ipairs(mon.moves) do
      if type(mv) == "table" and mv.id then
        local def = movesData[mv.id]
        if def then
          local step = math.floor(def.pp / 5)
          if gen == 2 then
            if mv.maxPp == nil then
              mv.maxPp = def.pp + (mv.ppUps or 0) * step
            end
          elseif mv.ppUps == nil and mv.maxPp then
            mv.ppUps = step > 0 and math.max(0, math.min(3, math.floor((mv.maxPp - def.pp) / step + 0.5))) or 0
          end
        end
      end
    end
  end

  local STATUS_TO_GEN2 = { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze" }
  local STATUS_TO_GEN1 = { sleep = "SLP", poison = "PSN", toxic = "PSN", burn = "BRN", freeze = "FRZ", paralyze = "PAR" }

  local function reshapeStatus(mon)
    if type(mon) ~= "table" or mon.status == nil then return end
    if GameVersion.generation() == 2 then
      mon.status = STATUS_TO_GEN2[mon.status] or mon.status
    else
      mon.status = STATUS_TO_GEN1[mon.status] or mon.status
      mon.statusTurns = nil
      mon.toxicCounter = nil
    end
  end

  local function stampTrainer(game, mon)
    if type(mon) ~= "table" then return end
    local player = game and game.save and game.save.player
    if not player then return end
    mon.ot = player.name
    mon.otId = player.id
    mon.otName = player.name
  end

  -- An Egg's OT is stamped once, at creation, and Gold's own hatch preserves whatever is already there rather than re-stamping.
  -- CRYSTAL_251's own hatch already re-stamps ot/otId at hatch time regardless of what the egg already carries, so this only changes behavior for Gold's own Day Care.
  local function stampEggTrainer(game, mon)
    if mon and mon.isEgg then stampTrainer(game, mon) end
  end

  -- When INHERIT TRAINER is enabled: the withdrawing trainer becomes any Pokémon's OT, not just an Egg's. Deliberately NOT part of reshapeForActiveGame.
  local function stampNewTrainer(game, mon)
    if mod.options:get("inherit_trainer_on_withdraw") then stampTrainer(game, mon) end
  end

  -- Reshaped here, once, right before a withdrawn mon actually enters the currently active game -- recomputed with the target generation's own formula over the target generation's own base stats.
  local function reshapeForActiveGame(game, mon)
    if type(mon) ~= "table" then return mon end
    local expValue = mon.exp or mon.experience
    if expValue ~= nil then
      if GameVersion.generation() == 2 then
        mon.experience, mon.exp = expValue, nil
      else
        mon.exp, mon.experience = expValue, nil
      end
    end
    reshapeStatus(mon)
    mirrorHeldItem(mon)
    mirrorEggFields(mon)
    stampEggTrainer(game, mon)
    reshapeMoves(game, mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local baseStats = def and def.baseStats
    if not (baseStats and type(mon.stats) == "table") then return mon end
    if GameVersion.generation() == 2 then
      local Mon = require("src.battle.gen2.Mon")
      if baseStats.specialAttack and (mon.stats.specialAttack == nil or mon.stats.specialDefense == nil) then
        local computed = Mon.stats(baseStats, mon.dvs or {}, mon.level or 1, mon.statExp)
        mon.stats.specialAttack = mon.stats.specialAttack or computed.specialAttack
        mon.stats.specialDefense = mon.stats.specialDefense or computed.specialDefense
      end
      if mon.maxHp == nil then mon.maxHp = mon.stats.hp end
      if mon.types == nil then mon.types = def.types end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
      if mon.gender == nil then mon.gender = Mon.gender(def, mon.dvs or {}, { species = mon.species, level = mon.level }) end
    else
      if mon.stats.special == nil and baseStats.special then
        mon.stats.special = Stats.calc(def, mon.level or 1, mon.dvs or {}, mon.statExp).special
      end
      if mon.catchRate == nil then mon.catchRate = def.catchRate end
    end
    return mon
  end

  -- Mirrors Evolution's own seen/owned write. Never called on release or on a move that stays inside the Bank -- see API.md's withdrawPokemon entry.
  -- The "owned" field itself is named differently per generation -- owned on Red/Blue/Yellow, caught on Gold -- so this writes whichever one the active save actually has.
  local function registerDex(game, species)
    local dex = game and game.save and game.save.pokedex
    if not dex then return end
    if type(dex.seen) == "table" then dex.seen[species] = true end
    local owned = dex.owned or dex.caught
    if type(owned) == "table" then owned[species] = true end
  end

  -- ---------------------------------------------------------------------
  -- Pokémon storage
  -- ---------------------------------------------------------------------
  local function stampOrigin(mon)
    if type(mon) ~= "table" then return end
    if mon.originGame == nil then mon.originGame = GameVersion.get() end
    if mon.originGeneration == nil then mon.originGeneration = GameVersion.generation() end
  end

  -- A mon deposited before originGame/originGeneration existed carries neither field. If its OT id matches the save that's currently validating the Bank, that trainer's own game/generation is the best inference of where it actually came from, so it's backfilled here instead of staying blank forever.
  local function backfillOrigin(game, mon)
    if type(mon) ~= "table" then return false end
    if mon.originGame ~= nil and mon.originGeneration ~= nil then return false end
    local player = game and game.save and game.save.player
    if not (player and mon.otId ~= nil and mon.otId == player.id) then return false end
    local changed = false
    if mon.originGame == nil then
      mon.originGame = GameVersion.get()
      changed = true
    end
    if mon.originGeneration == nil then
      mon.originGeneration = GameVersion.generation()
      changed = true
    end
    return changed
  end

  -- Never refuses: normalizeBoxes guarantees the last box is always empty, so the search below always finds room there even when every earlier box is full.
  local function depositMon(mon)
    if type(mon) ~= "table" then return nil end
    stampOrigin(mon)
    local s = loadStorage()
    local n = #s.boxes
    local start = math.min(s.currentBox, n)
    for off = 0, n - 1 do
      local i = ((start - 1 + off) % n) + 1
      if #s.boxes[i] < BOX_CAPACITY then
        table.insert(s.boxes[i], mon)
        normalizeBoxes(s)
        markDirty()
        return i, #s.boxes[i]
      end
    end
    return nil
  end

  local moveId = core.moveEntryId

  local function isValidPokemon(mon, data)
    if type(mon) ~= "table" or type(data) ~= "table" then return false end
    local pokemon = data.pokemon
    if type(pokemon) ~= "table" or not pokemon[mon.species] then return false end
    if mon.isEgg and GameVersion.generation() == 1 and not (mod.find and mod.find("CRYSTAL_251")) then
      return false
    end
    return true
  end

  -- A held item can go stale the same way a bank item can -- an id from an uninstalled mod, or one this game's item table simply doesn't carry.
  -- Checked on every mon that stays valid, and quarantined into the same table bank-item validation uses, rather than a separate list.
  -- Cleared off BOTH fields at once and quarantined once, not once per field, treating them as two held items would double-count the one Pokémon is actually holding.
  local function checkHeldItem(game, mon, orphaned, lostItems)
    mirrorHeldItem(mon)
    local item = mon.item or mon.heldItem
    if not item then return false end
    local valid = mod.exports.isValidItem and mod.exports.isValidItem(item, game)
    local blacklisted = mod.exports.isBlacklisted and mod.exports.isBlacklisted(item, game)
    if valid and not blacklisted then return false end
    mon.item = nil
    mon.heldItem = nil
    orphaned.items[item] = (orphaned.items[item] or 0) + 1
    lostItems[#lostItems + 1] = { id = item, count = 1 }
    return true
  end

  -- Every bankId currently in use or still referenced, to check a freshly rolled one against: mons in the Bank's own boxes, quarantined mons in orphaned.mons, and orphaned.monMoves' own keys -- a mon that's already left the Bank still has moves waiting there under its bankId, so that id can never be handed to anyone else either.
  local function bankIdTaken(s, id)
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box) do
        if mon.bankId == id then return true end
      end
    end
    local orphaned = s.orphaned
    if orphaned then
      for _, mon in ipairs(orphaned.mons or {}) do
        if mon.bankId == id then return true end
      end
      if orphaned.monMoves and orphaned.monMoves[id] then return true end
    end
    return false
  end

  -- Every stored mon's permanent identity: assigned once, kept forever (withdraw/deposit never clear it), so orphaned.monMoves below can still find a specific mon after it's left the Bank for the party or a PC box. Random rather than sequential, so a bankId reveals nothing about deposit order or how many Pokémon have ever passed through the Bank -- collision-checked against bankIdTaken above rather than trusted to the odds alone, however small they already are at this range.
  local function assignBankId(s, mon)
    if type(mon) ~= "table" or mon.bankId ~= nil then return false end
    local id
    repeat
      id = math.random(1, 999999999)
    until not bankIdTaken(s, id)
    mon.bankId = id
    return true
  end

  -- A species-valid mon whose moveset includes an id the active game doesn't know sets aside just that move (not the whole moveset) under its own bankId in orphaned.monMoves, rather than quarantining the mon itself -- the mon stays put and keeps every move that's still valid, until RELEARN MOVE (lib/Moves.lua) brings back whichever set-aside moves are valid again. Merges into any bucket already there instead of overwriting it, and skips an id already present so re-validating twice never duplicates an entry.
  local function scrubInvalidMoves(s, mon, orphaned, data)
    if type(mon.moves) ~= "table" or #mon.moves == 0 then return false end
    local keep, bad = {}, {}
    for _, mv in ipairs(mon.moves) do
      local id = moveId(mv)
      if id and not data.moves[id] then
        bad[#bad + 1] = mv
      else
        keep[#keep + 1] = mv
      end
    end
    if #bad == 0 then return false end
    assignBankId(s, mon)
    local bucket = orphaned.monMoves[mon.bankId]
    if not bucket then
      bucket = {}
      orphaned.monMoves[mon.bankId] = bucket
    end
    for _, mv in ipairs(bad) do
      local id = moveId(mv)
      local dup = false
      for _, existing in ipairs(bucket) do
        if moveId(existing) == id then dup = true break end
      end
      if not dup then bucket[#bucket + 1] = mv end
    end
    mon.moves = keep
    return true
  end

  local function validateStorage(game)
    local data = game and game.data
    if not data then
      return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {}, lostItems = {} }
    end
    local s = loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local bankIdAssigned = false
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box) do
        if assignBankId(s, mon) then bankIdAssigned = true end
      end
    end
    for _, mon in ipairs(orphaned.mons) do
      if assignBankId(s, mon) then bankIdAssigned = true end
    end
    local quarantined, restored = 0, 0
    local lostMons, restoredMons, lostItems = {}, {}, {}
    local originBackfilled = false
    for boxNum = 1, #s.boxes do
      local box = s.boxes[boxNum]
      for idx = #box, 1, -1 do
        local mon = box[idx]
        if not isValidPokemon(mon, data) then
          table.remove(box, idx)
          orphaned.mons[#orphaned.mons + 1] = mon
          quarantined = quarantined + 1
          lostMons[#lostMons + 1] = { species = mon.species, from = "BOX " .. boxNum }
        else
          local heldChanged = checkHeldItem(game, mon, orphaned, lostItems)
          if backfillOrigin(game, mon) then originBackfilled = true end
          if heldChanged then markDirty() end
        end
      end
    end
    normalizeBoxes(s)
    local targetBoxNum = #s.boxes
    local targetBox = s.boxes[targetBoxNum]
    for idx = #orphaned.mons, 1, -1 do
      local mon = orphaned.mons[idx]
      if isValidPokemon(mon, data) then
        table.remove(orphaned.mons, idx)
        checkHeldItem(game, mon, orphaned, lostItems)
        if backfillOrigin(game, mon) then originBackfilled = true end
        -- Find space in current target box or create new if needed
        if #targetBox >= BOX_CAPACITY then
          s.boxes[#s.boxes + 1] = {}
          targetBoxNum = #s.boxes
          targetBox = s.boxes[targetBoxNum]
        end
        table.insert(targetBox, mon)
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = mon.species, box = targetBoxNum }
      end
    end
    normalizeBoxes(s)
    local scrubbed = 0
    for _, box in ipairs(s.boxes) do
      for _, mon in ipairs(box) do
        if scrubInvalidMoves(s, mon, orphaned, data) then scrubbed = scrubbed + 1 end
      end
    end
    return {
      changed = quarantined > 0 or restored > 0 or #lostItems > 0 or bankIdAssigned or scrubbed > 0 or originBackfilled,
      quarantined = quarantined,
      restored = restored,
      lostMons = lostMons,
      restoredMons = restoredMons,
      lostItems = lostItems,
    }
  end

  local function listInvalidMons()
    local out = {}
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.mons or {}
    for idx, mon in ipairs(orphaned) do
      out[#out + 1] = { index = idx, mon = mon }
    end
    return out
  end

  local function invalidMonCount()
    local s = loadStorage()
    local orphaned = s.orphaned and s.orphaned.mons or {}
    return #orphaned
  end

  local function withdrawMon(boxNum, idx)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    local mon = box and box[idx]
    if not mon then return nil end
    table.remove(box, idx)
    normalizeBoxes(s)
    markDirty()
    return mon
  end

  local function peekMon(boxNum, idx)
    local box = loadStorage().boxes[boxNum]
    return box and box[idx] or nil
  end

  local function moveMon(srcBox, srcIdx, destBox, destIdx)
    local s = loadStorage()
    local from = s.boxes[srcBox]
    local mon = from and from[srcIdx]
    if not mon then return false end
    if srcBox == destBox and destIdx == srcIdx then return false end
    local to = s.boxes[destBox]
    if not to then return false end
    local destMon = to[destIdx]
    if destMon then
      from[srcIdx], to[destIdx] = destMon, mon
      normalizeBoxes(s)
      markDirty()
      return true
    end
    if #to >= BOX_CAPACITY then return false, "full" end
    table.remove(from, srcIdx)
    table.insert(to, mon)
    normalizeBoxes(s)
    markDirty()
    return true
  end

  local function listMons()
    local out = {}
    local s = loadStorage()
    for boxNum, box in ipairs(s.boxes) do
      for idx, mon in ipairs(box) do
        out[#out + 1] = { box = boxNum, index = idx, mon = mon }
      end
    end
    return out
  end

  local function countMons()
    local n = 0
    for _, box in ipairs(loadStorage().boxes) do n = n + #box end
    return n
  end

  local function boxCount()
    return #loadStorage().boxes
  end

  -- =========================================================================
  -- Pokémon UI
  -- =========================================================================
  -- action + STATS + CANCEL, the vanilla PC's own per-mon submenu
  local function monSubmenu(game, action, mon, onAction)
    game.stack:push(Menu.new(game, {
      { label = action, onSelect = onAction },
      { label = "STATS", keepOpen = true, onSelect = function()
          ensureStats(game, mon)
          openSummary(game, mon)
        end },
      { label = "CANCEL" },
    }, { tx = 9, ty = 10, tw = 11, th = 8, noSound = true }))
  end

  local function openWithdrawList(game)
    local s = loadStorage()
    local boxNum = s.currentBox
    local box = s.boxes[boxNum]
    if #box == 0 then
      message(game, "What? There are\nno POKéMON here!")
      return
    end
    if #game.save.party >= Party.MAX then
      message(game, "You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst.")
      return
    end
    local items = {}
    for i, mon in ipairs(box) do
      items[#items + 1] = { label = monName(game, mon), value = i }
    end
    local list
    list = ListMenu.new(game, Strings("BOX %d (WITHDRAW)", boxNum), items, {
      noSound = true, wrap = true,
      onChoose = function(item)
        local mon = box[item.value]
        if not mon then return end
        monSubmenu(game, "WITHDRAW", mon, function()
          if #game.save.party >= Party.MAX then
            list.footer = "The party is full!"
            return
          end
          table.remove(box, item.value)
          normalizeBoxes(s)
          markDirty()
          reshapeForActiveGame(game, mon)
          stampNewTrainer(game, mon)
          autoHealMon("withdraw", game, mon)
          table.insert(game.save.party, mon)
          registerDex(game, mon.species)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn",
            { box = boxNum, index = item.value, mon = mon })
          local name = monName(game, mon)
          list:close()
          message(game, ("%s is\ntaken out.\vGot %s."):format(name, name))
        end)
      end,
    })
    attachLevelIcons(list, box)
    game.stack:push(list)
  end

  local function openDepositList(game)
    if #game.save.party <= 1 then
      message(game, "You can't deposit\nthe last Pokemon!")
      return
    end
    local items = {}
    for i, mon in ipairs(game.save.party) do
      items[#items + 1] = { label = monName(game, mon), value = i }
    end
    local list = ListMenu.new(game, "PARTY (DEPOSIT)", items, {
      noSound = true, wrap = true,
      onChoose = function(item, list)
        local mon = game.save.party[item.value]
        if not mon then return end
        monSubmenu(game, "DEPOSIT", mon, function()
          if #game.save.party <= 1 then
            list.footer = "You need at least\none POKéMON!"
            return
          end
          table.remove(game.save.party, item.value)
          ensureStats(game, mon)
          autoHealMon("deposit", game, mon)
          local boxNum, slot = depositMon(mon)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited",
            { box = boxNum, index = slot, mon = mon })
          local name = monName(game, mon)
          list:close()
          message(game, ("%s was\nstored in BANK BOX %d."):format(name, boxNum))
        end)
      end,
    })
    attachLevelIcons(list, game.save.party)
    game.stack:push(list)
  end

  local function openReleaseList(game)
    local s = loadStorage()
    local boxNum = s.currentBox
    local box = s.boxes[boxNum]
    if #box == 0 then
      message(game, "What? There are\nno POKéMON here!")
      return
    end
    local items = {}
    for i, mon in ipairs(box) do
      items[#items + 1] = { label = monName(game, mon), value = i }
    end
    local list = ListMenu.new(game, ("BOX %d (RELEASE)"):format(boxNum), items, {
      noSound = true, wrap = true,
      onChoose = function(_, list)
        local mon = box[list.index]
        if not mon then return end
        local name = monName(game, mon)
        game.stack:push(TextBox.new(game,
          Strings("Once released,\n%s is\ngone forever. OK?", name), function()
          game.stack:push(ChoiceBox.new(game, function(yes)
            if not yes then return end
            local current = box[list.index]
            if current ~= mon then
              message(game, "The selection changed.\nTry again.")
              return
            end
            table.remove(box, list.index)
            normalizeBoxes(s)
            markDirty()
            playCry(game, mon.species)
            mod.events:emit("mod.vrm_pokemon_bank.pokemon_released",
              { box = boxNum, index = list.index, mon = mon })
            message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
            list:removeCurrent()
          end, { defaultNo = true, noSound = true }))
        end))
      end,
    })
    attachLevelIcons(list, box)
    game.stack:push(list)
  end

  local function openChangeBoxList(game)
    local s = loadStorage()
    local items = {}
    for i = 1, #s.boxes do
      local mark = i == s.currentBox and "*" or " "
      items[#items + 1] = {
        label = ("%sBOX %d"):format(mark, i),
        right = ("%d/%d"):format(#s.boxes[i], BOX_CAPACITY),
        value = i,
      }
    end
    game.stack:push(ListMenu.new(game, "CHANGE BOX", items, {
      noSound = true, wrap = true,
      onChoose = function(item, list)
        local st = loadStorage()
        st.currentBox = math.max(1, math.min(#st.boxes, item.value))
        markDirty()
        list:close()
      end,
    }))
  end

  -- TRANSFER BOX: a two-step box picker.
  -- It commits the WHOLE box currently on screen as either the source or the destination, since this moves every Pokémon in a box in one go.
  -- Stage 1 ("source"): SELECT still alternates BANK/PC, and A on a non-empty box locks it in as the source and flips to the other storage.
  -- Stage 2 ("destination"): SELECT is locked out (the whole point is the other storage), A asks to confirm before calling the bulk exports.
  local function openTransferBoxList(game)
    Boxes.ensure(game.save)
    local state = {
      stage = "source",
      view = "bank",
      bankBox = loadStorage().currentBox,
      pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
      source = nil,
    }

    local screen = { isOpaque = true }
    local list
    local rebuild, backHandler

    local function currentBoxNum()
      return state.view == "bank" and state.bankBox or state.pcBox
    end

    local function currentBox()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox]
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return Strings("BANK BOX %d", state.bankBox)
      else return Strings("PC BOX %d", state.pcBox) end
    end

    local function cycleView()
      if state.stage == "destination" then return end -- locked to the other storage
      state.view = (state.view == "bank") and "pc" or "bank"
      rebuild()
    end

    local function cycleBox(delta)
      if state.view == "bank" then
        local n = #loadStorage().boxes
        if n <= 1 then return end
        state.bankBox = ((state.bankBox - 1 + delta) % n) + 1
      else
        state.pcBox = ((state.pcBox - 1 + delta) % Boxes.COUNT) + 1
      end
      rebuild()
    end

    local function performTransfer()
      local src = state.source
      local destBoxNum = currentBoxNum()
      state.stage = "source"
      state.source = nil
      if src.view == "bank" then
        local result = mod.exports.withdrawToBox(game, destBoxNum, { boxNum = src.box, indices = nil })
        local transferred = result and #result.withdrawn or 0
        if transferred > 0 then
          local msg = Strings("Transferred %d\nPOKéMON to\nPC BOX %d.", transferred, destBoxNum)
          if result.remaining > 0 then msg = msg .. Strings("\n%d remained.", result.remaining) end
          message(game, msg)
        else
          message(game, "No POKéMON\ntransferred.\nPC may be full.")
        end
      else
        local result = mod.exports.depositBoxPokemon(game, src.box, { boxNum = destBoxNum, indices = nil })
        local transferred = result and #result or 0
        if transferred > 0 then
          message(game, Strings("Transferred %d\nPOKéMON to\nthe BANK.", transferred))
        else
          message(game, "No POKéMON\ntransferred.")
        end
      end
      rebuild()
    end

    local function confirmTransfer()
      local src = state.source
      local srcLabel = src.view == "bank" and Strings("BANK BOX %d", src.box) or Strings("PC BOX %d", src.box)
      local destLabel = viewTitle()
      game.stack:push(TextBox.new(game,
        Strings("Transfer %s\nto %s?", srcLabel, destLabel), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if yes then performTransfer() end
        end, { defaultNo = true, noSound = true }))
      end))
    end

    local function chooseThisBox()
      if state.stage == "source" then
        if #currentBox() == 0 then
          message(game, "What? There are\nno POKéMON here!")
          return
        end
        state.source = { view = state.view, box = currentBoxNum() }
        state.stage = "destination"
        state.view = (state.view == "bank") and "pc" or "bank"
        rebuild()
      else
        confirmTransfer()
      end
    end

    -- Shared by screen:update's own "b" handling and the Gen1 Modern UI adapter's "back" action below, so a touch/mouse BACK does exactly what the B button does.
    backHandler = function()
      if state.stage == "destination" then
        state.view = state.source.view
        state.stage = "source"
        state.source = nil
        rebuild()
      else
        game.stack:pop()
      end
    end

    rebuild = function()
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local box = currentBox()
      local rows = {}
      for i, mon in ipairs(box) do
        rows[#rows + 1] = { label = monName(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, { noSound = true, rows = 6, wrap = true })
      attachLevelIcons(list, box)
      list.footer = state.stage == "source"
        and ("A: PICK BOX\nSELECT: " .. (state.view == "bank" and "PC" or "BANK"))
        or "A: CONFIRM"
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("left") then
        cycleBox(-1)
        return
      elseif input:wasPressed("right") then
        cycleBox(1)
        return
      elseif input:wasPressed("a") then
        chooseThisBox()
        return
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      local total = #list.items
      local text = Strings("%d/%d", total > 0 and list.index or 0, total)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, 160 - 8 - Font.width(text), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Gen1 Modern UI compatibility surface: read-only accessors plus semantic actions so the presenter can paint this screen, and a touch/mouse user can drive it
    screen.screenId = TRANSFER_BOX_SCREEN_ID
    screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
      title = function() return viewTitle() end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseThisBox()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
    })

    rebuild()
    game.stack:push(screen)
  end

  -- Direct PARTY <-> PC moves bypass the Bank entirely (nothing here ever touches loadStorage()/markDirty) -- only reachable from the MOVE screen below, so these stay local instead of joining the exports table.
  local function pcToParty(game, pcBoxNum, index)
    Boxes.ensure(game.save)
    if #game.save.party >= Party.MAX then return false end
    local box = game.save.boxes[pcBoxNum]
    local mon = box and box[index]
    if not mon then return false end
    -- mirrors BoxMenu.withdraw's own Stats.ensure: a box mon carries no stat block on some imported .sav files
    Stats.ensure(game.data.pokemon[mon.species], mon)
    table.remove(box, index)
    table.insert(game.save.party, mon)
    return true
  end

  local function partyToPc(game, index, startPcBoxNum)
    Boxes.ensure(game.save)
    local mon = game.save.party[index]
    if not mon then return false end
    for off = 0, Boxes.COUNT - 1 do
      local i = ((startPcBoxNum - 1 + off) % Boxes.COUNT) + 1
      local box = game.save.boxes[i]
      if #box < Boxes.CAPACITY then
        table.remove(game.save.party, index)
        table.insert(box, mon)
        return true, i
      end
    end
    return false
  end

  -- MOVE <PK><MN>: SELECT cycles BANK > PARTY > PC, on BANK/PC, Left/Right cycles boxes. A on a Pokémon opens TO <other two storages>/SWITCH/STATS/RELEASE/CANCEL.
  -- SWITCH pins the source slot and stays armed while Left/Right keeps browsing boxes, so the target can be anywhere in the same storage.
  local function openMoveList(game)
    Boxes.ensure(game.save)
    local state = {
      view = "bank",
      bankBox = loadStorage().currentBox,
      pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
      pendingSwap = nil,
    }

    local screen = { isOpaque = true }
    local list -- current ListMenu; rebuilt on every view/box/data change

    local rebuild, performMove, releaseCurrent, completeSwitch, openMonActions, backHandler, chooseCurrent

    local function currentList()
      if state.view == "bank" then return loadStorage().boxes[state.bankBox]
      elseif state.view == "party" then return game.save.party
      else return game.save.boxes[state.pcBox] end
    end

    local function viewTitle()
      if state.view == "bank" then return Strings("BANK BOX %d", state.bankBox)
      elseif state.view == "party" then return "PARTY"
      else return Strings("PC BOX %d", state.pcBox) end
    end

    -- BANK > PARTY > PC > BANK, matching cycleView below -- what SELECT switches TO from the current view, for the footer hint.
    local function nextViewName()
      if state.view == "bank" then return "PARTY"
      elseif state.view == "party" then return "PC"
      else return "BANK" end
    end

    local function cycleView()
      if state.pendingSwap then return end
      if state.view == "bank" then state.view = "party"
      elseif state.view == "party" then state.view = "pc"
      else state.view = "bank" end
      rebuild()
    end

    local function cycleBox(delta)
      if state.view == "bank" then
        local n = #loadStorage().boxes
        if n <= 1 then return end
        state.bankBox = ((state.bankBox - 1 + delta) % n) + 1
        rebuild()
      elseif state.view == "pc" then
        state.pcBox = ((state.pcBox - 1 + delta) % Boxes.COUNT) + 1
        rebuild()
      end
    end

    performMove = function(destView, idx)
      local srcView = state.view
      if destView == "party" and #game.save.party >= Party.MAX then
        return false, "The party is full!"
      end
      if destView == "bank" then
        if srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local deposited = mod.exports.depositPartyPokemon(game, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\nBANK BOX %d.", deposited[1].box)
        elseif srcView == "pc" then
          local deposited = mod.exports.depositBoxPokemon(game, state.pcBox, { indices = { idx }, boxNum = state.bankBox })
          if not deposited or #deposited == 0 then return false, "It didn't work!" end
          return true, Strings("Stored in\nBANK BOX %d.", deposited[1].box)
        end
      elseif destView == "party" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToParty(game, { boxNum = state.bankBox, indices = { idx } })
          if not result or #result.withdrawn == 0 then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        elseif srcView == "pc" then
          if not pcToParty(game, state.pcBox, idx) then return false, "It didn't work!" end
          return true, "Added to\nthe PARTY."
        end
      elseif destView == "pc" then
        if srcView == "bank" then
          local result = mod.exports.withdrawToBox(game, state.pcBox, { boxNum = state.bankBox, indices = { idx } })
          if not result or #result.withdrawn == 0 then return false, "PC BOX is full!" end
          return true, Strings("Stored in\nPC BOX %d.", result.withdrawn[1].pcBox)
        elseif srcView == "party" then
          if #game.save.party <= 1 then return false, "You need at least\none POKéMON!" end
          local ok, placedBox = partyToPc(game, idx, state.pcBox)
          if not ok then return false, "PC BOX is full!" end
          return true, Strings("Stored in\nPC BOX %d.", placedBox)
        end
      end
      return false, "It didn't work!"
    end

    completeSwitch = function(targetIdx)
      local pending = state.pendingSwap
      state.pendingSwap = nil
      if pending and pending.view == state.view then
        if state.view == "party" then
          if pending.index ~= targetIdx then
            local party = game.save.party
            party[pending.index], party[targetIdx] = party[targetIdx], party[pending.index]
          end
        elseif state.view == "bank" then
          if not (pending.box == state.bankBox and pending.index == targetIdx) then
            mod.exports.movePokemon(pending.box, pending.index, state.bankBox, targetIdx)
          end
        else -- pc
          if not (pending.box == state.pcBox and pending.index == targetIdx) then
            local from = game.save.boxes[pending.box]
            local to = game.save.boxes[state.pcBox]
            if pending.box == state.pcBox then
              from[pending.index], from[targetIdx] = from[targetIdx], from[pending.index]
            else
              from[pending.index], to[targetIdx] = to[targetIdx], from[pending.index]
            end
          end
        end
      end
      rebuild()
    end

    releaseCurrent = function(idx, mon)
      if state.view == "party" and #game.save.party <= 1 then
        message(game, "You can't release\nyour last POKéMON!")
        return
      end
      local name = monName(game, mon)
      game.stack:push(TextBox.new(game,
        Strings("Once released,\n%s is\ngone forever. OK?", name), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then return end
          local src = currentList()
          local current = src[idx]
          if current ~= mon then
            message(game, "The selection changed.\nTry again.")
            return
          end
          table.remove(src, idx)
          if state.view == "bank" then
            local st = loadStorage()
            normalizeBoxes(st)
            markDirty()
            mod.events:emit("mod.vrm_pokemon_bank.pokemon_released",
              { box = state.bankBox, index = idx, mon = mon })
          end
          playCry(game, mon.species)
          message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
          rebuild()
        end, { defaultNo = true, noSound = true }))
      end))
    end

    openMonActions = function(mon, idx)
      local view = state.view
      local rows = {}
      local function addTo(label, destView)
        rows[#rows + 1] = { label = label, onSelect = function()
          local _, msg = performMove(destView, idx)
          rebuild()
          list.footer = msg
        end }
      end
      if view ~= "bank" then addTo("TO BANK", "bank") end
      if view ~= "party" then addTo("TO PARTY", "party") end
      if view ~= "pc" then addTo("TO PC", "pc") end
      rows[#rows + 1] = { label = "SWITCH", onSelect = function()
        state.pendingSwap = {
          view = view,
          box = (view == "bank" and state.bankBox) or (view == "pc" and state.pcBox) or nil,
          index = idx,
        }
        rebuild()
      end }
      rows[#rows + 1] = { label = "STATS", keepOpen = true, onSelect = function()
        ensureStats(game, mon)
        openSummary(game, mon)
      end }
      rows[#rows + 1] = { label = "RELEASE", onSelect = function() releaseCurrent(idx, mon) end }
      rows[#rows + 1] = { label = "CANCEL" }
      local th = #rows * 2 + 2
      game.stack:push(Menu.new(game, rows, { tx = 9, ty = math.max(0, 18 - th), tw = 11, th = th, noSound = true }))
    end

    rebuild = function()
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local src = currentList()
      local rows = {}
      for i, mon in ipairs(src) do
        rows[#rows + 1] = { label = monName(game, mon), value = i }
      end
      list = ListMenu.new(game, viewTitle(), rows, {
        noSound = true,
        rows = 6,
        wrap = true,
        onChoose = function(item)
          if state.pendingSwap then
            completeSwitch(item.value)
            return
          end
          local mon = src[item.value]
          if not mon then return end
          openMonActions(mon, item.value)
        end,
      })
      attachLevelIcons(list, src)
      list.footer = "\nSELECT: " .. nextViewName()
      local pending = state.pendingSwap
      if pending and pending.view == state.view then
        local sameBox = state.view == "party"
          or (state.view == "bank" and pending.box == state.bankBox)
          or (state.view == "pc" and pending.box == state.pcBox)
        if sameBox then list.swapIndex = pending.index end
        list.footer = "Choose a POKéMON\nto switch with."
      end
    end

    -- Shared by screen:update's own "b" handling and the Gen1 Modern UI adapter's "back" action below.
    backHandler = function()
      if state.pendingSwap then
        state.pendingSwap = nil
        rebuild()
      else
        game.stack:pop()
      end
    end

    -- Whatever pressing A on the highlighted row would do -- list.onChoose already branches on state.pendingSwap itself, so this is the one thing the Gen1 Modern UI "select" action needs to reuse.
    chooseCurrent = function()
      core.chooseListCurrent(list, function() game.stack:pop() end)
    end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("left") then
        cycleBox(-1)
        return
      elseif input:wasPressed("right") then
        cycleBox(1)
        return
      elseif input:wasPressed("b") then
        backHandler()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      local total = #list.items
      local text = Strings("%d/%d", total > 0 and list.index or 0, total)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, 160 - 8 - Font.width(text), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Gen1 Modern UI compatibility surface -- see the TRANSFER BOX screen above (openTransferBoxList) for the full explanation.
    screen.screenId = MOVE_SCREEN_ID
    screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
      title = function() return viewTitle() end,
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(list, payload) end
        chooseCurrent()
      end,
      back = function() backHandler() end,
      start = function() cycleView() end,
    })

    rebuild()
    game.stack:push(screen)
  end

  -- WITHDRAW / DEPOSIT / RELEASE / MOVE / TRANSFER BOX / CHANGE BOX / CANCEL, keepOpen so each sub-list leaves this menu underneath it.
  local function BankBoxMenu(game)
    local rows = {
      { label = "MOVE <PK><MN>", keepOpen = true, onSelect = function() openMoveList(game) end },
      { label = "WITHDRAW <PK><MN>", keepOpen = true, onSelect = function() openWithdrawList(game) end },
      { label = "DEPOSIT <PK><MN>", keepOpen = true, onSelect = function() openDepositList(game) end },
      { label = "RELEASE <PK><MN>", keepOpen = true, onSelect = function() openReleaseList(game) end },
      { label = "TRANSFER BOX", keepOpen = true, onSelect = function() openTransferBoxList(game) end },
      { label = "CHANGE BOX", keepOpen = true, onSelect = function() openChangeBoxList(game) end },
      { label = "CANCEL" },
    }
    local th = #rows * 2 + 2
    return Menu.new(game, rows, { tx = 0, ty = 0, tw = 14, th = th, noSound = true })
  end

  mod.content.screens:register(SCREEN_ID, { new = BankBoxMenu })

  local pokemonTab = core.makeTabToggle("show_pokemon_tab")
  local tabEnabled = pokemonTab.enabled

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.boxCount = boxCount
  mod.exports.boxCapacity = function() return BOX_CAPACITY end

  mod.exports.depositPokemon = function(mon, opts)
    if type(mon) ~= "table" then return nil, "invalid pokemon" end
    opts = opts or {}
    if opts.game then
      ensureStats(opts.game, mon)
      autoHealMon("deposit", opts.game, mon)
    end
    local boxNum, slot = depositMon(mon)
    mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", { box = boxNum, index = slot, mon = mon })
    return boxNum, slot
  end

  mod.exports.withdrawPokemon = function(boxNum, index, game)
    local mon = withdrawMon(boxNum, index)
    if mon then
      if game then
        reshapeForActiveGame(game, mon)
        stampNewTrainer(game, mon)
        autoHealMon("withdraw", game, mon)
      end
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = boxNum, index = index, mon = mon })
    end
    return mon
  end

  mod.exports.getPokemon = peekMon

  mod.exports.getBox = function(boxNum)
    local s = loadStorage()
    local box = s.boxes[boxNum]
    if not box then return nil end
    local copy = {}
    for i = 1, BOX_CAPACITY do copy[i] = box[i] end
    return copy
  end

  mod.exports.movePokemon = moveMon

  mod.exports.releasePokemon = function(boxNum, index)
    local mon = withdrawMon(boxNum, index)
    if mon then
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_released", { box = boxNum, index = index, mon = mon })
    end
    return mon ~= nil
  end

  mod.exports.listPokemon = listMons
  mod.exports.pokemonCount = countMons

  mod.exports.healBank = healBank

  mod.exports.isValidPokemon = function(mon, game)
    return isValidPokemon(mon, game and game.data)
  end
  mod.exports.validatePokemonStorage = validateStorage

  mod.exports.reshapeForActiveGame = reshapeForActiveGame
  mod.exports.reshapeMoves = reshapeMoves
  mod.exports.reshapeStatus = reshapeStatus

  mod.exports.listInvalidPokemon = listInvalidMons
  mod.exports.invalidPokemonCount = invalidMonCount

  local function validIndices(indices, n)
    for _, idx in ipairs(indices) do
      if type(idx) ~= "number" or idx < 1 or idx > n then return false end
    end
    return true
  end

  local function allIndices(n)
    local t = {}
    for i = 1, n do t[#t + 1] = i end
    return t
  end

  -- Shared by every bulk deposit/withdraw export below: collects the mons at `indices` off `source`, in the caller's own order, then asks `place(mon, originalIdx)` to move each one into its destination. `place` returns a result table on success or nil to leave that mon where it is (a full destination); every mon `place` accepted is then removed from `source`, in descending index order so an earlier removal never shifts a later one. Returns the successful results and how many entries were left behind.
  local function bulkTransfer(source, indices, place)
    local entries = {}
    for _, idx in ipairs(indices) do
      entries[#entries + 1] = { mon = source[idx], originalIdx = idx }
    end
    local results, removedIdx = {}, {}
    for _, entry in ipairs(entries) do
      local result = place(entry.mon, entry.originalIdx)
      if result then
        results[#results + 1] = result
        removedIdx[#removedIdx + 1] = entry.originalIdx
      end
    end
    table.sort(removedIdx, function(a, b) return a > b end)
    for _, idx in ipairs(removedIdx) do table.remove(source, idx) end
    return results, #entries - #results
  end

  -- Builds a bulkTransfer `place` callback that deposits each mon into the Bank's own boxes, searching from `startBoxNum` and continuing wherever the last mon actually landed -- shared by depositPartyPokemon and depositBoxPokemon, the only two bulk paths that deposit INTO the Bank.
  local function depositPlacer(game, s, startBoxNum)
    local currentBoxNum = startBoxNum
    return function(mon)
      if game then ensureStats(game, mon) end
      autoHealMon("deposit", game, mon)
      stampOrigin(mon)
      for off = 0, #s.boxes - 1 do
        local boxNum = ((currentBoxNum - 1 + off) % #s.boxes) + 1
        if #s.boxes[boxNum] < BOX_CAPACITY then
          table.insert(s.boxes[boxNum], mon)
          currentBoxNum = boxNum
          return { box = boxNum, index = #s.boxes[boxNum], mon = mon }
        end
      end
      -- Should not happen due to normalizeBoxes guarantee, but handle gracefully
      s.boxes[#s.boxes + 1] = {}
      table.insert(s.boxes[#s.boxes], mon)
      currentBoxNum = #s.boxes
      return { box = #s.boxes, index = 1, mon = mon }
    end
  end

  -- Bulk deposit from party
  mod.exports.depositPartyPokemon = function(game, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum -- nil = last box
    local indices = opts.indices -- nil = 2..last (keep first)

    if not game or not game.save or not game.save.party then
      return nil, "invalid game"
    end

    local party = game.save.party
    if #party < 2 then
      return nil, "need at least 2 pokemon in party"
    end

    -- Default indices: keep first, deposit rest
    if not indices then
      indices = {}
      for i = 2, #party do indices[#indices + 1] = i end
    end
    if not validIndices(indices, #party) then return nil, "invalid index" end
    if #party - #indices < 1 then
      return nil, "must keep at least 1 pokemon in party"
    end

    local s = loadStorage()
    local deposited = bulkTransfer(party, indices, depositPlacer(game, s, targetBoxNum or #s.boxes))

    normalizeBoxes(s)
    markDirty()

    for _, entry in ipairs(deposited) do
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry)
    end

    return deposited
  end

  -- Bulk deposit from PC box
  mod.exports.depositBoxPokemon = function(game, pcBoxNum, opts)
    opts = opts or {}
    local targetBoxNum = opts.boxNum
    local indices = opts.indices
    if not game or not game.save or not game.save.boxes then
      return nil, "invalid game"
    end
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)
    local pcBox = game.save.boxes[pcBoxNum]
    if not pcBox then return nil, "invalid pc box" end
    if #pcBox == 0 then return nil, "pc box is empty" end

    indices = indices or allIndices(#pcBox)
    if not validIndices(indices, #pcBox) then return nil, "invalid index" end

    local s = loadStorage()
    local deposited = bulkTransfer(pcBox, indices, depositPlacer(game, s, targetBoxNum or #s.boxes))

    normalizeBoxes(s)
    markDirty()

    for _, entry in ipairs(deposited) do
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_deposited", entry)
    end

    return deposited
  end

  -- Bulk withdraw to party
  mod.exports.withdrawToParty = function(game, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum -- nil = first non-empty box
    local indices = opts.indices -- nil = all

    if not game or not game.save or not game.save.party then
      return nil, "invalid game"
    end

    local party = game.save.party
    local s = loadStorage()

    -- Default source box: first non-empty box
    if not sourceBoxNum then
      sourceBoxNum = 1
      while sourceBoxNum <= #s.boxes and #s.boxes[sourceBoxNum] == 0 do
        sourceBoxNum = sourceBoxNum + 1
      end
      if sourceBoxNum > #s.boxes then return nil, "bank is empty" end
    end

    local sourceBox = s.boxes[sourceBoxNum]
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end

    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end

    if Party.MAX - #party <= 0 then return nil, "party is full" end

    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      if #party >= Party.MAX then return nil end
      reshapeForActiveGame(game, mon)
      stampNewTrainer(game, mon)
      autoHealMon("withdraw", game, mon)
      table.insert(party, mon)
      registerDex(game, mon.species)
      mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
      return { mon = mon }
    end)

    normalizeBoxes(s)
    markDirty()

    return { withdrawn = withdrawn, remaining = remainingCount }
  end

  -- Bulk withdraw to PC box
  mod.exports.withdrawToBox = function(game, targetPcBoxNum, opts)
    opts = opts or {}
    local sourceBoxNum = opts.boxNum -- nil = first non-empty box
    local indices = opts.indices -- nil = all
    if not game or not game.save or not game.save.boxes then
      return nil, "invalid game"
    end
    local Boxes = require("src.pokemon.Boxes")
    Boxes.ensure(game.save)
    if not game.save.boxes[targetPcBoxNum] then return nil, "invalid target pc box" end
    local s = loadStorage()
    -- Default source box: first non-empty box
    if not sourceBoxNum then
      sourceBoxNum = 1
      while sourceBoxNum <= #s.boxes and #s.boxes[sourceBoxNum] == 0 do
        sourceBoxNum = sourceBoxNum + 1
      end
      if sourceBoxNum > #s.boxes then return nil, "bank is empty" end
    end
    local sourceBox = s.boxes[sourceBoxNum]
    if not sourceBox then return nil, "invalid bank box" end
    if #sourceBox == 0 then return nil, "bank box is empty" end

    indices = indices or allIndices(#sourceBox)
    if not validIndices(indices, #sourceBox) then return nil, "invalid index" end

    local currentPcBoxNum = targetPcBoxNum
    local withdrawn, remainingCount = bulkTransfer(sourceBox, indices, function(mon, originalIdx)
      -- Try to place in current or subsequent PC boxes
      for off = 0, Boxes.COUNT - 1 do
        local boxNum = ((currentPcBoxNum - 1 + off) % Boxes.COUNT) + 1
        local box = game.save.boxes[boxNum]
        if box and #box < Boxes.CAPACITY then
          reshapeForActiveGame(game, mon)
          stampNewTrainer(game, mon)
          autoHealMon("withdraw", game, mon)
          table.insert(box, mon)
          registerDex(game, mon.species)
          mod.events:emit("mod.vrm_pokemon_bank.pokemon_withdrawn", { box = sourceBoxNum, index = originalIdx, mon = mon })
          currentPcBoxNum = boxNum
          return { mon = mon, pcBox = boxNum }
        end
      end
      return nil
    end)

    normalizeBoxes(s)
    markDirty()
    return { withdrawn = withdrawn, remaining = remainingCount }
  end

  mod.exports.pokemonScreenId = SCREEN_ID

  mod.exports.setPokemonTabEnabled = pokemonTab.setEnabled
  mod.exports.isPokemonTabEnabled = tabEnabled

  mod.log:info("Pokemon Bank: Pokemon tab ready")

  return {
    screenId = SCREEN_ID,
    transferBoxScreenId = TRANSFER_BOX_SCREEN_ID,
    moveScreenId = MOVE_SCREEN_ID,
    tabEnabled = tabEnabled,
    validateStorage = validateStorage,
    withdrawMon = withdrawMon,
    depositMon = depositMon,
  }
end

return Module
