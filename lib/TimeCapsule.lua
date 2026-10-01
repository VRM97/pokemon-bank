local V = ...

local Species = V.require("Species")
local BoxAccess = V.require("BoxAccess")
local BagAccess = V.require("BagAccess")
local MoveSet = V.require("MoveSet")

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Party = require("src.pokemon.Party")
local GenerationMap = V.require("GenerationMap")

local SCREEN_ID = "PokemonBankTimeCapsule"
local MAX_SUPPORTED_GENERATION = 3
local DEPOSIT_REFUSAL = {
  egg = "An EGG can't go\nin TIME CAPSULE.",
  held_item = "Remove its held\nitem first.",
  no_next_generation = "There's nowhere\nfurther to go.",
  origin = "It's from a newer\ngeneration.",
  illegal = "It's not legal to\ndeposit right now.",
}
local WITHDRAW_REFUSAL = {
  generation = "It can't go\nbackward in time!",
  species = "Unknown in this\ngame.",
  move = "It knows a move\nunknown here.",
  illegal = "It's not legal\nto withdraw now.",
}
local CATCH_RATE_ITEM_OVERRIDES = {
  [25] = "LEFTOVERS",
  [45] = "BITTER_BERRY",
  [50] = "GOLD_BERRY",
  [90] = "BERRY",
  [100] = "BERRY",
  [120] = "BERRY",
  [190] = "BERRY",
  [255] = "BERRY",
}
local GEN3_ITEM_BY_CATCH_RATE = {
  [3] = "BRIGHTPOWDER",
  [9] = "ANTIDOTE",
  [25] = "LEFTOVERS",
  [27] = "PROTEIN",
  [30] = "LUCKY_PUNCH",
  [35] = "METAL_POWDER",
  [45] = "PERSIM_BERRY",
  [50] = "SITRUS_BERRY",
  [65] = "ELIXIR",
  [90] = "ORAN_BERRY",
  [96] = "TWISTEDSPOON",
  [100] = "ORAN_BERRY",
  [120] = "ORAN_BERRY",
  [150] = "LEPPA_BERRY",
  [163] = "LIGHT_BALL",
  [190] = "ORAN_BERRY",
  [255] = "ORAN_BERRY",
}
local YELLOW_ITEM_BYTE_OVERRIDES = {
  PIKACHU = 163,
  KADABRA = 96,
  DRAGONAIR = 27,
  DRAGONITE = 9
}

local Module = {}

Module.screenId = SCREEN_ID

