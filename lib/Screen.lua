local V = ...

local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local Widgets = V.require("Widgets")
local GridUi = V.require("GridUi")
local ListMenu = Widgets.listMenu(require("src.ui.ListMenu"))
local Actions = V.require("Actions")
local Species = V.require("Species")
local unpack = table.unpack or unpack

local function hasHeldItem(mon)
  if type(mon) ~= "table" then return false end
  local item = mon.item or mon.heldItem
  return item ~= nil and item ~= "" and item ~= 0
end

local function drawHeldIcon(x, y, mon, game)
  if Widgets.active() then return Widgets.drawHeldIconAt(x, y, mon) end
  if GameVersion.generation() ~= 2 then return false end
  local okP, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  if not (okP and PartyMenu.heldMarkerRow) then return false end
  local row = PartyMenu.heldMarkerRow(mon)
  if not row then return false end
  local gfx = game and game.data and game.data.gen2MenuGfx and game.data.gen2MenuGfx.billsPc
  if not (gfx and gfx.icons) then return false end
  local Assets = require("src.render.Assets")
  local okImage, image = pcall(Assets.image, gfx.icons)
  if not (okImage and image) then return false end
  local okQuad, quad = pcall(love.graphics.newQuad, row * 8, 0, 8, 8, image:getDimensions())
  if not okQuad then return false end
  local G = love.graphics
  local function body() G.draw(image, quad, x, y) end
  local GbcPalette = require("src.render.GbcPalette")
  local okAvail, avail = pcall(GbcPalette.available)
  G.setColor(1, 1, 1, 1)
  if gfx.palette and okAvail and avail then GbcPalette.with(gfx.palette, body) else body() end
  return true
end

local function drawHeldMarkAt(x, y, mon, game)
  if not hasHeldItem(mon) then return end
  if drawHeldIcon(x, y, mon, game) then return end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", x + 2, y + 2, 4, 4)
  love.graphics.setColor(1, 1, 1, 1)
end

local Screen = {
  syncListScroll = function(list)
    if list.grid then return GridUi.sync(list) end
    local rows = list.rows or 7
    if list.index - list.scroll > rows then list.scroll = list.index - rows end
    if list.index - list.scroll < 1 then list.scroll = list.index - 1 end
  end,
  publicRows = function(list)
    local out = {}
    for i, row in ipairs(list.items) do out[i] = { label = row.label, value = row.sub or row.right } end
    return out
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
    if Widgets.active() then return Widgets.drawListCounter(list, text) end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(text, 160 - 8 - Font.width(text), 4)
    love.graphics.setColor(1, 1, 1, 1)
  end,
  drawListTitle = function(list)
    if Widgets.active() or list.grid or not list.itemBox or not list.title then return end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings(list.title), 8, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end,
  attachLevelIcons = function(list, mons)
    for i, item in ipairs(list.items) do
      local mon = mons[i]
      if mon then item.right = (Widgets.active() and "Lv" or "") .. tostring(mon.level) end
    end
    if Widgets.active() then return end
    local origDraw = list.draw
    function list:draw()
      origDraw(self)
      local gen2 = GameVersion.generation() == 2
      local levelCode = gen2 and Font.encode("<LV>")[1]
      local HudTiles = not gen2 and require("src.render.HudTiles")
      if levelCode or HudTiles then
        local wasBattle = gen2 and Font.useBattleExtra(true)
        for row = 1, self.rows do
          local item = self.items[self.scroll + row]
          local levelText = item and item.right
          if levelText then
            local y = self.itemBox and (32 + (row - 1) * 16 + 8) or (8 + row * 16)
            local right = self.itemBox and 136 or (160 - 8)
            local x = right - Font.width(levelText) - 8
            if gen2 then Font.drawCode(levelCode, x, y) else HudTiles.tile(0x6E, x, y) end
          end
        end
        if gen2 then Font.useBattleExtra(wasBattle) end
      end
    end
  end,
  attachHeldItemMarks = function(list, mons, game)
    local origDraw = list.draw
    function list:draw()
      origDraw(self)
      if Widgets.active() then
        for row = 1, self.rows do
          local item = self.items[self.scroll + row]
          local mon = item and mons[self.scroll + row]
          if mon and hasHeldItem(mon) and not Widgets.drawListHeldIcon(self, row, item.label, mon) then
            Widgets.drawListMark(self, row, item.label)
          end
        end
        return
      end
      for row = 1, self.rows do
        local item = self.items[self.scroll + row]
        local mon = item and mons[self.scroll + row]
        if mon and hasHeldItem(mon) then
          local y = self.itemBox and (32 + (row - 1) * 16) or (8 + row * 16)
          local x0 = self.itemBox and 48 or 16
          local x = x0 + Font.width(item.label) + 6
          local iconY = y + (self.itemBox and 4 or 0)
          local drew = drawHeldIcon(x, iconY - 4, mon, game)
          if not drew then
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", x + 2, iconY + 2, 4, 4)
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end,
  currentList = function(env, list) return env and env.screen and env.screen.list or list end,
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
  monName = function(game, mon)
    local key = Species.key(mon)
    local def = game and game.data and game.data.pokemon and game.data.pokemon[key]
    local nickname = mon.nickname ~= "" and mon.nickname or nil
    return nickname or mon.name or (def and def.name) or tostring(key)
  end,
  moveName = function(game, id)
    local def = game.data.moves and game.data.moves[id]
    return (def and def.name) or id
  end,
  moveEntryId = function(mv) return type(mv) == "table" and mv.id or mv end
}

