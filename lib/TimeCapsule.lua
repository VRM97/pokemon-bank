local V = ...

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Menu = require("src.ui.Menu")
local ListMenu = require("src.ui.ListMenu")
local Boxes = require("src.pokemon.Boxes")
local Party = require("src.pokemon.Party")
local GenerationMap = V.require("GenerationMap")
local Pickers = V.require("Pickers")

local SCREEN_ID = "PokemonBankTimeCapsule"
local WITHDRAW_SCREEN_ID = "PokemonBankTimeCapsuleWithdraw"
-- The highest generation this recomp currently has a playable game for. A Pokémon can only ever move forward across this ladder, never back down it
local MAX_SUPPORTED_GENERATION = 2
local DEPOSIT_REFUSAL = {
  egg = "An EGG can't go\nin TIME CAPSULE.",
  held_item = "Remove its held\nitem first.",
  no_next_generation = "There's nowhere\nfurther to go.",
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

  local function capsuleMons() return core.loadStorage().timeCapsule end

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
    if not legalityCheckPasses(mon, game) then return false, "illegal" end
    return true
  end

  local function removeFromSource(game, loc, mon)
    if loc.view == "bank" then
      return Pokemon.withdrawMon(loc.box, loc.index) == mon
    elseif loc.view == "pc" then
      local box = game.save.boxes[loc.box]
      if not box or box[loc.index] ~= mon then return false end
      table.remove(box, loc.index)
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

  function TimeCapsule.validateStorage(game)
    local data = game and game.data
    if not data then return { changed = false, quarantined = 0, restored = 0, lostMons = {}, restoredMons = {} } end
    local s = core.loadStorage()
    local orphaned = core.ensureOrphaned(s)
    local mons = capsuleMons()
    local quarantined, restored = 0, 0
    local lostMons, restoredMons = {}, {}
    local isValid = mod.exports.isValidPokemon
    for idx = #mons, 1, -1 do
      local mon = mons[idx]
      if not (isValid and isValid(mon, game)) then
        table.remove(mons, idx)
        orphaned.timeCapsule[#orphaned.timeCapsule + 1] = mon
        quarantined = quarantined + 1
        lostMons[#lostMons + 1] = { species = mon.species, from = "TIME CAPSULE" }
      end
    end
    for idx = #orphaned.timeCapsule, 1, -1 do
      local mon = orphaned.timeCapsule[idx]
      if isValid and isValid(mon, game) then
        table.remove(orphaned.timeCapsule, idx)
        mons[#mons + 1] = mon
        restored = restored + 1
        restoredMons[#restoredMons + 1] = { species = mon.species, to = "TIME CAPSULE" }
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

  local function openDepositPicker(game)
    local handle
    handle = Pickers.openMonPicker(mod, core, game, {
      dynamicFooter = function(mon, view, nextLabel)
        local speciesLine = mon and Pokemon.speciesName(game, mon) or ""
        local selectLine = nextLabel and ("SELECT: " .. nextLabel) or ""
        return speciesLine .. "\n" .. selectLine
      end,
      onChoose = function(mon, loc)
        local ok, reason = canDeposit(mon, game)
        if not ok then
          handle.setFooter(DEPOSIT_REFUSAL[reason] or "It didn't work!")
          return
        end
        if not removeFromSource(game, loc, mon) then
          handle.setFooter("The selection changed.")
          return
        end
        mon.minGeneration = GameVersion.generation() + 1
        mon.timeCapsuleItemByte = timeCapsuleItemByte(game, mon.species)
        table.insert(capsuleMons(), mon)
        markDirty()
        core.playSound(game, "Withdraw_Deposit")
        handle.refresh()
        handle.setFooter("Sent to the\nTIME CAPSULE!")
      end,
    })
  end

  local function eligibleForWithdraw(mon) return GameVersion.generation() >= (mon.minGeneration or 0) end

  local function placeInto(game, view, boxNum, mon)
    if view == "bank" then
      local s = core.loadStorage()
      s.currentBox = math.max(1, math.min(#s.boxes, boxNum))
      local placedBox = mod.exports.depositPokemon(mon, { game = game })
      return placedBox ~= nil
    end
    if view == "party" then
      if #game.save.party >= Party.MAX then return false end
      table.insert(game.save.party, mon)
      return true
    end
    Boxes.ensure(game.save)
    for off = 0, Boxes.COUNT - 1 do
      local i = ((boxNum - 1 + off) % Boxes.COUNT) + 1
      local box = game.save.boxes[i]
      if #box < Boxes.CAPACITY then
        table.insert(box, mon)
        return true
      end
    end
    return false
  end

  local function checkWithdraw(game, mon)
    if GameVersion.generation() < (mon.minGeneration or 0) then return false, "generation" end
    mon.species = GenerationMap.translateSpeciesId(mon.species)
    if type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        if type(mv) == "table" and mv.id then mv.id = GenerationMap.translateMoveId(mv.id) end
      end
    end

    if not game.data.pokemon[mon.species] then return false, "species" end
    if type(mon.moves) == "table" then
      for _, mv in ipairs(mon.moves) do
        local id = core.moveEntryId(mv)
        local proxy = { species = mon.species, isEgg = false }
        if not (mod.exports.canLearn and mod.exports.canLearn(game, proxy, id)) then
          return false, "move"
        end
      end
    end

    if not legalityCheckPasses(mon, game) then
      if legalityMode() == "force_fix" and tryFix(mon, game) then return true end
      return false, "illegal"
    end
    return true
  end

  local function commitWithdraw(game, mon)
    mod.exports.reshapeForActiveGame(game, mon)
    if mod.exports.registerDex then mod.exports.registerDex(game, mon.species) end
    if not (mon.item or mon.heldItem) then
      local item = itemIdForByte(game, mon.timeCapsuleItemByte)
      if item then mon.item = item end
    end
    mon.timeCapsuleItemByte = nil
    mon.minGeneration = GameVersion.generation()
  end

  local function destinationHasRoom(game, view, boxNum)
    if view == "bank" then return true end
    if view == "party" then return #game.save.party < Party.MAX end
    Boxes.ensure(game.save)
    for off = 0, Boxes.COUNT - 1 do
      local i = ((boxNum - 1 + off) % Boxes.COUNT) + 1
      if #game.save.boxes[i] < Boxes.CAPACITY then return true end
    end
    return false
  end

  local function openWithdrawList(game)
    local list
    local screen = { isOpaque = true, screenId = WITHDRAW_SCREEN_ID }

    local function refresh(preserveCursor)
      local oldIndex = preserveCursor and list and list.index
      local rows = {}
      for i, mon in ipairs(capsuleMons()) do
        rows[#rows + 1] = { label = core.monName(game, mon), value = i }
      end
      if list then
        list.items = rows
        core.attachLevelIcons(list, capsuleMons())
        if oldIndex then core.setListCursor(list, oldIndex) end
      end
      return rows
    end

    local function checkWithdrawOnce(index)
      local mon = capsuleMons()[index]
      if not mon then return nil, "It didn't work!" end
      local ok, reason = checkWithdraw(game, mon)
      if not ok then return nil, WITHDRAW_REFUSAL[reason] or "It didn't work!" end
      return mon
    end

    local function commitWithdrawTo(index, mon, destView, destBox)
      if capsuleMons()[index] ~= mon then return false, "The selection changed." end
      if not destinationHasRoom(game, destView, destBox) then return false, "There's no room\nthere." end
      commitWithdraw(game, mon)
      if not placeInto(game, destView, destBox, mon) then return false, "It didn't work!" end
      table.remove(capsuleMons(), index)
      markDirty()
      return true
    end

    local function finishWithdrawTo(index, mon, destView, destBox)
      local ok, msg = commitWithdrawTo(index, mon, destView, destBox)
      if ok then
        core.playSound(game, "Withdraw_Deposit")
        refresh(true)
        list.footer = "Transferred!"
      else
        refresh(true)
        list.footer = msg
      end
    end

    local function attemptWithdrawTo(index, destView)
      local destBox = destView == "pc" and (game.save.currentBox or 1) or nil
      local mon, msg = checkWithdrawOnce(index)
      if mon then
        finishWithdrawTo(index, mon, destView, destBox)
        return
      end
      if msg == WITHDRAW_REFUSAL.illegal and legalityMode() == "fix" then
        local target = capsuleMons()[index]
        core.confirm(game, "This POKéMON\nneeds to be fixed.\nOK?", function(yes)
          if yes and target and tryFix(target, game) then
            finishWithdrawTo(index, target, destView, destBox)
          else
            refresh(true)
            list.footer = msg
          end
        end, { defaultNo = true, noSound = true })
        return
      end
      refresh(true)
      list.footer = msg
    end

    local function releaseCurrent(index, mon)
      local name = core.monName(game, mon)
      core.confirmRelease(game, name, function(yes)
        if not yes then return end
        if capsuleMons()[index] ~= mon then
          list.footer = "The selection changed."
          return
        end
        table.remove(capsuleMons(), index)
        markDirty()
        -- box is nil (TIME CAPSULE has none); VIEW STATS' own RELEASE
        -- count only listens for the event firing, not this payload
        mod.events:emit("mod.vrm_pokemon_bank.pokemon_released", { box = nil, index = index, mon = mon })
        core.playCry(game, mon.species)
        refresh(true)
        core.message(game, Strings("%s was\nreleased.\fBye %s!", name, name))
      end)
    end

    local function openMonActions(index)
      local mon = capsuleMons()[index]
      if not mon then return end
      local rows = {}
      local function appendRow(label, onSelect, keepOpen) rows[#rows + 1] = { label = label, onSelect = onSelect, keepOpen = keepOpen } end
      if mod.options:get("storage_mode") ~= "time_capsule" then appendRow("TO BANK", function() attemptWithdrawTo(index, "bank") end) end
      appendRow("TO PARTY", function() attemptWithdrawTo(index, "party") end)
      appendRow("TO PC", function() attemptWithdrawTo(index, "pc") end)
      appendRow("STATS", function() core.openSummary(game, mon) end, true)
      appendRow("RELEASE", function() releaseCurrent(index, mon) end)
      appendRow("CANCEL")
      core.rowActionsMenu(game, rows)
    end

    local function startWithdrawAll()
      local eligible = {}
      for i, mon in ipairs(capsuleMons()) do
        if eligibleForWithdraw(mon) then eligible[#eligible + 1] = i end
      end
      if #eligible == 0 then return end
      core.confirm(game, Strings("Transfer all %d\nPOKéMON?", #eligible), function(yes)
        if not yes then return end
        Pickers.openBoxPicker(mod, core, game, {
          requireNonEmpty = false,
          hideBank = mod.options:get("storage_mode") == "time_capsule",
          onChoose = function(view, boxNum)
            game.stack:pop()
            local ready, needingFix, refused = {}, {}, 0
            for _, idx in ipairs(eligible) do
              local mon, msg = checkWithdrawOnce(idx)
              if mon then
                ready[#ready + 1] = idx
              elseif msg == WITHDRAW_REFUSAL.illegal and legalityMode() == "fix" then
                needingFix[#needingFix + 1] = idx
              else refused = refused + 1 end
            end
            local function finish(toCommit, refusedCount)
              local order = {}
              for _, idx in ipairs(toCommit) do order[#order + 1] = idx end
              table.sort(order, function(a, b) return a > b end)
              local moved = 0
              for _, idx in ipairs(order) do
                local mon = capsuleMons()[idx]
                if mon and commitWithdrawTo(idx, mon, view, boxNum) then moved = moved + 1 else refusedCount = refusedCount + 1 end
              end
              if moved > 0 then core.playSound(game, "Withdraw_Deposit") end
              refresh(true)
              local footerMsg
              if moved == 0 then
                footerMsg = refusedCount > 0 and Strings("Nothing moved,\n%d refused.", refusedCount) or "Nothing moved."
              elseif refusedCount == 0 then
                footerMsg = Strings("Transferred %d\nPOKéMON.", moved)
              else footerMsg = Strings("Transferred %d,\n%d refused.", moved, refusedCount) end
              list.footer = footerMsg
            end
            if #needingFix == 0 then
              finish(ready, refused)
              return
            end
            core.confirm(game, Strings("%d POKéMON need\nto be fixed. OK?", #needingFix), function(fixYes)
              local toCommit = ready
              local extraRefused = 0
              for _, idx in ipairs(needingFix) do
                local mon = capsuleMons()[idx]
                if fixYes and mon and tryFix(mon, game) then
                  toCommit[#toCommit + 1] = idx
                else extraRefused = extraRefused + 1 end
              end
              finish(toCommit, refused + extraRefused)
            end, { defaultNo = true, noSound = true })
          end,
        })
      end, { defaultNo = true, noSound = true })
    end

    list = ListMenu.new(game, "TIME CAPSULE", refresh(), {
      messageBox = true, noSound = true, wrap = true,
      onChoose = function(item) openMonActions(item.value) end,
    })
    core.attachLevelIcons(list, capsuleMons())
    core.attachDynamicFooter(list, function(l)
      local item = l.items[l.index]
      local mon = item and capsuleMons()[item.value]
      local speciesLine = mon and Pokemon.speciesName(game, mon) or ""
      return speciesLine .. "\nA: PICK  ST: ALL"
    end)

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("start") then
        startWithdrawAll()
        return
      elseif input:wasPressed("b") then
        game.stack:pop()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
      core.drawListTitle(list)
      core.drawListCounter(list)
    end

    game.stack:push(screen)
  end

  local function TimeCapsuleMenu(game)
    local rows = {
      { label = "DEPOSIT <PK><MN>", keepOpen = true, onSelect = function() openDepositPicker(game) end },
      { label = "WITHDRAW <PK><MN>", keepOpen = true, onSelect = function() openWithdrawList(game) end },
      { label = "CANCEL" },
    }
    local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 14, th = #rows * 2 + 2, noSound = true })
    local screen = { isOpaque = false }
    function screen:update(dt) menu:update(dt) end
    function screen:draw()
      menu:draw()
      local Font = require("src.render.Font")
      local text = Strings("CAPSULE: %d", #capsuleMons())
      local tw = math.floor(Font.width(text) / 8) + 3
      local tx, ty = 20 - tw, 15
      Font.drawBox(tx, ty, tw, 3)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(text, (tx + 2) * 8, (ty + 1) * 8)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return screen
  end
  mod.content.screens:register(SCREEN_ID, { new = TimeCapsuleMenu })

  -- =========================================================================
  -- Public API for other mods. See API.md for the full reference.
  -- =========================================================================
  mod.exports.timeCapsuleScreenId = SCREEN_ID
  mod.exports.timeCapsuleWithdrawScreenId = WITHDRAW_SCREEN_ID
  mod.exports.isTimeCapsuleEnabled = function() return mod.options:get("storage_mode") ~= "bank" end
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
