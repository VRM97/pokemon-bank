local V = ...

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")
local Theme = require("src.ui.Theme")
local Widgets = V.require("Widgets")

local GridUi = { MIN_CELL = 16 }

local GB_AREA = { x = 8, y = 16, w = 144, h = 100 }
local GB_COLORS = { line = { 170 / 255, 170 / 255, 170 / 255, 1 }, selected = { 0, 0, 0, 1 } }
local DIRS = { "up", "down", "left", "right" }
local REPEAT = { [1] = { 30, 5 }, [2] = { 15, 5 }, [3] = { 20, 4 } }

function GridUi.area()
  if Widgets.active() then return Widgets.gridArea() end
  return GB_AREA
end

function GridUi.clampColumns(n)
  n = math.floor(tonumber(n) or 1)
  return math.max(1, math.min(n, math.floor(GridUi.area().w / GridUi.MIN_CELL)))
end

function GridUi.layout(columns)
  local area = GridUi.area()
  local cell = math.floor(area.w / columns)
  return {
    columns = columns,
    cell = cell,
    rows = math.max(1, math.floor(area.h / cell)),
    x = area.x + math.floor((area.w - cell * columns) / 2),
    y = area.y,
  }
end

local function rowOf(grid, index) return math.floor((math.max(1, index) - 1) / grid.columns) + 1 end

local function colOf(grid, index) return ((math.max(1, index) - 1) % grid.columns) + 1 end