function Screen.drawTitleMark(list)
  if Widgets.active() then return Widgets.drawListMark(list, 0) end
  love.graphics.setColor(0, 0, 0, 1)
  local x = 8 + Font.width(Strings(list.title)) + 6
  love.graphics.rectangle("fill", x, 4 + 2, 4, 4)
  love.graphics.setColor(1, 1, 1, 1)
end

function Screen.drawRowMark(list, value)
  if value == nil then return end
  if Widgets.active() then
    for row = 1, list.rows do
      local item = list.items[list.scroll + row]
      if item and item.value == value then Widgets.drawListMark(list, row, item.label) end
    end
    return
  end
  love.graphics.setColor(0, 0, 0, 1)
  for row = 1, list.rows do
    local item = list.items[list.scroll + row]
    if item and item.value == value then
      local y = list.itemBox and (32 + (row - 1) * 16) or (8 + row * 16)
      local x0 = list.itemBox and 48 or 16
      love.graphics.rectangle("fill", x0 + Font.width(item.label) + 6, y + 2, 4, 4)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Screen.moveListCursor(list, delta)
  local n = list.items and #list.items or 0
  if n == 0 then return end
  list.index = math.max(1, math.min(n, (list.index or 1) + delta))
  Screen.syncListScroll(list)
end

function Screen.setListCursor(list, index)
  local n = list.items and #list.items or 0
  if n == 0 or index == nil then return end
  list.index = math.max(1, math.min(n, math.floor(tonumber(index) or list.index)))
  Screen.syncListScroll(list)
end

function Screen.gen1ModernUiListAdapter(getList, actions)
  local surface = {
    rows = function() return Screen.publicRows(getList()) end,
    index = function() return getList().index end,
    scroll = function() return getList().scroll end,
    footer = function() return getList().footer end,
    up = function() Screen.moveListCursor(getList(), -1) end,
    down = function() Screen.moveListCursor(getList(), 1) end,
    hover = function(payload) Screen.setListCursor(getList(), payload) end,
  }
  for k, v in pairs(actions) do surface[k] = v end
  return surface
end

function Screen.listScreen(game, opts)
  opts = opts or {}
  local list
  local screen = { isOpaque = true }
  local onClose = opts.onClose or function() game.stack:pop() end

  function screen:rebuild(title, rows, listOpts, mons)
    list = ListMenu.new(game, title, rows, listOpts or {})
    if mons then Screen.attachLevelIcons(list, mons) end
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
    Screen.drawListTitle(list)
    if opts.counter then Screen.drawListCounter(list) end
  end

  screen.screenId = opts.screenId
  local modernUi = {
    select = opts.readOnly and onClose or function() Screen.chooseListCurrent(list, onClose) end,
    back = onClose,
  }
  for k, v in pairs(opts.modernUi or {}) do modernUi[k] = v end
  screen.gen1ModernUi = Screen.gen1ModernUiListAdapter(function() return list end, modernUi)
  return screen
end

