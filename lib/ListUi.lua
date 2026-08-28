local V = ...

local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Utils = V.require("Utils")

local LOST_VIEWS = { "pokemon", "items", "moves" }
local LOST_VIEW_TITLE = { pokemon = "LOST <PK><MN>", items = "LOST ITEMS", moves = "LOST MOVES" }

local ListUi = {
  syncListScroll = function(list)
    local rows = list.rows or 7
    if list.index - list.scroll > rows then list.scroll = list.index - rows end
    if list.index - list.scroll < 1 then list.scroll = list.index - 1 end
  end,
  publicRows = function(list)
    local out = {}
    for i, row in ipairs(list.items) do out[i] = { label = row.label, value = row.sub or row.right } end
    return out
  end,
  cycleBoxNumber = function(current, count, delta)
    if count <= 1 then return current end
    return ((current - 1 + delta) % count) + 1
  end,
  clampBoxState = function(state, loadStorage, pcBoxCount)
    local st = loadStorage()
    state.bankBox = math.max(1, math.min(#st.boxes, state.bankBox))
    state.pcBox = math.max(1, math.min(pcBoxCount, state.pcBox))
  end,
  chooseListCurrent = function(list, onEmpty)
    if #list.items == 0 then
      onEmpty()
      return
    end
    local item = list.items[list.index]
    if item and list.onChoose then list.onChoose(item, list) end
  end,
  drawListCounter = function(list)
    local total = #list.items
    local text = Strings("%d/%d", total > 0 and list.index or 0, total)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(text, 160 - 8 - Font.width(text), 4)
    love.graphics.setColor(1, 1, 1, 1)
  end,
  drawListTitle = function(list)
    if not list.itemBox or not list.title then return end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings(list.title), 8, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end,
  idCountRows = function(map)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
    local rows = {}
    for _, id in ipairs(ids) do rows[#rows + 1] = { label = Utils.truncateName(id), right = "x" .. tostring(map[id]) } end
    return rows
  end,
  attachLevelIcons = function(list, mons)
    for i, item in ipairs(list.items) do
      local mon = mons[i]
      if mon then
        local level = Strings(":L%d", mon.level)
        if list.itemBox then item.sub = level else item.right = level end
      end
    end
  end,
  attachDynamicFooter = function(list, computeFn)
    local function refresh()
      list._dynFooterIndex = list.index
      local text = computeFn(list)
      if text then list.footer = text end
    end
    refresh()
    local baseUpdate = list.update
    function list:update(dt)
      baseUpdate(self, dt)
      if self.index ~= self._dynFooterIndex or self.footer == nil then refresh() end
    end
  end,
  cycleCategory = function(current, avail, delta)
    if #avail - 1 < 2 then return current end
    local idx = 1
    for i, c in ipairs(avail) do if c == current then idx = i break end end
    return avail[((idx - 1 + delta) % #avail) + 1]
  end,
  availableCategoriesSorted = function(counts, categoryOfFn)
    local present, order = {}, {}
    for id, qty in pairs(counts) do
      if qty and qty > 0 then
        local cat = categoryOfFn(id)
        if cat and not present[cat] then
          present[cat] = true
          order[#order + 1] = cat
        end
      end
    end
    table.sort(order)
    local list = { "ALL" }
    for _, cat in ipairs(order) do list[#list + 1] = cat end
    return list
  end,
  resetCategoryIfStale = function(current, avail)
    if #avail - 1 >= 2 then
      for _, c in ipairs(avail) do if c == current then return current end end
    end
    return "ALL"
  end,
  monName = function(game, mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or mon.name or (def and def.name) or tostring(mon.species)
  end,
  moveName = function(game, id)
    local def = game.data.moves and game.data.moves[id]
    return (def and def.name) or id
  end,
  moveEntryId = function(mv) return type(mv) == "table" and mv.id or mv end
}

function ListUi.moveListCursor(list, delta)
  local n = list.items and #list.items or 0
  if n == 0 then return end
  list.index = math.max(1, math.min(n, (list.index or 1) + delta))
  ListUi.syncListScroll(list)
end

function ListUi.setListCursor(list, index)
  local n = list.items and #list.items or 0
  if n == 0 or index == nil then return end
  list.index = math.max(1, math.min(n, math.floor(tonumber(index) or list.index)))
  ListUi.syncListScroll(list)
end

function ListUi.gen1ModernUiListAdapter(getList, actions)
  local surface = {
    rows = function() return ListUi.publicRows(getList()) end,
    index = function() return getList().index end,
    scroll = function() return getList().scroll end,
    footer = function() return getList().footer end,
    up = function() ListUi.moveListCursor(getList(), -1) end,
    down = function() ListUi.moveListCursor(getList(), 1) end,
    hover = function(payload) ListUi.setListCursor(getList(), payload) end,
  }
  for k, v in pairs(actions) do surface[k] = v end
  return surface
end

function ListUi.listScreen(game, opts)
  opts = opts or {}
  local list
  local screen = { isOpaque = true }
  local onClose = opts.onClose or function() game.stack:pop() end

  function screen:rebuild(title, rows, listOpts, mons)
    list = ListMenu.new(game, title, rows, listOpts or {})
    if mons then ListUi.attachLevelIcons(list, mons) end
    screen.list = list
    return list
  end

  function screen:update(dt)
    local input = game.input
    if opts.extraKeys and opts.extraKeys(input) then
      return
    elseif opts.onSelect and input:wasPressed("select") then
      opts.onSelect()
      return
    elseif input:wasPressed("b") then
      onClose()
      return
    elseif opts.readOnly and input:wasPressed("a") then
      onClose()
      return
    end
    list:update(dt)
  end

  function screen:draw()
    list:draw()
    ListUi.drawListTitle(list)
    if opts.counter then ListUi.drawListCounter(list) end
  end

  screen.screenId = opts.screenId
  local modernUi = {
    select = opts.readOnly and onClose or function() ListUi.chooseListCurrent(list, onClose) end,
    back = onClose,
  }
  for k, v in pairs(opts.modernUi or {}) do modernUi[k] = v end
  screen.gen1ModernUi = ListUi.gen1ModernUiListAdapter(function() return list end, modernUi)
  return screen
end

function ListUi.listGroup(game, opts)
  opts = opts or {}
  local views = opts.views
  assert(type(views) == "table" and #views > 0, "listGroup: opts.views must be a non-empty array")
  local state = opts.state or {}
  if state.view == nil then
    local start, found = opts.startView, false
    if start ~= nil then
      for _, v in ipairs(views) do if v == start then found = true break end end
    end
    state.view = found and start or views[1]
  end

  local function nextView()
    if #views <= 1 then return state.view end
    local idx = 1
    for i, v in ipairs(views) do
      if v == state.view then idx = i break end
    end
    return views[(idx % #views) + 1]
  end

  local function labelOf(view) return opts.label and opts.label(view) or opts.title(view) end

  local group = { state = state }

  local function rebuild(preserveCursor)
    local oldIndex = preserveCursor and group.screen.list and group.screen.list.index
    local rows, listOpts, mons = opts.build(state.view)
    group.screen:rebuild(opts.title(state.view), rows, listOpts, mons)
    if oldIndex then ListUi.setListCursor(group.screen.list, oldIndex) end
    local nextLabel = #views > 1 and labelOf(nextView()) or nil
    if opts.dynamicFooter then
      ListUi.attachDynamicFooter(group.screen.list, function(list) return opts.dynamicFooter(state.view, list.items[list.index], nextLabel) end)
    elseif opts.footer then
      group.screen.list.footer = opts.footer(state.view, nextLabel)
    elseif nextLabel then group.screen.list.footer = "SELECT: " .. nextLabel end
  end

  local function cycleView()
    if #views <= 1 then return end
    state.view = nextView()
    rebuild()
  end

  local modernUi = { title = function() return opts.title(state.view) end, start = cycleView }
  for k, v in pairs(opts.modernUi or {}) do modernUi[k] = v end
  group.screen = ListUi.listScreen(game, {
    screenId = opts.screenId,
    readOnly = opts.readOnly,
    counter = opts.counter,
    onClose = opts.onClose,
    onSelect = cycleView,
    extraKeys = opts.extraKeys,
    modernUi = modernUi,
  })
  group.rebuild = rebuild
  group.cycleView = cycleView
  rebuild()
  return group
end

function ListUi.lostBrowser(game, opts)
  local group = ListUi.listGroup(game, {
    screenId = opts.screenId,
    readOnly = true,
    counter = true,
    views = LOST_VIEWS,
    title = function(view) return LOST_VIEW_TITLE[view] end,
    build = function(view)
      if view == "pokemon" then
        local rows, mons = {}, {}
        for _, mon in ipairs(opts.getMons()) do
          rows[#rows + 1] = { label = ListUi.monName(game, mon) }
          mons[#mons + 1] = mon
        end
        return rows, { messageBox = true, noSound = true, wrap = true }, mons
      elseif view == "items" then
        return ListUi.idCountRows(opts.getItems()), { messageBox = true, noSound = true, wrap = true }
      else
        return ListUi.idCountRows(opts.getMoves()), { messageBox = true, noSound = true, wrap = true }
      end
    end,
  })
  return group.screen
end

return ListUi