local function totalRows(list) return math.ceil(#list.items / list.grid.columns) end

function GridUi.sync(list)
  local grid = list.grid
  local row, top = rowOf(grid, list.index), math.floor((list.scroll or 0) / grid.columns)
  if row > top + grid.rows then top = row - grid.rows end
  if row <= top then top = row - 1 end
  list.scroll = math.max(0, math.min(top, math.max(0, totalRows(list) - grid.rows))) * grid.columns
end

function GridUi.setIndex(list, index)
  local n = #list.items
  list.index = n == 0 and 1 or math.max(1, math.min(n, math.floor(index)))
  GridUi.sync(list)
end

function GridUi.attach(list, opts)
  local grid = GridUi.layout(opts.columns)
  grid.decorate = opts.decorate or function() end
  grid.drawHeldMark = opts.drawHeldMark
  grid.isMoving = opts.isMoving or function() return false end
  list.grid = grid
  list.rows = grid.rows * grid.columns
  list.cursorRows = nil
  list.draw = GridUi.draw
  GridUi.sync(list)
  return grid
end

function GridUi.direction(hold, input)
  for _, dir in ipairs(DIRS) do
    if input:wasPressed(dir) then
      hold.dir, hold.frames = dir, 0
      return dir
    end
  end
  if not (hold.dir and input.isDown and input:isDown(hold.dir)) then
    hold.dir = nil
    return nil
  end
  local timing = REPEAT[GameVersion.generation()] or REPEAT[1]
  hold.frames = hold.frames + 1
  local after = hold.frames - timing[1]
  if after >= 0 and after % timing[2] == 0 then return hold.dir end
  return nil
end

function GridUi.navigate(list, dir, turnPage)
  local grid, n, index = list.grid, #list.items, list.index
  local cols, row, col = grid.columns, rowOf(grid, index), colOf(grid, index)
  local function land(target) return function(count) return math.max(1, math.min(count, target)) end end
  if dir == "up" then
    if n > 0 and index - cols >= 1 then GridUi.setIndex(list, index - cols) end
  elseif dir == "down" then
    if index + cols <= n then GridUi.setIndex(list, index + cols)
    elseif row < totalRows(list) then GridUi.setIndex(list, n) end
  elseif dir == "left" then
    if n == 0 or col == 1 then
      if turnPage then turnPage(-1, land((row - 1) * cols + cols)) end
    else GridUi.setIndex(list, index - 1) end
  elseif dir == "right" then
    if n == 0 or col == cols or index >= n then
      if turnPage then turnPage(1, land((row - 1) * cols + 1)) end
    else GridUi.setIndex(list, index + 1) end
  end
end

function GridUi.iconDrawer(a, b)
  if type(a) == "function" then return a end
  if type(a) ~= "userdata" and type(a) ~= "table" then return nil end
  return function(x, y, size)
    local w, h
    if b then
      local _, _, qw, qh = b:getViewport()
      w, h = qw, qh
    else w, h = a:getDimensions() end
    local s = size / math.max(w, h, 1)
    if s >= 1 then s = math.floor(s) end
    love.graphics.setColor(1, 1, 1, 1)
    local dx, dy = x + math.floor((size - w * s) / 2), y + math.floor((size - h * s) / 2)
    if b then love.graphics.draw(a, b, dx, dy, 0, s, s) else love.graphics.draw(a, dx, dy, 0, s, s) end
  end
end

local function frame(x, y, size, t, color)
  local G = love.graphics
  G.setColor(color)
  G.rectangle("fill", x, y, size, t)
  G.rectangle("fill", x, y + size - t, size, t)
  G.rectangle("fill", x, y, t, size)
  G.rectangle("fill", x + size - t, y, t, size)
end

local function fitGb(text, pixels)
  if Font.width(text) <= pixels then return text end
  local chars = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
  while #chars > 0 and Font.width(table.concat(chars) .. ".") > pixels do chars[#chars] = nil end
  return table.concat(chars) .. "."
end

local function drawLabel(text, x, y, size)
  if Widgets.active() then return Widgets.gridText(text, x + 2, y + math.floor((size - 14) / 2), size - 4) end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(fitGb(text, size - 4), x + 2, y + math.floor((size - 8) / 2))
end

function GridUi.textIcon(text, marked, count, slots)
  return function(x, y, size)
    drawLabel(text, x, y, size)
    if (count or 0) > 0 then
      local full = slots ~= nil and count >= slots
      local gen3 = Widgets.active()
      if full then love.graphics.setColor(gen3 and { 0.85, 0.2, 0.15, 1 } or { 0, 0, 0, 1 })
      else love.graphics.setColor(gen3 and { 0.2, 0.6, 0.25, 1 } or { 0.45, 0.45, 0.45, 1 }) end
      love.graphics.rectangle("fill", x + size - 7, y + size - 7, 4, 4)
    end
    if marked then
      local colors = Widgets.active() and Widgets.gridColors() or GB_COLORS
      love.graphics.setColor(colors.selected)
      love.graphics.rectangle("fill", x + size - 7, y + 3, 4, 4)
    end
  end
end

local function drawGbChrome(list, hasMore)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, 160, 144)
  G.setColor(0, 0, 0, 1)
  Font.draw(Strings(list.title), 8, 4)
  if #list.items == 0 then Font.draw(Strings("Nothing here."), 16, 64) end
  if hasMore then Font.drawCode(Theme.moreArrow, 144, GB_AREA.y + GB_AREA.h - 4) end
  if list.footer then
    local flat = {}
    for _, page in ipairs(require("src.render.TextBox").paginate(list.footer)) do
      for _, line in ipairs(page) do flat[#flat + 1] = line end
    end
    local y = (#flat >= 2) and 120 or 136
    for i = math.max(1, #flat - 1), #flat do
      Font.draw(flat[i], 8, y)
      y = y + 16
    end
  end
end

function GridUi.draw(list)
  local grid = list.grid
  local cols, cell = grid.columns, grid.cell
  local top = math.floor(list.scroll / cols)
  local hasMore = top + grid.rows < totalRows(list)
  if Widgets.active() then Widgets.drawGridChrome(list, hasMore) else drawGbChrome(list, hasMore) end
  local colors = Widgets.active() and Widgets.gridColors() or GB_COLORS
  local selected
  for r = 1, grid.rows do
    for c = 1, cols do
      local i = list.scroll + (r - 1) * cols + c
      local item = list.items[i]
      if not item then break end
      local x, y = grid.x + (c - 1) * cell, grid.y + (r - 1) * cell
      frame(x, y, cell, 1, colors.line)
      if item._gridIcon then
        love.graphics.setColor(1, 1, 1, 1)
        local ok = pcall(item._gridIcon, x + 1, y + 1, cell - 2)
        if not ok then item._gridIcon = false end
      end
      if not item._gridIcon and not item.inert then drawLabel(item.label or "", x, y, cell) end
      if item._gridMon and grid.drawHeldMark then grid.drawHeldMark(x + cell - 10, y + cell - 10, item._gridMon) end
      if i == list.index then selected = { x = x, y = y } end
    end
  end
  if selected then
    frame(selected.x, selected.y, cell, 2, colors.selected)
    if grid.isMoving() then frame(selected.x + 3, selected.y + 3, cell - 6, 1, colors.selected) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return GridUi
