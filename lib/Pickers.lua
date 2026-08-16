local V = ...

local Strings = require("src.core.Strings")
local ListMenu = require("src.ui.ListMenu")
local Font = require("src.render.Font")
local Boxes = require("src.pokemon.Boxes")
local Bag = require("src.inventory.Bag")

local Pickers = {}

Pickers.MON_PICKER_SCREEN_ID = "PokemonBankMonPicker"
Pickers.ITEM_PICKER_SCREEN_ID = "PokemonBankItemPicker"
Pickers.BOX_PICKER_SCREEN_ID = "PokemonBankBoxPicker"

local VIEW_LABELS = { bank = "BANK", party = "PARTY", pc = "PC", bag = "BAG" }

-- Next entry in a SELECT cycle, wrapping past the last back to the first.
local function nextView(views, current)
  local idx = 1
  for i, v in ipairs(views) do if v == current then idx = i break end end
  return views[(idx % #views) + 1]
end

function Pickers.openMonPicker(mod, core, game, opts)
  opts = opts or {}
  local views = {}
  if not opts.hideBank then views[#views + 1] = "bank" end
  if not opts.hideParty then views[#views + 1] = "party" end
  if not opts.hidePc then views[#views + 1] = "pc" end
  if #views == 0 then return nil, "no views enabled" end
  Boxes.ensure(game.save)
  local loadStorage = core.loadStorage
  local viewIdx = 1
  for i, v in ipairs(views) do
    if v == opts.startView then viewIdx = i end
  end
  local state = {
    view = views[viewIdx],
    bankBox = loadStorage().currentBox,
    pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
  }

  local screen = { isOpaque = true }
  local list
  local rebuild, cycleView, cycleBox, backHandler, chooseCurrent

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
    if state.view == "bank" then return Strings("BANK BOX %d", state.bankBox)
    elseif state.view == "party" then return "PARTY"
    else return Strings("PC BOX %d", state.pcBox) end
  end

  local function viewTitle()
    if opts.title then return opts.title(state.view, boxNumFor(state.view)) end
    return defaultTitle()
  end

  cycleView = function()
    if #views <= 1 then return end
    state.view = nextView(views, state.view)
    rebuild()
  end

  cycleBox = function(delta)
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

  rebuild = function()
    core.clampBoxState(state, loadStorage, Boxes.COUNT)
    local src = currentList()
    local rows = {}
    for i, mon in ipairs(src) do
      local right = opts.rowRight and opts.rowRight(mon, state.view, boxNumFor(state.view), i)
      rows[#rows + 1] = { label = core.monName(game, mon), value = i, right = right }
    end
    list = ListMenu.new(game, viewTitle(), rows, {
      noSound = true, rows = 6, wrap = true,
      onChoose = function(item)
        local mon = src[item.value]
        if not mon then return end
        if opts.onChoose then
          opts.onChoose(mon, { view = state.view, box = boxNumFor(state.view), index = item.value })
        end
      end,
    })
    core.attachLevelIcons(list, src, 0)
    if opts.footer then
      list.footer = opts.footer(state.view, #views > 1 and VIEW_LABELS[nextView(views, state.view)] or nil)
    elseif #views > 1 then
      list.footer = "SELECT: " .. VIEW_LABELS[nextView(views, state.view)]
    end
  end

  backHandler = function()
    game.stack:pop()
    if opts.onCancel then opts.onCancel() end
  end

  chooseCurrent = function()
    core.chooseListCurrent(list, backHandler)
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

  screen.screenId = Pickers.MON_PICKER_SCREEN_ID
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

  return {
    refresh = function() rebuild() end,
    setFooter = function(msg) list.footer = msg end,
    close = function() game.stack:pop() end,
  }
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
  local viewIdx = 1
  for i, v in ipairs(views) do
    if v == opts.startView then viewIdx = i end
  end
  local state = { view = views[viewIdx] }

  local screen = { isOpaque = true }
  local list
  local rebuild, cycleView, backHandler, chooseCurrent

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

  cycleView = function()
    if #views <= 1 then return end
    state.view = nextView(views, state.view)
    rebuild()
  end

  rebuild = function()
    local counts = currentCounts()
    local rows = {}
    for _, id in ipairs(currentIds()) do
      local count = counts[id]
      if count and count > 0 then
        local right = opts.rowRight and opts.rowRight(id, count, state.view) or ("x" .. tostring(count))
        rows[#rows + 1] = { value = id, label = core.truncateName(core.itemName(game, id)), right = right }
      end
    end
    list = ListMenu.new(game, viewTitle(), rows, {
      noSound = true, wrap = true,
      onChoose = function(item)
        local count = counts[item.value]
        if not count or count <= 0 then return end
        if opts.onChoose then opts.onChoose(item.value, count, state.view) end
      end,
    })
    if opts.footer then
      list.footer = opts.footer(state.view, #views > 1 and VIEW_LABELS[nextView(views, state.view)] or nil)
    elseif #views > 1 then
      list.footer = "SELECT: " .. VIEW_LABELS[nextView(views, state.view)]
    end
  end

  backHandler = function()
    game.stack:pop()
    if opts.onCancel then opts.onCancel() end
  end

  chooseCurrent = function()
    core.chooseListCurrent(list, backHandler)
  end

  function screen:update(dt)
    local input = game.input
    if input:wasPressed("select") then
      cycleView()
      return
    elseif input:wasPressed("b") then
      backHandler()
      return
    end
    list:update(dt)
  end

  function screen:draw()
    list:draw()
  end

  screen.screenId = Pickers.ITEM_PICKER_SCREEN_ID
  screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
    title = function() return viewTitle() end,
    select = function(payload)
      if payload then core.setListCursor(list, payload) end
      chooseCurrent()
    end,
    back = function() backHandler() end,
    start = function() cycleView() end,
  })

  rebuild()
  game.stack:push(screen)

  return {
    refresh = function() rebuild() end,
    setFooter = function(msg) list.footer = msg end,
    close = function() game.stack:pop() end,
  }
end

function Pickers.openBoxPicker(mod, core, game, opts)
  opts = opts or {}
  local views = {}
  if not opts.hideBank then views[#views + 1] = "bank" end
  if not opts.hidePc then views[#views + 1] = "pc" end
  if #views == 0 then return nil, "no views enabled" end

  Boxes.ensure(game.save)
  local loadStorage = core.loadStorage
  local viewIdx = 1
  for i, v in ipairs(views) do
    if v == opts.startView then viewIdx = i end
  end
  local state = {
    view = views[viewIdx],
    bankBox = loadStorage().currentBox,
    pcBox = math.max(1, math.min(Boxes.COUNT, game.save.currentBox or 1)),
  }

  local screen = { isOpaque = true }
  local list
  local rebuild, cycleView, cycleBox, backHandler, chooseThisBox

  local function currentBoxNum() return state.view == "bank" and state.bankBox or state.pcBox end
  local function currentBox()
    if state.view == "bank" then return loadStorage().boxes[state.bankBox]
    else return game.save.boxes[state.pcBox] end
  end

  local function viewTitle()
    if opts.title then return opts.title(state.view, currentBoxNum()) end
    return state.view == "bank" and Strings("BANK BOX %d", state.bankBox) or Strings("PC BOX %d", state.pcBox)
  end

  cycleView = function()
    if #views <= 1 then return end
    state.view = nextView(views, state.view)
    rebuild()
  end

  cycleBox = function(delta)
    if state.view == "bank" then
      local n = #loadStorage().boxes
      if n <= 1 then return end
      state.bankBox = ((state.bankBox - 1 + delta) % n) + 1
    else
      state.pcBox = ((state.pcBox - 1 + delta) % Boxes.COUNT) + 1
    end
    rebuild()
  end

  rebuild = function()
    core.clampBoxState(state, loadStorage, Boxes.COUNT)
    local box = currentBox()
    local rows = {}
    for i, mon in ipairs(box) do
      rows[#rows + 1] = { label = core.monName(game, mon), value = i }
    end
    list = ListMenu.new(game, viewTitle(), rows, { noSound = true, rows = 6, wrap = true })
    core.attachLevelIcons(list, box, 0)
    if opts.footer then
      list.footer = opts.footer(state.view, currentBoxNum(), #views > 1 and VIEW_LABELS[nextView(views, state.view)] or nil)
    else
      local hint = #views > 1 and ("SELECT: " .. VIEW_LABELS[nextView(views, state.view)] .. "\n") or ""
      list.footer = hint .. "A: CONFIRM"
    end
  end

  chooseThisBox = function()
    local box = currentBox()
    if opts.requireNonEmpty ~= false and #box == 0 then
      list.footer = opts.emptyMessage or "What? There are\nno POKéMON here!"
      return
    end
    if opts.onChoose then opts.onChoose(state.view, currentBoxNum()) end
  end

  backHandler = function()
    game.stack:pop()
    if opts.onCancel then opts.onCancel() end
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
  end

  screen.screenId = Pickers.BOX_PICKER_SCREEN_ID
  screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
    title = function() return viewTitle() end,
    left = function() cycleBox(-1) end,
    right = function() cycleBox(1) end,
    select = function() chooseThisBox() end,
    back = function() backHandler() end,
    start = function() cycleView() end,
  })

  rebuild()
  game.stack:push(screen)

  return {
    refresh = function() rebuild() end,
    setFooter = function(msg) list.footer = msg end,
    close = function() game.stack:pop() end,
  }
end

return Pickers
