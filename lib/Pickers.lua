local V = ...

local Boxes = require("src.pokemon.Boxes")
local Bag = require("src.inventory.Bag")

local VIEW_LABELS = { bank = "BANK", party = "PARTY", pc = "PC", bag = "BAG" }

local Pickers = {
  MON_PICKER_SCREEN_ID = "PokemonBankMonPicker",
  ITEM_PICKER_SCREEN_ID = "PokemonBankItemPicker",
  BOX_PICKER_SCREEN_ID = "PokemonBankBoxPicker"
}

function Pickers.openMonPicker(mod, core, game, opts)
  opts = opts or {}
  local views = {}
  if not opts.hideBank then views[#views + 1] = "bank" end
  if not opts.hideParty then views[#views + 1] = "party" end
  if not opts.hidePc then views[#views + 1] = "pc" end
  if #views == 0 then return nil, "no views enabled" end
  Boxes.ensure(game.save)
  local loadStorage = core.loadStorage
  local state = {
    bankBox = loadStorage().currentBox,
    pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
  }

  local function boxNumFor(view)
    if view == "bank" then return state.bankBox
    elseif view == "pc" then return state.pcBox
    else return nil end
  end

  local function currentList()
    if state.view == "bank" then return loadStorage().boxes[state.bankBox]
    elseif state.view == "party" then return game.save.party
    else return game.save.boxes[state.pcBox] end
  end

  local function defaultTitle()
    if state.view == "bank" then return core.boxLabel(loadStorage(), state.bankBox)
    elseif state.view == "party" then return "PARTY"
    else return core.pcBoxLabel(game, state.pcBox) end
  end

  local function viewTitle()
    if opts.title then return opts.title(state.view, boxNumFor(state.view)) end
    return defaultTitle()
  end

  local group, cycleBox
  local backHandler = core.cancelHandler(game, opts)

  cycleBox = function(delta)
    if state.view == "bank" then
      state.bankBox = core.cycleBoxNumber(state.bankBox, #loadStorage().boxes, delta)
      group.rebuild()
    elseif state.view == "pc" then
      state.pcBox = core.cycleBoxNumber(state.pcBox, Boxes.COUNT, delta)
      group.rebuild()
    end
  end

  group = core.listGroup(game, {
    screenId = Pickers.MON_PICKER_SCREEN_ID,
    counter = true,
    views = views,
    state = state,
    startView = opts.startView,
    onClose = backHandler,
    title = viewTitle,
    label = function(view) return VIEW_LABELS[view] end,
    footer = opts.footer,
    dynamicFooter = opts.dynamicFooter and function(view, item, nextLabel)
      local mon = item and currentList()[item.value]
      return opts.dynamicFooter(mon, view, nextLabel)
    end or nil,
    build = function()
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local src = currentList()
      local rows = {}
      for i, mon in ipairs(src) do
        local sub = opts.rowRight and opts.rowRight(mon, state.view, boxNumFor(state.view), i)
        rows[#rows + 1] = { label = core.monName(game, mon), value = i, sub = sub }
      end
      local listOpts = {
        messageBox = true, noSound = true, rows = opts.rows, wrap = true,
        onChoose = function(item)
          local mon = src[item.value]
          if not mon then return end
          if opts.onChoose then
            opts.onChoose(mon, { view = state.view, box = boxNumFor(state.view), index = item.value })
          end
        end,
      }
      return rows, listOpts, not opts.rowRight and src or nil
    end,
    extraKeys = function(input)
      if input:wasPressed("left") then cycleBox(-1); return true end
      if input:wasPressed("right") then cycleBox(1); return true end
      return false
    end,
    modernUi = {
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function(payload)
        if payload then core.setListCursor(group.screen.list, payload) end
        core.chooseListCurrent(group.screen.list, backHandler)
      end,
    },
  })

  game.stack:push(group.screen)

  return core.pickerHandle(game, group)
end

function Pickers.openMovePicker(mod, core, game, opts)
  opts = opts or {}
  if type(opts.compatible) ~= "function" then return nil, "opts.compatible required" end
  local wrapped = {}
  for k, v in pairs(opts) do wrapped[k] = v end
  wrapped.rowRight = function(mon)
    return opts.compatible(mon) and "ABLE" or "---"
  end
  return Pickers.openMonPicker(mod, core, game, wrapped)
end

function Pickers.openItemPicker(mod, core, game, opts)
  opts = opts or {}
  local views = {}
  if not opts.hideBank then views[#views + 1] = "bank" end
  if not opts.hideBag then views[#views + 1] = "bag" end
  if not opts.hidePc then views[#views + 1] = "pc" end
  if #views == 0 then return nil, "no views enabled" end

  game.save.pcItems = game.save.pcItems or {}
  local loadStorage = core.loadStorage
  local state = {}

  local function currentCounts()
    if state.view == "bank" then return loadStorage().items
    elseif state.view == "bag" then return game.save.inventory
    else return game.save.pcItems end
  end

  local function currentIds()
    if state.view == "bag" then return Bag.order(game.save) end
    return core.sortedItemIds(game, currentCounts())
  end

  local function viewTitle()
    if opts.title then return opts.title(state.view) end
    return VIEW_LABELS[state.view]
  end

  local group
  local backHandler = core.cancelHandler(game, opts)

  group = core.listGroup(game, {
    screenId = Pickers.ITEM_PICKER_SCREEN_ID,
    counter = true,
    views = views,
    state = state,
    startView = opts.startView,
    onClose = backHandler,
    title = viewTitle,
    label = function(view) return VIEW_LABELS[view] end,
    footer = opts.footer,
    build = function()
      local counts = currentCounts()
      local rows = {}
      for _, id in ipairs(currentIds()) do
        local count = counts[id]
        if count and count > 0 then
          local right = opts.rowRight and opts.rowRight(id, count, state.view) or ("x" .. tostring(count))
          rows[#rows + 1] = { value = id, label = core.truncateName(core.itemName(game, id)), right = right }
        end
      end
      local listOpts = {
        messageBox = true, noSound = true, wrap = true,
        onChoose = function(item)
          local count = counts[item.value]
          if not count or count <= 0 then return end
          if opts.onChoose then opts.onChoose(item.value, count, state.view) end
        end,
      }
      return rows, listOpts
    end,
    modernUi = {
      select = function(payload)
        if payload then core.setListCursor(group.screen.list, payload) end
        core.chooseListCurrent(group.screen.list, backHandler)
      end,
    },
  })
  game.stack:push(group.screen)
  return core.pickerHandle(game, group)
end

function Pickers.openBoxPicker(mod, core, game, opts)
  opts = opts or {}
  local views = {}
  if not opts.hideBank then views[#views + 1] = "bank" end
  if not opts.hidePc then views[#views + 1] = "pc" end
  if #views == 0 then return nil, "no views enabled" end

  Boxes.ensure(game.save)
  local loadStorage = core.loadStorage
  local state = {
    bankBox = loadStorage().currentBox,
    pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
  }

  local function currentBoxNum() return state.view == "bank" and state.bankBox or state.pcBox end
  local function currentBox()
    if state.view == "bank" then return loadStorage().boxes[state.bankBox]
    else return game.save.boxes[state.pcBox] end
  end

  local function viewTitle()
    if opts.title then return opts.title(state.view, currentBoxNum()) end
    return state.view == "bank" and core.boxLabel(loadStorage(), state.bankBox) or core.pcBoxLabel(game, state.pcBox)
  end

  local group, cycleBox, chooseThisBox

  cycleBox = function(delta)
    if state.view == "bank" then
      state.bankBox = core.cycleBoxNumber(state.bankBox, #loadStorage().boxes, delta)
    else
      state.pcBox = core.cycleBoxNumber(state.pcBox, Boxes.COUNT, delta)
    end
    group.rebuild()
  end

  chooseThisBox = function()
    local box = currentBox()
    if opts.requireNonEmpty ~= false and #box == 0 then
      group.screen.list.footer = opts.emptyMessage or "What? There are\nno POKéMON here!"
      return
    end
    if opts.onChoose then opts.onChoose(state.view, currentBoxNum()) end
  end

  local backHandler = core.cancelHandler(game, opts)

  group = core.listGroup(game, {
    screenId = Pickers.BOX_PICKER_SCREEN_ID,
    counter = true,
    views = views,
    state = state,
    startView = opts.startView,
    onClose = backHandler,
    title = viewTitle,
    label = function(view) return VIEW_LABELS[view] end,
    -- BoxPicker's own default footer isn't just "SELECT: NEXT" so this always overrides listGroup's own default, whether or not the caller gave its own opts.footer.
    footer = function(view, nextLabel)
      if opts.footer then return opts.footer(view, currentBoxNum(), nextLabel) end
      local hint = nextLabel and ("SELECT: " .. nextLabel .. "\n") or ""
      return hint .. "A: CONFIRM"
    end,
    build = function()
      core.clampBoxState(state, loadStorage, Boxes.COUNT)
      local box = currentBox()
      local rows = {}
      for i, mon in ipairs(box) do
        rows[#rows + 1] = { label = core.monName(game, mon), value = i }
      end
      return rows, { messageBox = true, noSound = true, wrap = true }, box
    end,
    extraKeys = function(input)
      if input:wasPressed("left") then cycleBox(-1); return true end
      if input:wasPressed("right") then cycleBox(1); return true end
      if input:wasPressed("a") then chooseThisBox(); return true end
      return false
    end,
    modernUi = {
      left = function() cycleBox(-1) end,
      right = function() cycleBox(1) end,
      select = function() chooseThisBox() end,
    },
  })
  game.stack:push(group.screen)
  return core.pickerHandle(game, group)
end

return Pickers
