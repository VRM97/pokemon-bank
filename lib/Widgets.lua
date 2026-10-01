local GameVersion = require("src.core.GameVersion")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Widgets = { gen3 = false }

function Widgets.active() return Widgets.gen3 and GameVersion.generation() == 3 end

local cachedGen3

local function buildGen3()
  if cachedGen3 then return cachedGen3 end

  local TILE = 8
  local SCREEN_TILES = 30
  local DIALOGUE_TOP = 14
  local MAX_VISIBLE_ROWS = 8
  local CHARS_PER_FRAME = 2
  local PARAGRAPH, WAIT = "\f", "\11"

  local Window = require("src.ui.game3.window")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Chrome = require("src.ui.game3.chrome")

  local Gen3Widgets = {}

  local function playSe(id) pcall(function() require("src.core.game3.audio").playSe(id) end) end

  local function clean(text) return (tostring(text or ""):gsub("<PK><MN>", "POKéMON"):gsub("<PK>", "POKé"):gsub("<MN>", "MON")) end

  local function pixelWidth(text) return tonumber(FrlgFont.measure(text)) or (#text * 7) end

  local function charCount(text)
    local n = 0
    for i = 1, #text do
      local b = text:byte(i)
      if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
  end

  local function realTime() return love.timer and love.timer.getTime and love.timer.getTime() or 0 end

  local function pressed(input, ...)
    for _, key in ipairs({ ... }) do
      if input:wasPressed(key) then return true end
    end
    return false
  end

  local Menu = {}
  Menu.__index = Menu

  function Menu.new(game, items, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      items = items,
      index = 1,
      scroll = 0,
      noWrap = opts.noWrap or false,
      cancelable = opts.cancelable ~= false,
      keepOnCancel = opts.keepOnCancel or false,
      onCancel = opts.onCancel,
      maxVisible = opts.maxVisible or MAX_VISIBLE_ROWS,
      fromRight = (opts.tx or 0) > 0,
      fromBottom = (opts.ty or 0) + (opts.th or 0) >= 16,
    }, Menu)
  end

  function Menu:visibleRows() return math.min(#self.items, self.maxVisible) end

  function Menu:clampScroll()
    local visible = self:visibleRows()
    if self.index - self.scroll > visible then self.scroll = self.index - visible end
    if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
    if #self.items <= visible then self.scroll = 0 end
  end

  function Menu:widthTiles()
    local widest = 0
    for _, item in ipairs(self.items) do widest = math.max(widest, pixelWidth(clean(item.label))) end
    return math.max(6, math.ceil((widest + 24) / TILE))
  end

  function Menu:update()
    local input = self.game.input
    local count = #self.items
    if count == 0 then return end
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or (self.noWrap and 1 or count)
      playSe(5)
    elseif input:wasPressed("down") then
      self.index = self.index < count and self.index + 1 or (self.noWrap and count or 1)
      playSe(5)
    elseif input:wasPressed("a") then
      playSe(5)
      local item = self.items[self.index]
      if not item.keepOpen then self.game.stack:pop() end
      if item.onSelect then item.onSelect() end
    elseif self.cancelable and input:wasPressed("b") then
      playSe(5)
      if not self.keepOnCancel then self.game.stack:pop() end
      if self.onCancel then self.onCancel() end
    end
    self:clampScroll()
  end

  function Menu:draw()
    local visible = self:visibleRows()
    if visible == 0 then return end
    local w, h = self:widthTiles(), visible * 2
    local left = self.fromRight and (SCREEN_TILES - 1 - w) or 1
    local top = self.fromBottom and (DIALOGUE_TOP - 1 - h) or 1
    top = math.max(1, top)
    Window.stdFrame(Window.template(left, top, w, h))
    for row = 1, visible do
      local index = self.scroll + row
      local item = self.items[index]
      if not item then break end
      local y = top * TILE + 2 + (row - 1) * 16
      if index == self.index then Window.cursorPx(left * TILE + 4, y) end
      Window.printPx(clean(item.label), left * TILE + 12, y)
    end
    if self.scroll + visible < #self.items then Chrome.promptArrow((left + w) * TILE - 12, (top + h) * TILE - 10, math.floor(realTime() * 8)) end
  end

  local ChoiceBox = {}
  ChoiceBox.__index = ChoiceBox

  local CHOICE_LEFT, CHOICE_TOP, CHOICE_W, CHOICE_H = 23, 9, 6, 4

  function ChoiceBox.new(game, onChoose, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      onChoose = onChoose,
      index = opts.defaultNo and 2 or 1,
      labels = opts.labels or { "YES", "NO" },
    }, ChoiceBox)
  end

  function ChoiceBox:answer(yes)
    playSe(5)
    self.game.stack:pop()
    self.onChoose(yes)
  end

  function ChoiceBox:update()
    local input = self.game.input
    if pressed(input, "up", "down") then
      self.index = self.index == 1 and 2 or 1
      playSe(5)
    elseif input:wasPressed("a") then self:answer(self.index == 1)
    elseif input:wasPressed("b") then self:answer(false) end
  end

  function ChoiceBox:draw()
    Window.stdFrame(Window.template(CHOICE_LEFT, CHOICE_TOP, CHOICE_W, CHOICE_H))
    for i, label in ipairs(self.labels) do
      local y = CHOICE_TOP * TILE + 2 + (i - 1) * 16
      if i == self.index then Window.cursorPx(CHOICE_LEFT * TILE + 4, y) end
      Window.printPx(clean(label), CHOICE_LEFT * TILE + 12, y)
    end
  end

  local TextBox = {}
  TextBox.__index = TextBox

  local function parse(text)
    local paragraphs = {}
    text = clean(text)
    local start = 1
    repeat
      local stop = text:find(PARAGRAPH, start, true)
      local chunk = text:sub(start, (stop or #text + 1) - 1)
      local lines, pos = {}, 1
      while true do
        local s = chunk:find("[\n\11]", pos)
        if not s then
          lines[#lines + 1] = { text = chunk:sub(pos), wait = false }
          break
        end
        lines[#lines + 1] = { text = chunk:sub(pos, s - 1), wait = chunk:sub(s, s) == WAIT }
        pos = s + 1
      end
      if #lines > 1 and lines[#lines].text == "" then lines[#lines] = nil end
      if #lines > 1 or lines[1].text ~= "" or #paragraphs == 0 then paragraphs[#paragraphs + 1] = lines end
      start = stop and stop + 1
    until not start
    return paragraphs
  end

  function TextBox.new(game, text, onDone, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      onDone = onDone,
      choice = opts.choice,
      defaultNo = opts.defaultNo,
      paragraphs = parse(text),
      paragraph = 1,
      line = 1,
      shown = 0,
      state = "typing",
      tick = 0,
    }, TextBox)
  end

  function TextBox:nextLine()
    self.line, self.shown, self.state = self.line + 1, 0, "typing"
  end

  function TextBox:finish()
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end

  function TextBox:update()
    self.tick = self.tick + 1
    local input = self.game.input
    local lines = self.paragraphs[self.paragraph]
    local line = lines[self.line]
    if self.state == "typing" then
      local total = charCount(line.text)
      self.shown = pressed(input, "a", "b") and total or self.shown + CHARS_PER_FRAME
      if self.shown >= total then self.shown, self.state = total, "typed" end
    elseif self.state == "typed" then
      if self.line < #lines then
        if line.wait then self.state = "wait" else self:nextLine() end
      elseif self.paragraph < #self.paragraphs then self.state = "wait"
      elseif self.choice then
        self.state = "choice"
        self.game.stack:push(ChoiceBox.new(self.game, function(yes)
          self.game.stack:pop()
          self.choice(yes)
        end, { defaultNo = self.defaultNo }))
      else self.state = "wait" end
    elseif self.state == "wait" and pressed(input, "a", "b") then
      playSe(5)
      if self.line < #lines then self:nextLine()
      elseif self.paragraph < #self.paragraphs then self.paragraph, self.line, self.shown, self.state = self.paragraph + 1, 1, 0, "typing"
      else self:finish() end
    end
  end

  function TextBox:draw()
    Window.dialogueFrame()
    local lines = self.paragraphs[self.paragraph]
    local first = math.max(1, self.line - 1)
    for i = first, self.line do
      local limit = i == self.line and self.state == "typing" and self.shown or nil
      Window.print(lines[i].text, 2, 15 + (i - first) * 2, { clipTiles = 26, limitChars = limit })
    end
    if self.state == "wait" then Chrome.promptArrow(210, 140, math.floor(self.tick / 8)) end
  end

  local ListMenu = {}
  ListMenu.__index = ListMenu
  ListMenu.isOpaque = true

  local LIST_LEFT, LIST_TOP, LIST_W, LIST_H = 1, 1, 28, 12
  local LIST_ROWS = 5
  local CURSOR_X, LABEL_X = 14, 22
  local RIGHT_X = (LIST_LEFT + LIST_W) * TILE - 8
  local REPEAT_DELAY, REPEAT_RATE = 20, 4

  local function lineY(line) return LIST_TOP * TILE + 2 + line * 16 end
  Gen3Widgets.listLineY = lineY

  local function fit(text, pixels)
    if pixelWidth(text) <= pixels then return text end
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    while #chars > 0 and pixelWidth(table.concat(chars) .. ".") > pixels do chars[#chars] = nil end
    return table.concat(chars) .. "."
  end

  local function drawFooter(footer)
    Window.dialogueFrame()
    if not footer then return end
    local lines = {}
    for line in clean(footer):gmatch("[^\r\n\f\11]+") do lines[#lines + 1] = line end
    for i = math.max(1, #lines - 1), #lines do Window.print(lines[i], 2, 15 + (i - math.max(1, #lines - 1)) * 2, { clipTiles = 26 }) end
  end

  function ListMenu.new(game, title, items, opts)
    opts = opts or {}
    return setmetatable({
      game = game,
      title = title,
      kind = opts.kind or title,
      items = items,
      index = 1,
      scroll = 0,
      rows = math.max(1, math.min(math.floor(tonumber(opts.rows) or LIST_ROWS), LIST_ROWS)),
      onChoose = opts.onChoose,
      onCancel = opts.onCancel,
      onSelectKey = opts.onSelectKey,
      footer = opts.footer,
      pageJump = opts.pageJump,
      wrap = opts.wrap,
      itemBox = opts.itemBox or opts.messageBox or false,
      noSound = opts.noSound or false,
      holdFrames = 0,
    }, ListMenu)
  end

  function ListMenu:moveIndex(delta)
    local count = #self.items
    local target = self.index + delta
    if self.wrap then target = ((target - 1) % count) + 1 else target = math.max(1, math.min(count, target)) end
    self.index = target
  end

  function ListMenu:syncScroll()
    if self.index - self.scroll > self.rows then self.scroll = self.index - self.rows end
    if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
  end

  function ListMenu:direction(input)
    local dirs = self.pageJump and { "up", "down", "left", "right" } or { "up", "down" }
    for _, dir in ipairs(dirs) do
      if input:wasPressed(dir) then
        self.holdDir, self.holdFrames = dir, 0
        return dir
      end
    end
    if self.holdDir and input.isDown and input:isDown(self.holdDir) then
      self.holdFrames = self.holdFrames + 1
      if self.holdFrames >= REPEAT_DELAY and (self.holdFrames - REPEAT_DELAY) % REPEAT_RATE == 0 then return self.holdDir end
    else self.holdDir = nil end
    return nil
  end

  function ListMenu:beep() if not self.noSound then playSe(5) end end

  function ListMenu:update()
    local input = self.game.input
    self.hollowIndex = nil
    if #self.items == 0 then
      if pressed(input, "a", "b") then
        self:beep()
        self.game.stack:pop()
        if self.onCancel then self.onCancel() end
      end
      return
    end
    local dir = self:direction(input)
    if dir then
      local step = { up = -1, down = 1, left = -self.rows, right = self.rows }
      self:moveIndex(step[dir])
      self:beep()
    elseif self.onSelectKey and input:wasPressed("select") then self.onSelectKey(self.items[self.index], self)
    elseif input:wasPressed("b") then
      self:beep()
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
      return
    elseif input:wasPressed("a") then
      self:beep()
      if self.onChoose then self.onChoose(self.items[self.index], self) end
      return
    end
    self:syncScroll()
  end

  function ListMenu:removeCurrent()
    table.remove(self.items, self.index)
    self.index = math.max(1, math.min(self.index, #self.items))
  end

  function ListMenu:close()
    if self.game.stack:top() == self then self.game.stack:pop() end
  end

  function ListMenu:draw()
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
    Window.printPx(clean(Strings(self.title)), LABEL_X - 6, lineY(0))
    if #self.items == 0 then Window.printPx(Strings("Nothing here."), LABEL_X, lineY(1)) end
    for row = 1, self.rows do
      local item = self.items[self.scroll + row]
      if not item then break end
      local y = lineY(row)
      local right = item.right or item.sub
      local rightText = right ~= nil and clean(right) or nil
      local budget = RIGHT_X - LABEL_X - (rightText and pixelWidth(rightText) + 8 or 0)
      Window.printPx(fit(clean(item.label), budget), LABEL_X, y)
      if rightText then Window.printPx(rightText, RIGHT_X - pixelWidth(rightText), y) end
      if self.scroll + row == self.index then Window.cursorPx(CURSOR_X, y) end
    end
    if self.scroll + self.rows < #self.items then Chrome.promptArrow(RIGHT_X - 4, (LIST_TOP + LIST_H) * TILE - 12, math.floor(realTime() * 8)) end
    drawFooter(self.footer)
  end

  function Gen3Widgets.drawListCounter(list, text) Window.printPx(text, RIGHT_X - pixelWidth(text), lineY(0)) end

  function Gen3Widgets.drawListMark(list, row, label)
    local text = row == 0 and clean(Strings(list.title)) or clean(label)
    local x = (row == 0 and LABEL_X - 6 or LABEL_X) + pixelWidth(text) + 4
    love.graphics.setColor(56 / 255, 56 / 255, 56 / 255, 1)
    love.graphics.rectangle("fill", x, lineY(row) + 5, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  function Gen3Widgets.drawHeldIconAt(x, y, mon)
    local okP, PartyMenu = pcall(require, "src.ui.game3.party_menu")
    if not (okP and PartyMenu.heldItemFrame and PartyMenu.heldItemSheet) then return false end
    local okF, frame = pcall(PartyMenu.heldItemFrame, mon)
    local okS, sheet = pcall(PartyMenu.heldItemSheet)
    local quad = okF and frame and okS and sheet and sheet.quads[frame]
    if not quad then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sheet.image, quad, x, y)
    return true
  end

  function Gen3Widgets.drawListHeldIcon(list, row, label, mon)
    return Gen3Widgets.drawHeldIconAt(LABEL_X + pixelWidth(clean(label)) + 2, lineY(row) + 3, mon)
  end

  local GRID_AREA = { x = 12, y = lineY(1), w = RIGHT_X - 8 - 12, h = (LIST_TOP + LIST_H) * TILE - lineY(1) }

  function Gen3Widgets.gridArea() return GRID_AREA end

  Gen3Widgets.gridColors = { line = { 200 / 255, 200 / 255, 208 / 255, 1 }, selected = { 56 / 255, 56 / 255, 56 / 255, 1 } }

  function Gen3Widgets.drawGridChrome(list, hasMore)
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
    Window.printPx(clean(Strings(list.title)), LABEL_X - 6, lineY(0))
    if #list.items == 0 then Window.printPx(Strings("Nothing here."), LABEL_X, lineY(1)) end
    if hasMore then Chrome.promptArrow(RIGHT_X - 4, (LIST_TOP + LIST_H) * TILE - 12, math.floor(realTime() * 8)) end
    drawFooter(list.footer)
  end

  function Gen3Widgets.gridText(text, x, y, width) Window.printPx(fit(clean(text), width), x, y) end

  function Gen3Widgets.textWidth(text) return pixelWidth(clean(text)) end

  local Report = {}
  Report.__index = Report
  Report.isOpaque = true

  local function readable(id) return (tostring(id or "?"):gsub("_", " ")) end

  local function monName(mon)
    for _, name in ipairs({ mon.nickname, mon.species, mon.speciesAlt, mon.name }) do
      if type(name) == "string" and name ~= "" then return readable(name) end
    end
    return readable(mon.species)
  end

  function Gen3Widgets.reportLines(report)
    local lines = {}
    local rows

    local function section(header, rows)
      if #rows == 0 then return end
      if #lines > 0 then lines[#lines + 1] = "" end
      lines[#lines + 1] = header
      for _, row in ipairs(rows) do lines[#lines + 1] = "  " .. row end
    end

    local function appendRow(str, ...) rows[#rows + 1] = (str):format(...) end

    rows = {}
    for _, mon in ipairs(report.lostMons or {}) do appendRow("%s (%s)", monName(mon), tostring(mon.from or "?")) end
    section("POKéMON set aside:", rows)
    rows = {}
    for _, item in ipairs(report.lostItems or {}) do appendRow("%s x%d (%s)", readable(item.id), item.count or 1, tostring(item.from or "?")) end
    section("Items set aside:", rows)
    rows = {}
    for _, mon in ipairs(report.restoredMons or {}) do appendRow("%s to box %d", monName(mon), mon.box or 0) end
    for _, item in ipairs(report.restoredItems or {}) do appendRow("%s x%d", readable(item.id), item.count or 1) end
    section("Restored:", rows)
    return lines
  end

  function Report.new(game, report) return setmetatable({ game = game, lines = Gen3Widgets.reportLines(report or {}), offset = 0 }, Report) end

  function Report:maxOffset() return math.max(0, #self.lines - LIST_ROWS) end

  function Report:update()
    local input = self.game.input
    if input:wasPressed("up") then
      self.offset = math.max(0, self.offset - 1)
      playSe(5)
    elseif input:wasPressed("down") then
      self.offset = math.min(self:maxOffset(), self.offset + 1)
      playSe(5)
    elseif pressed(input, "a", "b", "start") then
      playSe(5)
      self.game.stack:pop()
    end
  end

  function Report:draw()
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
    Window.printPx("LOAD REPORT", LABEL_X - 6, lineY(0))
    for row = 1, LIST_ROWS do
      local line = self.lines[self.offset + row]
      if line then Window.printPx(line, LABEL_X - 6, lineY(row)) end
    end
    if self.offset < self:maxOffset() then Chrome.promptArrow(RIGHT_X - 4, (LIST_TOP + LIST_H) * TILE - 12, math.floor(realTime() * 8)) end
    Window.dialogueFrame()
    Window.print("Up/Down: scroll", 2, 15, { clipTiles = 26 })
    Window.print("A: continue", 2, 17, { clipTiles = 26 })
  end

  function Gen3Widgets.panelRows(panel)
    local used = #(panel.options or {}) + (panel.entry and 1 or 0)
    return math.max(0, LIST_ROWS - used)
  end

  function Gen3Widgets.drawPanel(panel)
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
    Window.printPx(clean(panel.title), LABEL_X - 6, lineY(0))
    if panel.right then
      local right = clean(panel.right)
      Window.printPx(right, RIGHT_X - pixelWidth(right), lineY(0))
    end
    local row = 1
    for i, text in ipairs(panel.options or {}) do
      Window.printPx(clean(text), LABEL_X, lineY(row))
      if i == panel.cursor then Window.cursorPx(CURSOR_X, lineY(row)) end
      row = row + 1
    end
    if panel.entry then
      local x = LABEL_X - 6
      for _, cell in ipairs(panel.entry.cells) do
        local text = clean(cell.text)
        local width = pixelWidth(text)
        Window.printPx(text, x, lineY(row))
        if cell.index ~= nil and cell.index == panel.entry.pos then
          love.graphics.setColor(56 / 255, 56 / 255, 56 / 255, 1)
          love.graphics.rectangle("fill", x, lineY(row) + 13, width, 1)
          love.graphics.setColor(1, 1, 1, 1)
        end
        x = x + width + (cell.sep and 1 or 3)
      end
      row = row + 1
    end
    local lines, offset, visible = panel.lines or {}, panel.offset or 0, Gen3Widgets.panelRows(panel)
    for i = 1, visible do
      local text = lines[offset + i]
      if text then Window.printPx(clean(text), LABEL_X - 6, lineY(row + i - 1)) end
    end
    if offset + visible < #lines then Chrome.promptArrow(RIGHT_X - 4, (LIST_TOP + LIST_H) * TILE - 12, math.floor(realTime() * 8)) end
    Window.dialogueFrame()
    local hints = panel.hints or {}
    for i = 1, math.min(2, #hints) do Window.print(clean(hints[i]), 2, 15 + (i - 1) * 2, { clipTiles = 26 }) end
  end

  function Gen3Widgets.drawInfoBox(rows, opts)
    opts = opts or {}
    local widest = 0
    for _, row in ipairs(rows) do widest = math.max(widest, pixelWidth(clean(row[1])) + (row[1] ~= "" and 16 or 0) + pixelWidth(clean(row[2]))) end
    local w, h = math.max(8, math.ceil((widest + 16) / TILE)), #rows * 2
    local left = SCREEN_TILES - 1 - w
    local top = opts.position == "topright" and 1 or DIALOGUE_TOP - 1 - h
    Window.stdFrame(Window.template(left, top, w, h))
    for i, row in ipairs(rows) do
      local y = top * TILE + 2 + (i - 1) * 16
      local value = clean(row[2])
      Window.printPx(clean(row[1]), left * TILE + 8, y)
      Window.printPx(value, (left + w) * TILE - 8 - pixelWidth(value), y)
    end
  end

  local QuantityBox = {}
  QuantityBox.__index = QuantityBox

  function QuantityBox.new(game, opts)
    local max = math.max(1, opts.max or 99)
    return setmetatable({
      game = game,
      max = max,
      qty = math.min(opts.start or 1, max),
      unitPrice = opts.unitPrice,
      onDone = opts.onDone,
      keepOpen = opts.keepOpen,
    }, QuantityBox)
  end

  local function wrap(value, max)
    if value < 1 then return max end
    if value > max then return 1 end
    return value
  end

  function QuantityBox:answer(qty)
    playSe(5)
    if not self.keepOpen then self.game.stack:pop() end
    if self.onDone then self.onDone(qty) end
  end

  function QuantityBox:update()
    local input = self.game.input
    if input:wasPressed("up") then
      self.qty = wrap(self.qty + 1, self.max)
      playSe(5)
    elseif input:wasPressed("down") then
      self.qty = wrap(self.qty - 1, self.max)
      playSe(5)
    elseif input:wasPressed("right") then
      self.qty = math.min(self.max, self.qty + 10)
      playSe(5)
    elseif input:wasPressed("left") then
      self.qty = math.max(1, self.qty - 10)
      playSe(5)
    elseif input:wasPressed("a") then self:answer(self.qty)
    elseif input:wasPressed("b") then self:answer(nil) end
  end

  function QuantityBox:draw()
    local w = self.unitPrice and 12 or 6
    local left, top = SCREEN_TILES - 1 - w, DIALOGUE_TOP - 1 - 2
    Window.stdFrame(Window.template(left, top, w, 2))
    local y = top * TILE + 2
    Window.printPx(("×%02d"):format(self.qty), left * TILE + 8, y)
    if self.unitPrice then
      local price = "¥" .. tostring(math.floor(self.qty * self.unitPrice))
      Window.printPx(price, (left + w) * TILE - 8 - pixelWidth(price), y)
    end
  end

  function Gen3Widgets.drawAmountBox(box)
    local prefix = box.prefix or ""
    local balances = {
      { box.walletLabel, prefix .. tostring(box.wallet) },
      { box.bankLabel, prefix .. tostring(box.bank) },
      { "AMOUNT", prefix .. table.concat(box.digits) },
    }
    local widest = 0
    for _, row in ipairs(balances) do widest = math.max(widest, pixelWidth(clean(row[1])) + 16 + pixelWidth(row[2])) end
    local w, h = math.max(10, math.ceil((widest + 16) / TILE)), #balances * 2
    local left, top = SCREEN_TILES - 1 - w, DIALOGUE_TOP - 1 - h
    Window.stdFrame(Window.template(left, top, w, h))
    local amountX, amountY
    for i, row in ipairs(balances) do
      local y = top * TILE + 2 + (i - 1) * 16
      local x = (left + w) * TILE - 8 - pixelWidth(row[2])
      Window.printPx(clean(row[1]), left * TILE + 8, y)
      Window.printPx(row[2], x, y)
      if i == #balances then amountX, amountY = x, y end
    end
    local digits = table.concat(box.digits)
    local before = pixelWidth(prefix .. digits:sub(1, box.pos - 1))
    local width = pixelWidth(digits:sub(box.pos, box.pos))
    love.graphics.setColor(56 / 255, 56 / 255, 56 / 255, 1)
    love.graphics.rectangle("fill", amountX + before, amountY + 13, width, 1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  Gen3Widgets.QuantityBox = QuantityBox
  Gen3Widgets.ListMenu = ListMenu
  Gen3Widgets.QuarantineReport = Report
  Gen3Widgets.Menu = Menu
  Gen3Widgets.ChoiceBox = ChoiceBox
  Gen3Widgets.TextBox = TextBox

  cachedGen3 = Gen3Widgets
  return cachedGen3
end

local function widget(name, gen1Module)
  return {
    new = function(...)
      if Widgets.active() then return buildGen3()[name].new(...) end
      return require(gen1Module).new(...)
    end,
  }
end

function Widgets.infoBox(rows, opts) return buildGen3().drawInfoBox(rows, opts) end

function Widgets.listMenu(gen1)
  return { new = function(...)
    if Widgets.active() then return buildGen3().ListMenu.new(...) end
    return gen1.new(...)
  end }
end

function Widgets.drawAmountBox(box) return buildGen3().drawAmountBox(box) end

function Widgets.drawPanel(panel) return buildGen3().drawPanel(panel) end

function Widgets.panelRows(panel) return buildGen3().panelRows(panel) end

function Widgets.drawListCounter(list, text) return buildGen3().drawListCounter(list, text) end

function Widgets.drawListMark(list, row, label) return buildGen3().drawListMark(list, row, label) end

function Widgets.drawListHeldIcon(list, row, label, mon) return buildGen3().drawListHeldIcon(list, row, label, mon) end

function Widgets.drawHeldIconAt(x, y, mon) return buildGen3().drawHeldIconAt(x, y, mon) end

function Widgets.gridArea() return buildGen3().gridArea() end

function Widgets.gridColors() return buildGen3().gridColors end

function Widgets.drawGridChrome(list, hasMore) return buildGen3().drawGridChrome(list, hasMore) end

function Widgets.gridText(text, x, y, width) return buildGen3().gridText(text, x, y, width) end

function Widgets.textWidth(text) return buildGen3().textWidth(text) end

Widgets.QuarantineReport = widget("QuarantineReport", "src.ui.QuarantineReport")
Widgets.Menu = widget("Menu", "src.ui.Menu")
Widgets.TextBox = widget("TextBox", "src.render.TextBox")
Widgets.ChoiceBox = widget("ChoiceBox", "src.ui.ChoiceBox")
Widgets.QuantityBox = widget("QuantityBox", "src.ui.QuantityBox")

function Widgets.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal, extra)
  local gap = 1
  local interior = math.max(#moneyLabel + gap + #moneyVal, #bankLabel + gap + #bankVal, extra or 0)
  local tw = interior + 2
  return tw, math.max(0, 20 - tw)
end

function Widgets.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
  Font.draw(moneyLabel, (tx + 1) * 8, (ty + 1) * 8)
  Font.draw(bankLabel, (tx + 1) * 8, (ty + 2) * 8)
  Font.draw(moneyVal, 160 - 8 - Font.width(moneyVal), (ty + 1) * 8)
  Font.draw(bankVal, 160 - 8 - Font.width(bankVal), (ty + 2) * 8)
end

local function composeDigits(digits, digitCount)
  local n = 0
  for i = 1, digitCount do n = n * 10 + digits[i] end
  return n
end

local AmountBox = {}
AmountBox.__index = AmountBox
AmountBox.isOpaque = false

function AmountBox.new(game, opts)
  local self = setmetatable({}, AmountBox)
  self.game = game
  self.max = math.max(1, math.floor(opts.max or 1))
  self.digitCount = #tostring(self.max)
  self.wallet = math.floor(opts.wallet or 0)
  self.bank = math.floor(opts.bank or 0)
  self.walletLabel = opts.walletLabel or "MONEY"
  self.bankLabel = opts.bankLabel or "BANK"
  self.prefix = opts.prefix
  self.onDone = opts.onDone
  self.title = opts.title
  self:setAmount(opts.start or 1)
  self.pos = self.digitCount

  self.screenId = opts.screenId or "PokemonBankMoneyAmount"
  self.gen1ModernUi = {
    title = function() return self.title or "AMOUNT" end,
    rows = function()
      return {
        { label = self.walletLabel, value = ((self.prefix or "") .. "%d"):format(self.wallet), enabled = false },
        { label = self.bankLabel, value = ((self.prefix or "") .. "%d"):format(self.bank), enabled = false },
        { label = "AMOUNT", value = ((self.prefix or "") .. "%d"):format(self.amount) },
      }
    end,
    index = function() return 3 end,
    scroll = function() return 0 end,
    footer = function() return "A OK   B CANCEL" end,
    up = function() self:stepDigit(1) end,
    down = function() self:stepDigit(-1) end,
    left = function() self:moveCursor(-1) end,
    right = function() self:moveCursor(1) end,
    select = function() self:confirm() end,
    back = function() self:cancel() end,
    start = function() self:jumpMax() end,
  }
  return self
end

function AmountBox:setAmount(amount)
  amount = math.min(self.max, math.max(1, math.floor(amount)))
  self.amount = amount
  local digits = {}
  for i = self.digitCount, 1, -1 do
    digits[i] = amount % 10
    amount = math.floor(amount / 10)
  end
  self.digits = digits
end

function AmountBox:stepDigit(delta)
  self.digits[self.pos] = (self.digits[self.pos] + delta) % 10
  self:setAmount(composeDigits(self.digits, self.digitCount))
end

function AmountBox:moveCursor(delta)
  self.pos = ((self.pos - 1 + delta) % self.digitCount) + 1
end

function AmountBox:jumpMax() self:setAmount(self.max) end

function AmountBox:confirm()
  self.game.stack:pop()
  if self.onDone then self.onDone(self.amount) end
end

function AmountBox:cancel()
  self.game.stack:pop()
  if self.onDone then self.onDone(nil) end
end

function AmountBox:update(dt)
  local input = self.game.input
  if input:wasPressed("up") then self:stepDigit(1)
  elseif input:wasPressed("down") then self:stepDigit(-1)
  elseif input:wasPressed("right") then self:moveCursor(1)
  elseif input:wasPressed("left") then self:moveCursor(-1)
  elseif input:wasPressed("start") then self:jumpMax()
  elseif input:wasPressed("a") then self:confirm()
  elseif input:wasPressed("b") then self:cancel() end
end

function AmountBox:draw()
  if Widgets.active() then return Widgets.drawAmountBox(self) end
  local prefix = self.prefix or ""
  local moneyVal = (prefix .. "%d"):format(self.wallet)
  local bankVal = (prefix .. "%d"):format(self.bank)
  local digitsStr = table.concat(self.digits)
  local amountVal = prefix .. digitsStr
  local moneyLabel, bankLabel = self.walletLabel, self.bankLabel
  local tw, tx = Widgets.walletBankBoxWidth(moneyLabel, moneyVal, bankLabel, bankVal, #amountVal)
  local ty = 9
  Font.drawBox(tx, ty, tw, 6)
  love.graphics.setColor(0, 0, 0, 1)
  Widgets.drawWalletBankRows(tx, ty, moneyLabel, moneyVal, bankLabel, bankVal)
  local amountX = 160 - 8 - Font.width(amountVal)
  Font.draw(amountVal, amountX, (ty + 3) * 8)
  local cursorX = amountX + Font.width(prefix .. digitsStr:sub(1, self.pos - 1))
  Font.drawCode(Theme.moreArrow, cursorX, (ty + 4) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

Widgets.AmountBox = AmountBox

return Widgets