function Module.install(mod, core, Pokemon)

  local TimeCapsule = { screenId = SCREEN_ID }
  local markDirty = core.markDirty
  local loadStorage = core.loadStorage

  local function capsuleMons() return loadStorage().entries.timeCapsule end

  local function legalityMode()
    local v = mod.options:get("legality_checks")
    if v == true then return "reject" end
    if v == false then return "off" end
    return v
  end

  local function legalityCheckPasses(mon, game)
    if legalityMode() == "off" or not mod.exports.isLegal then return true end
    return mod.exports.isLegal(mon, game) and true or false
  end

  local function tryFix(mon, game) return mod.exports.tryFixLegality and mod.exports.tryFixLegality(mon, game) end

  local function canDeposit(mon, game)
    if type(mon) ~= "table" then return false, "no_pokemon" end
    if mon.isEgg then return false, "egg" end
    if mon.item or mon.heldItem then return false, "held_item" end
    if GameVersion.generation() >= MAX_SUPPORTED_GENERATION then return false, "no_next_generation" end
    if (tonumber(mon.originGeneration) or GameVersion.generation()) > GameVersion.generation() then return false, "origin" end
    if not legalityCheckPasses(mon, game) then return false, "illegal" end
    return true
  end

  local function removeFromSource(game, loc, mon)
    if loc.view == "bank" then
      return Pokemon.withdrawMon(loc.box, loc.index) == mon
    elseif loc.view == "pc" then
      local box = BoxAccess.box(game, loc.box)
      if not box or box[loc.index] ~= mon then return false end
      BoxAccess.take(box, loc.index)
      return true
    else
      local party = game.save.party
      if #party <= 1 then return false end
      if party[loc.index] ~= mon then return false end
      table.remove(party, loc.index)
      return true
    end
  end

  local function timeCapsuleItemByte(game, species)
    local def = game.data.pokemon[species]
    local byte = def and tonumber(def.catchRate)
    if GameVersion.isYellow() then byte = YELLOW_ITEM_BYTE_OVERRIDES[species] or byte end
    return byte
  end

  local function itemIdForByte(game, byte)
    if not byte then return nil end
    local override = CATCH_RATE_ITEM_OVERRIDES[byte]
    if override then return override end
    for id, def in pairs(game.data.items or {}) do
      if type(def) == "table" and def.index == byte then return id end
    end
    return nil
  end

  local function gen3ItemName(ref)
    local number = ref and BagAccess.itemNumber(ref)
    return number and number ~= 0 and BagAccess.itemName(number) or nil
  end

  local function gen3WildItem(game, mon)
    local ok, P = pcall(require, "src.core.game3.pokemon")
    if not (ok and type(P) == "table" and P.speciesMeta) then return nil end
    local meta = P.speciesMeta(Species.number(mon) or Species.toNumber(game, Species.key(mon)))
    if not meta then return nil end
    local common, rare = tonumber(meta.itemCommon) or 0, tonumber(meta.itemRare) or 0
    return gen3ItemName(common ~= 0 and common or rare ~= 0 and rare or nil)
  end

  local function arrivalItem(game, mon)
    local generation = GameVersion.generation()
    if generation == 2 then return itemIdForByte(game, mon.timeCapsuleItemByte) end
    if generation ~= 3 then return nil end
    return gen3ItemName(GEN3_ITEM_BY_CATCH_RATE[mon.timeCapsuleItemByte]) or gen3WildItem(game, mon)
  end

  function TimeCapsule.validateStorage(game)
    local data = game and game.data
    if not data then return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {} } end
    local s = core.loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local mons = capsuleMons()
    local quarantined, restored = 0, 0
    local lostMons, restoredMons = {}, {}
    local isValid = mod.exports.isValidPokemon
    local reshape = mod.exports.reshapeForActiveGame
    for idx = #mons, 1, -1 do
      local mon = mons[idx]
      if not (isValid and isValid(mon, game)) then
        table.remove(mons, idx)
        orphaned.timeCapsule[#orphaned.timeCapsule + 1] = mon
        quarantined = quarantined + 1
        lostMons[#lostMons + 1] = { species = Species.key(mon), from = "TIME CAPSULE" }
      else
        reshape(game, mon)
        markDirty()
      end
    end
    for idx = #orphaned.timeCapsule, 1, -1 do
      local mon = orphaned.timeCapsule[idx]
      if isValid and isValid(mon, game) then
        table.remove(orphaned.timeCapsule, idx)
        reshape(game, mon)
        mons[#mons + 1] = mon
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = Species.key(mon), to = "TIME CAPSULE" }
      end
    end
    return {
      changed = quarantined > 0 or restored > 0,
      quarantined = quarantined,
      restored = restored,
      lostMons = lostMons,
      restoredMons = restoredMons,
    }
  end

  local function performDepositIntoCapsule(game, srcView, boxNum, index)
    local mon = srcView == "bank" and loadStorage().entries.boxes[boxNum].content[index] or srcView == "pc" and BoxAccess.box(game, boxNum)[index] or game.save.party[index]
    if not mon then return false, nil, "It didn't work!" end
    local ok, reason = canDeposit(mon, game)
    if not ok then return false, nil, DEPOSIT_REFUSAL[reason] or "It didn't work!" end
    if not removeFromSource(game, { view = srcView, box = boxNum, index = index }, mon) then return false, nil, "The selection changed." end
    mon.minGeneration = GameVersion.generation() + 1
    mon.timeCapsuleItemByte = GameVersion.generation() == 1 and timeCapsuleItemByte(game, Species.key(mon)) or nil
    table.insert(capsuleMons(), mon)
    markDirty()
    core.emitAction("timeCapsule", "deposit", nil, { mon = mon })
    if srcView == "bank" then core.emitAction("boxes", "withdraw", nil, { mon = mon }) end
    return true, mon, "Sent to the\nTIME CAPSULE!"
  end

  local function checkWithdraw(game, mon)
    if GameVersion.generation() < (mon.minGeneration or 0) then return false, "generation" end
    if GameVersion.generation() == 3 then mon.fatefulEncounter = true end
    Species.setText(mon, GenerationMap.translateSpeciesId(Species.key(mon)))
    if type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        if type(mv) == "table" and mv.id then mv.id = GenerationMap.translateMoveId(mv.id) end
      end
    end

    if not game.data.pokemon[Species.key(mon)] then return false, "species" end
    if type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        local id = type(mv) == "number" and MoveSet.toText(game, mv) or core.moveEntryId(mv)
        local known = id and (type(mv) == "number" or (game.data.moves and game.data.moves[id] ~= nil))
        if not known then return false, "move" end
      end
    end

    if not legalityCheckPasses(mon, game) then
      if legalityMode() == "force_fix" and tryFix(mon, game) then return true end
      return false, "illegal"
    end
    return true
  end

  local function commitWithdraw(game, mon)
    if mod.exports.registerDex then mod.exports.registerDex(game, Species.key(mon)) end
    if not (mon.item or mon.heldItem) then
      local item = arrivalItem(game, mon)
      if item then
        BagAccess.setHeldItem(mon, item)
      end
    end
    mon.timeCapsuleItemByte = nil
    mon.minGeneration = GameVersion.generation()
  end

  local function placeInto(game, view, boxNum, mon)
    if view == "bank" then
      core.setCurrentBox(boxNum)
      local placedBox = mod.exports.depositPokemon(mon, { game = game })
      return placedBox ~= nil
    end
    if view == "party" then
      if #game.save.party >= Party.MAX then return false end
      table.insert(game.save.party, mon)
      return true
    end
    local count = BoxAccess.count()
    for off = 0, count - 1 do
      local i = ((boxNum - 1 + off) % count) + 1
      if BoxAccess.insert(BoxAccess.box(game, i), mon) then return true end
    end
    return false
  end

  local function destinationHasRoom(game, view, boxNum)
    if view == "bank" then return true end
    if view == "party" then return #game.save.party < Party.MAX end
    local count = BoxAccess.count()
    for off = 0, count - 1 do
      local i = ((boxNum - 1 + off) % count) + 1
      if not BoxAccess.isFull(BoxAccess.box(game, i)) then return true end
    end
    return false
  end

  local function checkWithdrawOnce(game, index)
    local mon = capsuleMons()[index]
    if not mon then return nil, "It didn't work!" end
    local ok, reason = checkWithdraw(game, mon)
    if not ok then return nil, WITHDRAW_REFUSAL[reason] or "It didn't work!" end
    return mon
  end

  local function commitWithdrawTo(game, index, mon, destView, destBox)
    if capsuleMons()[index] ~= mon then return false, "The selection changed." end
    if not destinationHasRoom(game, destView, destBox) then return false, "There's no room\nthere." end
    commitWithdraw(game, mon)
    if not placeInto(game, destView, destBox, mon) then return false, "It didn't work!" end
    table.remove(capsuleMons(), index)
    markDirty()
    core.emitAction("timeCapsule", "withdraw", nil, { mon = mon })
    return true
  end

  local function finishWithdrawTo(game, index, mon, destView, destBox, rebuild, list, env)
    local ok, msg = commitWithdrawTo(game, index, mon, destView, destBox)
    rebuild(true)
    if ok then
      core.playSound(game, "Withdraw_Deposit")
      core.currentList(env, list).footer = "Transferred!"
    else
      core.currentList(env, list).footer = msg
    end
  end

  local function releaseCapsuleMon(game, index, mon, rebuild, list, env)
    local name = core.monName(game, mon)
    core.confirmRelease(game, name, function(yes)
      if not yes then return end
      if capsuleMons()[index] ~= mon then
        rebuild(true)
        core.currentList(env, list).footer = "The selection changed."
        return
      end
      table.remove(capsuleMons(), index)
      markDirty()
      core.emitAction("timeCapsule", "remove", "pokemon_released", { box = nil, index = index, mon = mon })
      core.playCry(game, Species.key(mon))
      rebuild(true)
      core.message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
    end)
  end

  local function bulkWithdrawFromCapsule(game, _, row, destView, env)
    local destBox = env.pageOf(destView)
    local mon = checkWithdrawOnce(game, row)
    if not mon then return false end
    return commitWithdrawTo(game, row, mon, destView, destBox) and true or false
  end

  local function fromExistingContainer(base, overrides)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(overrides) do out[k] = v end
    out.onStart = nil
    out.canListPages = nil
    out.listPagesActions = nil
    out.listPagesColumns, out.listPagesIcon, out.listPagesOnStart, out.listPagesFooter = nil, nil, nil, nil
    out.canRearrangePages = nil
    out.onMovePage = nil
    out.onMove = nil
    out.canRearrange = nil
    out.canRearrangeBetweenPages = nil
    out.columns = nil
    out.icon = nil
    return out
  end

  local function depositActionRow(srcView)
    return { label = "TO TIME CAPSULE", onSelect = function(game, pageId, row, rebuild, list, env)
      local ok, _, msg = performDepositIntoCapsule(game, srcView, pageId, row)
      if ok then core.playSound(game, "Withdraw_Deposit") end
      rebuild(true)
      core.currentList(env, list).footer = msg
    end }
  end

  local function statsRowAt(getMon)
    return { label = "STATS", keepOpen = true, onSelect = function(game, pageId, row)
      local mon = getMon(game, pageId, row)
      if mon then core.openSummary(game, mon) end
    end }
  end

  local function withdrawOnSelect(destView)
    return function(game, _, row, rebuild, list, env)
      local destBox = env.pageOf(destView)
      local mon, msg = checkWithdrawOnce(game, row)
      if mon then
        finishWithdrawTo(game, row, mon, destView, destBox, rebuild, list, env)
        return
      end
      if msg == WITHDRAW_REFUSAL.illegal and legalityMode() == "fix" then
        local target = capsuleMons()[row]
        core.confirm(game, "This POKéMON\nneeds to be fixed.\nOK?", function(yes)
          if yes and target and tryFix(target, game) then
            finishWithdrawTo(game, row, target, destView, destBox, rebuild, list, env)
          else
            rebuild(true)
            core.currentList(env, list).footer = msg
          end
        end, { defaultNo = true, noSound = true })
        return
      end
      rebuild(true)
      core.currentList(env, list).footer = msg
    end
  end

  local timeCapsuleContainer = {
    id = "capsule", label = "TIME CAPSULE",
    build = function(game)
      local rows, mons = {}, {}
      for i, mon in ipairs(capsuleMons()) do rows[i], mons[i] = { label = core.monName(game, mon), value = i }, mon end
      return rows, { messageBox = true, noSound = true, wrap = true }, mons
    end,
    dynamicFooter = function(game, _, row, nextLabel)
      local mon = capsuleMons()[row]
      return Strings("%s\nSELECT: %s", mon and Pokemon.speciesName(game, mon) or "", nextLabel)
    end,
    canTransfer = true,
    canWithdraw = false,
    withdraw = bulkWithdrawFromCapsule,
    deposit = function() end,
    onAction = {
      core.transferGroup({
        { label = "TO BANK", visible = function() return Pokemon.tabEnabled() end, onSelect = withdrawOnSelect("bank") },
        { label = "TO PARTY", onSelect = withdrawOnSelect("party") },
        { label = "TO PC", onSelect = withdrawOnSelect("pc") },
      }),
      statsRowAt(function(_, _, row) return capsuleMons()[row] end),
      { label = "RELEASE", onSelect = function(game, _, row, rebuild, list, env)
          local mon = capsuleMons()[row]
          if mon then releaseCapsuleMon(game, row, mon, rebuild, list, env) end
        end },
    },
  }

  local bankForCapsule = fromExistingContainer(Pokemon.containers[1], {
    canTransfer = false, withdraw = false, deposit = function() end,
    onAction = { depositActionRow("bank"), statsRowAt(function(_, pageId, row) return loadStorage().entries.boxes[pageId].content[row] end) },
  })
  local partyForCapsule = fromExistingContainer(Pokemon.containers[2], {
    canTransfer = false, withdraw = false, deposit = function() end,
    onAction = { depositActionRow("party"), statsRowAt(function(game, _, row) return game.save.party[row] end) },
  })
  local pcForCapsule = fromExistingContainer(Pokemon.containers[3], {
    canTransfer = false, withdraw = false, deposit = function() end,
    onAction = { depositActionRow("pc"), statsRowAt(function(game, pageId, row) return BoxAccess.box(game, pageId)[row] end) },
  })

  local function TimeCapsuleScreen(game)
    return core.entryScreen(game, { timeCapsuleContainer, bankForCapsule, partyForCapsule, pcForCapsule }, {
      screenId = SCREEN_ID,
      counter = true,
    })
  end
  mod.content.screens:register(SCREEN_ID, { new = TimeCapsuleScreen })

  local timeCapsuleTab = core.entryTab("timeCapsule", "show_time_capsule_tab")
  TimeCapsule.tabEnabled = timeCapsuleTab.shown

  mod.exports.timeCapsuleScreenId = SCREEN_ID
  mod.exports.isTimeCapsuleTabEnabled = TimeCapsule.tabEnabled
  mod.exports.setTimeCapsuleTabEnabled = timeCapsuleTab.setEnabled
  mod.exports.timeCapsulePokemonCount = function() return #capsuleMons() end
  mod.exports.listTimeCapsulePokemon = function()
    local out = {}
    for i, mon in ipairs(capsuleMons()) do out[#out + 1] = { index = i, mon = mon } end
    return out
  end
  mod.exports.validateTimeCapsuleStorage = TimeCapsule.validateStorage
  mod.exports.invalidTimeCapsulePokemonCount = function()
    local orphaned = core.loadStorage().orphaned
    return orphaned and #orphaned.timeCapsule or 0
  end
  mod.exports.listInvalidTimeCapsulePokemon = function()
    local orphaned = core.loadStorage().orphaned
    local out = {}
    for i, mon in ipairs(orphaned and orphaned.timeCapsule or {}) do out[#out + 1] = { index = i, mon = mon } end
    return out
  end
  mod.log:info("Pokemon Bank: Time Capsule ready")
  return TimeCapsule
end

return Module