function Screen.listGroup(game, opts)
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
    if oldIndex then Screen.setListCursor(group.screen.list, oldIndex) end
    local nextLabel = #views > 1 and labelOf(nextView()) or nil
    if opts.dynamicFooter then Screen.attachDynamicFooter(group.screen.list, function(list) return opts.dynamicFooter(state.view, list.items[list.index], nextLabel) end)
    elseif opts.footer then group.screen.list.footer = opts.footer(state.view, nextLabel)
    elseif nextLabel then group.screen.list.footer = "SELECT: " .. nextLabel end
  end

  local function cycleView()
    if #views <= 1 then return end
    state.view = nextView()
    rebuild()
  end

  local modernUi = { title = function() return opts.title(state.view) end, start = cycleView }
  for k, v in pairs(opts.modernUi or {}) do modernUi[k] = v end
  group.screen = Screen.listScreen(game, {
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

local ALL_PAGE_ID = setmetatable({}, { __tostring = function() return "ALL" end })

function Screen.isAllPage(pageId) return pageId == ALL_PAGE_ID end

local function gateOn(v, ...)
  if type(v) == "function" then return v(...) == true end
  return v == true
end

local function gateAllowed(v, ...)
  if type(v) == "function" then return v(...) ~= false end
  return v ~= false
end

local function realPages(state, container) return container.getPages and container.getPages(state.game, state.env) or nil end

local function pageChoicesOf(state, container)
  local pages = realPages(state, container)
  if not pages then return nil end
  if not container.includeAllPage then return pages end
  local out = { { id = ALL_PAGE_ID, label = "ALL" } }
  for _, p in ipairs(pages) do out[#out + 1] = p end
  return out
end

local function ensurePage(state, container)
  if not container.getPages or state.pages[container.id] ~= nil then return end
  local choices = pageChoicesOf(state, container)
  local remembered = container.getRememberedPage and container.getRememberedPage(state.game, state.env)
  for _, p in ipairs(choices or {}) do
    if p.id == remembered then
      state.pages[container.id] = remembered
      return
    end
  end
  state.pages[container.id] = choices and choices[1] and choices[1].id or nil
end

local function pageIdOf(state, container) return container.getPages and state.pages[container.id] or nil end

local function autoRemembers(container) return container.autoRememberPage ~= false end

local function rememberedPageOf(state, container)
  if autoRemembers(container) or not container.getRememberedPage then return nil end
  return container.getRememberedPage(state.game, state.env)
end

local function rememberPage(state, container, pageId, explicit)
  if not container.setRememberedPage or pageId == ALL_PAGE_ID then return end
  if explicit or autoRemembers(container) then container.setRememberedPage(state.game, pageId, state.env) end
end

local function realPageIndex(pages, pageId)
  for i, p in ipairs(pages or {}) do if p.id == pageId then return i end end
  return nil
end

local function buildContainerRows(state, container, pageId)
  if pageId ~= ALL_PAGE_ID then return container.build(state.game, pageId, state.env) end
  local rows, mons, anyMons = {}, {}, false
  for _, p in ipairs(realPages(state, container) or {}) do
    local r, _, m = container.build(state.game, p.id, state.env)
    for i, row in ipairs(r or {}) do
      rows[#rows + 1] = row
      if m then anyMons = true end
      mons[#mons + 1] = m and m[i] or false
    end
  end
  return rows, { messageBox = true, noSound = true, wrap = true }, anyMons and mons or nil
end

local function slotsOf(state, container, pageId)
  if pageId == ALL_PAGE_ID or container.slots == nil then return nil end
  local slots = container.slots
  if type(slots) == "function" then slots = slots(state.game, pageId, state.env) end
  slots = tonumber(slots)
  return slots and slots >= 1 and math.floor(slots) or nil
end

local function realRowCount(rows)
  local n = 0
  for _, row in ipairs(rows or {}) do if not row.inert then n = n + 1 end end
  return n
end

local function pageCount(state, container, pageId) return realRowCount((buildContainerRows(state, container, pageId))) end

local function pageFull(state, container, pageId)
  local slots = slotsOf(state, container, pageId)
  return slots ~= nil and pageCount(state, container, pageId) >= slots
end

local function landingPage(state, dest)
  local pageId = pageIdOf(state, dest)
  if not pageFull(state, dest, pageId) then return true, pageId end
  if not (dest.getPages and gateOn(dest.canOverflow, state.game, pageId, state.env)) then return false end
  local pages = realPages(state, dest) or {}
  local start = realPageIndex(pages, pageId) or 0
  for offset = 1, #pages do
    local page = pages[((start - 1 + offset) % #pages) + 1]
    if not pageFull(state, dest, page.id) then return true, page.id end
  end
  return false
end

local function emptySlotLabel(container)
  if container.emptySlotLabel then return container.emptySlotLabel end
  return Widgets.active() and "<EMPTY SLOT>" or "-----"
end

local function padEmptySlots(state, container, pageId, rows, mons)
  local slots = slotsOf(state, container, pageId)
  if not slots or not gateOn(container.emptySlots, state.game, pageId, state.env) then return end
  for i = #rows + 1, slots do
    rows[i] = { label = emptySlotLabel(container), inert = true, padding = true }
    if mons then mons[i] = false end
  end
end

local function eligibleDestinations(state, containers, source, pageId, row)
  if type(source.withdraw) ~= "function" then return {} end
  if not gateAllowed(source.canWithdraw, state.game, pageId, row, state.env) then return {} end
  local out = {}
  for _, dest in ipairs(containers) do
    if dest.id ~= source.id and type(dest.deposit) == "function" then
      local destPageId = pageIdOf(state, dest)
      if gateAllowed(dest.canDeposit, state.game, destPageId, row, source.id, state.env) and landingPage(state, dest) then
        out[#out + 1] = dest
      end
    end
  end
  return out
end

local function moveRow(state, source, dest, pageId, row, rebuild)
  local found, destPageId = landingPage(state, dest)
  if not found then return false end
  local shown = state.pages[dest.id]
  if dest.getPages then state.pages[dest.id] = destPageId end
  local ok = source.withdraw(state.game, pageId, row, dest.id, state.env)
  if ok ~= false then dest.deposit(state.game, destPageId, row, source.id, state.env) end
  if dest.getPages then state.pages[dest.id] = shown end
  if ok == false then return false end
  rebuild(true)
  return true
end

local function appendTransferRow(rows, state, containers, container, pageId, row, rebuild)
  local destinations = eligibleDestinations(state, containers, container, pageId, row)
  local label = container.transferLabel or "TRANSFER"
  if #destinations == 1 then
    local dest = destinations[1]
    rows[#rows + 1] = { label = label, onSelect = function() moveRow(state, container, dest, pageId, row, rebuild) end }
  elseif #destinations > 1 then
    rows[#rows + 1] = { label = label, keepOpen = true, onSelect = function()
      local subRows = {}
      for _, dest in ipairs(destinations) do
        subRows[#subRows + 1] = { label = "TO " .. dest.label, onSelect = function()
          moveRow(state, container, dest, pageId, row, rebuild)
        end }
      end
      subRows[#subRows + 1] = { label = "CANCEL" }
      Actions.rowActionsMenu(state.game, subRows)
    end }
  end
end

-- The per-row TRANSFER row for containers that build their own onAction: the same grouping the generated one has
-- (no row with nothing to offer, a direct run with one target, a `TO <label>` submenu with two or more).
-- targets: { { label = "TO BANK", visible = function(game, pageId, row, env), onSelect = <onAction's onSelect> }, ... }
function Screen.transferGroup(targets, label)
  local function shownFor(game, pageId, row, env)
    local shown = {}
    for _, t in ipairs(targets) do
      if t.visible == nil or t.visible(game, pageId, row, env) ~= false then shown[#shown + 1] = t end
    end
    return shown
  end
  return {
    label = label or "TRANSFER", keepOpen = true,
    visible = function(game, pageId, row, env) return #shownFor(game, pageId, row, env) > 0 end,
    onSelect = function(game, pageId, row, rebuild, list, env)
      local shown = shownFor(game, pageId, row, env)
      if #shown == 1 then return shown[1].onSelect(game, pageId, row, rebuild, list, env) end
      local rows = {}
      for _, t in ipairs(shown) do
        rows[#rows + 1] = { label = t.label, onSelect = function() t.onSelect(game, pageId, row, rebuild, list, env) end }
      end
      rows[#rows + 1] = { label = "CANCEL" }
      Actions.rowActionsMenu(game, rows)
    end,
  }
end

local function beginRearrange(state, container, pageId, index)
  state.rearrange = {
    containerId = container.id,
    pageId = pageId,
    index = index,
    originalPageId = pageId,
    originalIndex = index,
  }
end

local function appendMoveRemoveRows(rows, state, container, pageId, row, index, rebuild)
  if gateOn(container.canRearrange, state.game, pageId, row, state.env) then
    rows[#rows + 1] = { label = "MOVE", onSelect = function() beginRearrange(state, container, pageId, index) end }
  end
  if gateOn(container.canRemove, state.game, pageId, row, state.env) and type(container.withdraw) == "function"
      and gateAllowed(container.canWithdraw, state.game, pageId, row, state.env) then
    rows[#rows + 1] = { label = container.removeLabel or "REMOVE", onSelect = function()
      container.withdraw(state.game, pageId, row, nil, state.env)
      rebuild(true)
    end }
  end
end

local function buildDefaultRows(state, containers, container, pageId, row, index, rebuild)
  local rows = {}
  appendTransferRow(rows, state, containers, container, pageId, row, rebuild)
  appendMoveRemoveRows(rows, state, container, pageId, row, index, rebuild)
  return rows
end

local function openRowMenu(state, containers, container, pageId, item, index, rebuild)
  local row = item.value
  local rows = buildDefaultRows(state, containers, container, pageId, row, index, rebuild)
  local custom = container.onAction
  if type(custom) == "table" then
    for _, r in ipairs(custom) do
      if r.visible == nil or r.visible(state.game, pageId, row, state.env) ~= false then
        rows[#rows + 1] = { label = r.label, keepOpen = r.keepOpen, onSelect = r.onSelect and function() r.onSelect(state.game, pageId, row, rebuild, state.list, state.env) end }
      end
    end
  end
  if #rows == 0 or rows[#rows].label ~= "CANCEL" then rows[#rows + 1] = { label = "CANCEL" } end
  Actions.rowActionsMenu(state.game, rows)
end

local function bulkTransferRow(state, containers, container, pageId, rebuild)
  local structural = {}
  if type(container.withdraw) == "function" then
    for _, dest in ipairs(containers) do
      if dest.id ~= container.id and type(dest.deposit) == "function" then structural[#structural + 1] = dest end
    end
  end
  if #structural == 0 then return nil end
  local function runTo(dest)
    local rows = {}
    for _, row in ipairs(select(1, buildContainerRows(state, container, pageId)) or {}) do
      if not row.inert then rows[#rows + 1] = row end
    end
    Actions.confirmBulkMoveAll(state.game, {
      count = #rows,
      verb = "Move", resultVerb = "Moved", noun = "rows",
      run = function()
        local moved, refused = 0, 0
        for i = #rows, 1, -1 do
          if moveRow(state, container, dest, pageId, rows[i].value, function() end) then moved = moved + 1 else refused = refused + 1 end
        end
        return moved, refused
      end,
      rebuild = function() rebuild(true) end,
      setFooter = function(msg) state.list.footer = msg end,
    })
  end
  local label = container.transferLabel or "TRANSFER"
  if #structural == 1 then
    return { label = label, onSelect = function() runTo(structural[1]) end }
  end
  return { label = label, keepOpen = true, onSelect = function()
    local subRows = {}
    for _, dest in ipairs(structural) do
      subRows[#subRows + 1] = { label = "TO " .. dest.label, onSelect = function() runTo(dest) end }
    end
    subRows[#subRows + 1] = { label = "CANCEL" }
    Actions.rowActionsMenu(state.game, subRows)
  end }
end

local function jumpToPage(state, container, pageId, rebuild)
  state.pages[container.id] = pageId
  if container.onPageChange then container.onPageChange(state.game, pageId, state.env) end
  rememberPage(state, container, pageId)
  rebuild()
end

local function listsPages(state, container)
  if not gateOn(container.canListPages, state.game, pageIdOf(state, container), state.env) then return false end
  local pages = pageChoicesOf(state, container)
  return pages ~= nil and #pages > 1
end

local function textWidth(text)
  if Widgets.active() then return Widgets.textWidth(text) end
  return Font.width(text)
end

-- One footer line with `right` flush to the edge, padding with spaces; `left` is cut when they would collide.
function Screen.footerSplit(left, right)
  local budget = Widgets.active() and 204 or 144
  local chars = {}
  for ch in left:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  while #chars > 0 and textWidth(table.concat(chars)) + textWidth(right) + textWidth(" ") > budget do chars[#chars] = nil end
  left = table.concat(chars)
  local pad = math.floor((budget - textWidth(left) - textWidth(right)) / math.max(1, textWidth(" ")))
  return left .. string.rep(" ", math.max(1, pad)) .. right
end

-- Command hints for a pages-list footer: the longest wording that fits one line.
local function pagesFooterHints(nextLabel, startLabel)
  local budget = Widgets.active() and 204 or 144
  local candidates = {}
  if nextLabel then
    candidates[1] = ("SELECT: %s  A: MENU  START: %s"):format(nextLabel, startLabel)
    candidates[2] = ("SEL:%s A:OK ST:%s"):format(nextLabel, startLabel)
  end
  candidates[#candidates + 1] = ("A: MENU  START: %s"):format(startLabel)
  candidates[#candidates + 1] = ("A:OK ST:%s"):format(startLabel)
  for _, text in ipairs(candidates) do
    if textWidth(text) <= budget then return text end
  end
  return candidates[#candidates]
end

local function pagesContainerFor(state, container, rebuild, refreshList, titled)
  local game = state.game
  local allOffset = container.includeAllPage and 1 or 0

  local function rebuildBoth()
    rebuild(true)
    refreshList()
  end

  local actions = { { label = "VIEW", onSelect = function(_, _, pageId)
    game.stack:pop()
    state.view = container.id
    jumpToPage(state, container, pageId, rebuild)
  end } }
  if not autoRemembers(container) and container.setRememberedPage then
    actions[#actions + 1] = { label = container.rememberPageLabel or "CHANGE",
      visible = function(_, _, pageId) return pageId ~= ALL_PAGE_ID end,
      onSelect = function(_, _, pageId)
        rememberPage(state, container, pageId, true)
        rebuildBoth()
      end }
  end
  for _, r in ipairs(type(container.listPagesActions) == "table" and container.listPagesActions or {}) do
    actions[#actions + 1] = { label = r.label, keepOpen = r.keepOpen,
      visible = r.visible and function(_, _, pageId) return r.visible(game, pageId, state.env) end,
      onSelect = r.onSelect and function(_, _, pageId, _, list) r.onSelect(game, pageId, rebuildBoth, list, state.env) end }
  end
  local function subOf(pageId)
    local count, slots = pageCount(state, container, pageId), slotsOf(state, container, pageId)
    return slots and ("%d/%d"):format(count, slots) or tostring(count)
  end

  local function pageColumns()
    local columns = container.listPagesColumns
    if type(columns) == "function" then
      local ok, value = pcall(columns, game, state.env)
      columns = ok and value or 1
    end
    return GridUi.clampColumns(columns or 1)
  end

  local startRows = type(container.listPagesOnStart) == "table" and container.listPagesOnStart or nil
  return {
    id = container.id,
    label = titled and container.label or (container.listPagesLabel or "PAGES"),
    columns = container.listPagesColumns and function() return pageColumns() end or nil,
    icon = function(_, _, pageId)
      local pages = pageChoicesOf(state, container) or {}
      if type(container.listPagesIcon) == "function" then
        local ok, a, b = pcall(container.listPagesIcon, game, pageId, state.env)
        if ok and a ~= nil then return a, b end
      end
      return GridUi.textIcon(tostring(realPageIndex(pages, pageId) or ""), pageId == rememberedPageOf(state, container),
        pageCount(state, container, pageId), slotsOf(state, container, pageId))
    end,
    onStart = startRows and function(_, _, _, rebuildList)
      local rows = {}
      for _, r in ipairs(startRows) do
        if r.visible == nil or r.visible(game, nil, state.env) ~= false then
          rows[#rows + 1] = { label = r.label, keepOpen = r.keepOpen, onSelect = r.onSelect and function() r.onSelect(game, nil, rebuildList, nil, state.env) end }
        end
      end
      if #rows == 0 then return end
      rows[#rows + 1] = { label = "CANCEL" }
      Actions.rowActionsMenu(game, rows)
    end or nil,
    dynamicFooter = container.listPagesFooter and function(_, _, pageId, nextLabel)
      local label
      for _, p in ipairs(pageChoicesOf(state, container) or {}) do if p.id == pageId then label = p.label end end
      if not label then return nil end
      return Screen.footerSplit(label, subOf(pageId)) .. "\n" .. pagesFooterHints(nextLabel, container.listPagesColumns and "VIEW" or "MENU")
    end or nil,
    build = function()
      local rows = {}
      for i, p in ipairs(pageChoicesOf(state, container) or {}) do
        rows[i] = { label = p.label, sub = subOf(p.id), value = p.id }
      end
      return rows, { messageBox = true, noSound = true, wrap = true }
    end,
    canRearrange = type(container.onMovePage) == "function" and function(_, _, pageId)
      if pageId == ALL_PAGE_ID then return false end
      return gateOn(container.canRearrangePages, game, pageId, state.env)
    end or nil,
    onMove = function(_, _, fromIndex, _, toIndex)
      local moved = (pageChoicesOf(state, container) or {})[fromIndex]
      if not moved or fromIndex == toIndex then return end
      container.onMovePage(game, moved.id, fromIndex - allOffset, toIndex - allOffset, state.env)
      rebuild(true)
    end,
    onAction = actions,
    draw = function(_, _, list, defaultDraw)
      defaultDraw()
      if not list.grid then Screen.drawRowMark(list, rememberedPageOf(state, container)) end
    end,
  }
end

local function openPagesList(state, containers, container, rebuild)
  local listed = {}
  for _, c in ipairs(containers) do if listsPages(state, c) then listed[#listed + 1] = c end end
  local listScreen
  local function refreshList() if listScreen then listScreen.refresh(true) end end
  local pagesContainers = {}
  for i, c in ipairs(listed) do pagesContainers[i] = pagesContainerFor(state, c, rebuild, refreshList, #listed > 1) end
  listScreen = Screen.entryScreen(state.game, pagesContainers, { counter = true, startView = container.id })
  local current = realPageIndex(pageChoicesOf(state, container), pageIdOf(state, container))
  if current then Screen.setListCursor(listScreen.list, current) end
  state.game.stack:push(listScreen)
end

local function pagesListRow(state, containers, container, rebuild)
  if not listsPages(state, container) then return nil end
  return { label = container.listPagesLabel or "PAGES", onSelect = function() openPagesList(state, containers, container, rebuild) end }
end

local function openStartMenu(state, containers, container, pageId, rebuild)
  local defaultStartRows = {}
  if gateOn(container.canTransfer, state.game, pageId, state.env) then
    local row = bulkTransferRow(state, containers, container, pageId, rebuild)
    if row then defaultStartRows[#defaultStartRows + 1] = row end
  end
  do
    local row = pagesListRow(state, containers, container, rebuild)
    if row then defaultStartRows[#defaultStartRows + 1] = row end
  end
  if type(container.onStart) == "function" then
    container.onStart(state.game, pageId, defaultStartRows, rebuild, state.list, state.env)
    return
  end
  local rows = { unpack(defaultStartRows) }
  for _, r in ipairs(type(container.onStart) == "table" and container.onStart or {}) do
    if r.visible == nil or r.visible(state.game, pageId, state.env) ~= false then
      rows[#rows + 1] = { label = r.label, keepOpen = r.keepOpen, onSelect = r.onSelect and function() r.onSelect(state.game, pageId, rebuild, state.list, state.env) end }
    end
  end
  if #rows == 0 then return end
  if rows[#rows].label ~= "CANCEL" then rows[#rows + 1] = { label = "CANCEL" } end
  Actions.rowActionsMenu(state.game, rows)
end

local function swapAdjacent(list, mons, a, b)
  list.items[a], list.items[b] = list.items[b], list.items[a]
  if mons then mons[a], mons[b] = mons[b], mons[a] end
  list.index = b
  Screen.syncListScroll(list)
end

local function cyclePageId(pages, pageId, delta)
  if not pages or #pages == 0 then return pageId end
  local idx = realPageIndex(pages, pageId) or 1
  return pages[((idx - 1 + delta) % #pages) + 1].id
end

local function carryToPage(state, container, delta, atStart)
  local r, list = state.rearrange, state.list
  local newPageId = cyclePageId(realPages(state, container), r.pageId, delta)
  if newPageId == r.pageId then return false end
  local rows, _, mons = buildContainerRows(state, container, newPageId)
  rows = rows or {}
  if newPageId == r.originalPageId then
    table.remove(rows, r.originalIndex)
    if mons then table.remove(mons, r.originalIndex) end
  end
  local slots = slotsOf(state, container, newPageId)
  if slots and realRowCount(rows) >= slots then return false end
  local movingItem, movingMon = list.items[r.index], state.mons and state.mons[r.index]
  table.remove(list.items, r.index)
  if state.mons then table.remove(state.mons, r.index) end
  state.pages[container.id] = newPageId
  r.pageId = newPageId
  padEmptySlots(state, container, newPageId, rows, mons)
  if list.grid then list.grid.decorate(rows, mons, newPageId) end
  list.items = rows
  state.mons = mons
  local hole
  for i, item in ipairs(list.items) do if item.inert then hole = i break end end
  if atStart and list.items[1] and list.items[1].inert then hole = 1 end
  local at = atStart and 1 or (hole or #list.items + 1)
  if hole then
    table.remove(list.items, hole)
    if state.mons then table.remove(state.mons, hole) end
  end
  table.insert(list.items, at, movingItem)
  if state.mons then table.insert(state.mons, at, movingMon) end
  r.index = at
  list.index = r.index
  Screen.syncListScroll(list)
  return true
end

local function handleRearrangeKeys(state, containers, input, rebuild)
  local r = state.rearrange
  if not r then return false end
  local container = containers[1]
  for _, c in ipairs(containers) do if c.id == r.containerId then container = c end end
  local list = state.list
  local function canSwapWith(target)
    local item = list.items[target]
    if not item or item.padding then return false end
    return item.inert or gateOn(container.canRearrange, state.game, r.pageId, item.value, state.env)
  end
  local function swapTo(target)
    if not canSwapWith(target) then return end
    swapAdjacent(list, state.mons, r.index, target)
    r.index = target
  end
  local function betweenPages()
    return container.getPages and gateOn(container.canRearrangeBetweenPages, state.game, r.pageId, state.env)
  end
  local grid = list.grid
  if grid then
    local cols = grid.columns
    local col = ((r.index - 1) % cols) + 1
    local last = #list.items
    while last > 0 and list.items[last].padding do last = last - 1 end
    if input:wasPressed("up") or input:wasPressed("down") then
      local delta = input:wasPressed("up") and -cols or cols
      local p, q = r.index, r.index + delta
      if delta > 0 and q > last and math.ceil(last / cols) > math.ceil(p / cols) then q = last end
      if q < 1 or q > last or q == p or not canSwapWith(q) then return true end
      r.ops = r.ops or {}
      local fromPage, fromIndex = r.segPageId or r.originalPageId, r.segIndex or r.originalIndex
      if not (fromPage == r.pageId and fromIndex == p) then r.ops[#r.ops + 1] = { fromPage, fromIndex, r.pageId, p } end
      r.ops[#r.ops + 1] = { r.pageId, p, r.pageId, q }
      local displaced = q > p and q - 1 or q + 1
      if displaced ~= p then r.ops[#r.ops + 1] = { r.pageId, displaced, r.pageId, p } end
      list.items[p], list.items[q] = list.items[q], list.items[p]
      if state.mons then state.mons[p], state.mons[q] = state.mons[q], state.mons[p] end
      r.index, r.segPageId, r.segIndex = q, r.pageId, q
      list.index = q
      Screen.syncListScroll(list)
      return true
    elseif input:wasPressed("left") then
      if col == 1 and betweenPages() then carryToPage(state, container, -1, false)
      elseif r.index > 1 then swapTo(r.index - 1) end
      return true
    elseif input:wasPressed("right") then
      if (col == cols or r.index >= last) and betweenPages() then carryToPage(state, container, 1, true)
      elseif r.index < last then swapTo(r.index + 1) end
      return true
    end
  elseif input:wasPressed("up") then
    if r.index > 1 then swapTo(r.index - 1) end
    return true
  elseif input:wasPressed("down") then
    if r.index < #list.items then swapTo(r.index + 1) end
    return true
  elseif (input:wasPressed("left") or input:wasPressed("right")) then
    if betweenPages() then carryToPage(state, container, input:wasPressed("left") and -1 or 1, false) end
    return true
  end
  if input:wasPressed("a") then
    local pending = r
    state.rearrange = nil
    if type(container.onMove) == "function" then
      for _, op in ipairs(pending.ops or {}) do container.onMove(state.game, op[1], op[2], op[3], op[4], state.env) end
      local fromPage, fromIndex = pending.segPageId or pending.originalPageId, pending.segIndex or pending.originalIndex
      if not (pending.ops and fromPage == pending.pageId and fromIndex == pending.index) then
        container.onMove(state.game, fromPage, fromIndex, pending.pageId, pending.index, state.env)
      end
    end
    rebuild(true)
    return true
  elseif input:wasPressed("b") then
    state.rearrange = nil
    state.pages[container.id] = r.originalPageId
    rebuild(true)
    return true
  end
  return true
end

local function columnsOf(state, container, pageId)
  local columns = container.columns
  if type(columns) == "function" then
    local ok, value = pcall(columns, state.game, pageId, state.env)
    columns = ok and value or 1
  end
  return GridUi.clampColumns(columns or 1)
end

local function decorateGrid(state, container, pageId, items, mons)
  for i, item in ipairs(items or {}) do
    item._gridIcon, item._gridMon = false, mons and mons[i] or nil
    if type(container.icon) == "function" and not item.padding then
      local ok, a, b = pcall(container.icon, state.game, pageId, item.value, state.env)
      item._gridIcon = ok and GridUi.iconDrawer(a, b) or false
    end
  end
end

local function buildEngine(game, containers, opts, kind)
  assert(type(containers) == "table" and #containers > 0, "entryScreen/pickerScreen: containers must be a non-empty array")
  local byId = {}
  for _, c in ipairs(containers) do
    assert(type(c.id) == "string" and c.id ~= "", "container.id is required")
    assert(type(c.label) == "string" and c.label ~= "", "container.label is required")
    byId[c.id] = c
  end
  if kind == "picker" then assert(type(opts.onChoose) == "function", "pickerScreen: opts.onChoose is required") end

  local views = {}
  for i, c in ipairs(containers) do views[i] = c.id end

  local state = { game = game, pages = {}, mons = nil, list = nil, rearrange = nil, gridHold = {} }
  state.env = { game = game, data = opts.data or {} }
  function state.env.pageOf(containerId)
    local c = byId[containerId]
    return c and pageIdOf(state, c) or nil
  end
  for _, c in ipairs(containers) do ensurePage(state, c) end

  local function currentContainer() return byId[state.view] end

  local function titleOf(view)
    local container = byId[view]
    local pageId = pageIdOf(state, container)
    if type(container.title) == "function" then
      local t = container.title(game, pageId, state.env)
      if t then return t end
    end
    local pageLabel = pageId == ALL_PAGE_ID and "ALL" or nil
    if not pageLabel and pageId then
      for _, p in ipairs(realPages(state, container) or {}) do if p.id == pageId then pageLabel = p.label end end
    end
    return pageLabel and (container.label .. " " .. pageLabel) or container.label
  end

  local group

  local function rebuild(preserveCursor) group.rebuild(preserveCursor) end

  local function build(view)
    local container = byId[view]
    local pageId = pageIdOf(state, container)
    local choices = container.getPages and pageChoicesOf(state, container)
    if choices and pageId ~= nil and not realPageIndex(choices, pageId) and choices[1] then
      pageId = choices[1].id
      state.pages[container.id] = pageId
    end
    local rows, listOpts, mons = buildContainerRows(state, container, pageId)
    rows = rows or {}
    listOpts = listOpts or {}
    padEmptySlots(state, container, pageId, rows, mons)
    if #rows == 0 and container.emptyMessage then listOpts.footer = container.emptyMessage end
    listOpts.onChoose = function(item, list)
      if item.inert then return end
      local index = list.index
      if kind == "picker" then
        local ctx = { containerId = view, pageId = pageId, index = index }
        if container.onAction == nil then
          opts.onChoose(item.value, ctx)
        elseif type(container.onAction) == "function" then
          container.onAction(game, pageId, item.value, function() opts.onChoose(item.value, ctx) end, state.env)
        else
          local rows2 = { { label = container.pickLabel or "PICK", onSelect = function() opts.onChoose(item.value, ctx) end } }
          for _, r in ipairs(container.onAction) do rows2[#rows2 + 1] = { label = r.label, keepOpen = r.keepOpen, onSelect = r.onSelect and function() r.onSelect(game, pageId, item.value, nil, nil, state.env) end } end
          rows2[#rows2 + 1] = { label = "CANCEL" }
          Actions.rowActionsMenu(game, rows2)
        end
      else
        openRowMenu(state, containers, container, pageId, item, index, rebuild)
      end
    end
    state.mons = mons
    return rows, listOpts, mons
  end

  local function cyclePage(delta, landAt)
    local container = currentContainer()
    if not container.getPages then return false end
    local choices = pageChoicesOf(state, container)
    if not choices or #choices == 0 then return false end
    local newPageId = cyclePageId(choices, pageIdOf(state, container), delta)
    state.pages[container.id] = newPageId
    if container.onPageChange then container.onPageChange(game, newPageId, state.env) end
    rememberPage(state, container, newPageId)
    rebuild()
    if landAt then Screen.setListCursor(state.list, landAt(#state.list.items)) end
    return true
  end

  local function choosePage()
    local container = currentContainer()
    opts.onChoose(nil, { containerId = state.view, pageId = pageIdOf(state, container) })
  end

  local function extraKeys(input)
    if state.rearrange then return handleRearrangeKeys(state, containers, input, rebuild) end
    local container = currentContainer()
    if kind == "picker" and container.choosePage and input:wasPressed("a") then
      choosePage()
      return true
    elseif input:wasPressed("start") then
      openStartMenu(state, containers, container, pageIdOf(state, container), rebuild)
      return true
    end
    if state.list and state.list.grid then
      local dir = GridUi.direction(state.gridHold, input)
      if not dir then return false end
      local list = state.list
      local before = list.index
      GridUi.navigate(list, dir, cyclePage)
      if list == state.list and list.index ~= before and list.beep then list:beep() end
      return true
    elseif input:wasPressed("left") or input:wasPressed("right") then
      return cyclePage(input:wasPressed("left") and -1 or 1)
    end
    return false
  end

  local modernUi = {}
  for k, v in pairs(opts.modernUi or {}) do modernUi[k] = v end
  if modernUi.left == nil then modernUi.left = function() cyclePage(-1) end end
  if modernUi.right == nil then modernUi.right = function() cyclePage(1) end end
  if kind == "picker" and modernUi.select == nil then
    for _, c in ipairs(containers) do
      if c.choosePage then modernUi.select = choosePage break end
    end
  end

  group = Screen.listGroup(game, {
    screenId = opts.screenId,
    readOnly = opts.readOnly,
    counter = opts.counter,
    onClose = opts.onClose,
    views = views,
    state = state,
    startView = opts.startView,
    title = titleOf,
    label = function(view) return byId[view].label end,
    build = build,
    extraKeys = extraKeys,
    dynamicFooter = function(view, item, nextLabel)
      local container = byId[view]
      if not container.dynamicFooter then return nil end
      return container.dynamicFooter(game, pageIdOf(state, container), item and item.value, nextLabel, state.env)
    end,
    modernUi = modernUi,
  })

  local origScreenRebuild = group.screen.rebuild
  function group.screen:rebuild(title, rows, listOpts, mons)
    origScreenRebuild(self, title, rows, listOpts, mons)
    local container = currentContainer()
    local heldMarks = opts.heldItemMarks or container.heldItemMarks
    local columns = columnsOf(state, container, pageIdOf(state, container))
    if columns > 1 then
      GridUi.attach(self.list, {
        columns = columns,
        decorate = function(items, rowMons, pageId) decorateGrid(state, container, pageId, items, heldMarks and rowMons) end,
        drawHeldMark = function(x, y, mon) drawHeldMarkAt(x, y, mon, game) end,
        isMoving = function() return state.rearrange ~= nil end,
      }).decorate(self.list.items, mons, pageIdOf(state, container))
    elseif heldMarks and mons then Screen.attachHeldItemMarks(self.list, mons, game) end
    state.list = self.list
    local list = self.list
    local baseDraw = list.draw

    local function defaultDraw(self)
      baseDraw(self)
      local pageId = pageIdOf(state, container)
      if pageId ~= nil and pageId == rememberedPageOf(state, container) then Screen.drawTitleMark(self) end
    end

    function list:draw()
      if container.draw then container.draw(game, pageIdOf(state, container), self, function() defaultDraw(self) end, state.env) else defaultDraw(self) end
    end
  end
  
  group.rebuild()
  state.env.screen = group.screen
  
  function group.screen.refresh(preserveCursor) group.rebuild(preserveCursor) end

  function group.screen.jumpTo(containerId, pageId, preserveCursor)
    if not byId[containerId] then return end
    state.view = containerId
    local container = byId[containerId]
    if container.getPages and pageId ~= nil then state.pages[containerId] = pageId end
    group.rebuild(preserveCursor)
  end

  return group
end

function Screen.entryScreen(game, containers, opts)
  opts = opts or {}
  return buildEngine(game, containers, opts, "entry").screen
end

function Screen.pickerScreen(game, containers, opts)
  opts = opts or {}
  return buildEngine(game, containers, opts, "picker").screen
end

return Screen
