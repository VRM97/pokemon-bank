local V = ...

local Gen3Ui = {}

local LAYER_ID = "vrm_pokemon_bank_ui"
local MENU_ID = "vrm_pokemon_bank_menu"
local HOLD_B_FRAMES = 90
local ENGINE_ROWS = 5
local MENU_MAX_VISIBLE_ROWS = 6

local function playSe(id) pcall(function() require("src.core.game3.audio").playSe(id) end) end

local function realTime() return love.timer and love.timer.getTime and love.timer.getTime() or 0 end

local function realDt(state)
  local now = love.timer and love.timer.getTime and love.timer.getTime()
  if not now then return 1 / 60 end
  local dt = state.lastTime and math.max(0, now - state.lastTime) or 1 / 60
  state.lastTime = now
  return dt
end

local function engineRows(session)
  local flags = session and (session.flags or session.eventFlags) or {}
  local isBill = flags[0x828] or flags["FLAG_SYS_NOT_SOMEONES_PC"] or false
  local name = (session and (session.name or session.playerName)) or "RED"
  return {
    { engine = 1, label = isBill and "BILL's PC" or "SOMEONE's PC" },
    { engine = 2, label = string.format("%s's PC", name) },
    { engine = 3, label = "PROF. OAK's PC" },
    { engine = 4, label = "HALL OF FAME" },
    { engine = 5, label = "LOG OFF" },
  }
end

local function prepareWidgets()
  local okFont, Font = pcall(require, "src.render.Font")
  if okFont and type(Font) == "table" and not (Font.ttfActive and Font.ttfActive()) then pcall(Font.load, { font = { ttf = {} } }) end
  local okSound, Base = pcall(require, "src.core.Sound")
  if okSound and type(Base) == "table" and type(Base.play) == "function" and not Base.vrmBankSafe then
    local play = Base.play
    Base.play = function(...)
      local ok, result = pcall(play, ...)
      if ok then return result end
    end
    Base.vrmBankSafe = true
  end
  if not (okFont and type(Font) == "table" and Font.TTF_BASE) or Font.vrmBankGlyphs then return end
  Font.vrmBankGlyphs = true
  local okTheme, Theme = pcall(require, "src.ui.Theme")
  if okTheme and type(Theme) == "table" then
    Theme.cursor = Font.TTF_BASE + 0x25B6
    Theme.cursorHollow = Font.TTF_BASE + 0x25B7
    Theme.moreArrow = Font.TTF_BASE + 0x25BC
  end
  if type(Font.drawBox) == "function" then
    Font.drawBox = function(tx, ty, tw, th, fill)
      local r, g, b, a = love.graphics.getColor()
      if type(fill) == "table" and fill[1] and fill[2] and fill[3] then love.graphics.setColor(fill[1] / 255, fill[2] / 255, fill[3] / 255, 1)
      else love.graphics.setColor(1, 1, 1, 1) end
      love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", tx * 8 + 2, ty * 8 + 2, tw * 8 - 4, th * 8 - 4)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", tx * 8 + 3, ty * 8 + 3, tw * 8 - 6, th * 8 - 6)
      love.graphics.setColor(r, g, b, a)
    end
  end
end

function Gen3Ui.install(mod, opts)
  local okPc, PcMenu = pcall(require, "src.ui.game3.pc_menu")
  local okStack, Stack = pcall(require, "src.ui.game3.stack")
  local okWindow, Window = pcall(require, "src.ui.game3.window")
  local okChrome, Chrome = pcall(require, "src.ui.game3.chrome")
  if not (okPc and okStack and okWindow and okChrome and type(PcMenu) == "table") then
    mod.log:warn("FireRed PC menu not found: the Bank has no PC row")
    return false
  end

  V.require("Widgets").gen3 = true

  local function buildRows()
    local rows = engineRows(PcMenu._session)
    if not opts.enabled() then return rows, false end
    local position = opts.position()
    local at = 3
    if position == "start" then at = 1 elseif position == "middle" then at = 2 end
    table.insert(rows, at, { label = opts.label, bank = true })
    return rows, true
  end

  local function displayIndexOf(rows, engineIndex)
    for i, row in ipairs(rows) do
      if row.engine == engineIndex then return i end
    end
    return 1
  end

  local screens, held, timing = {}, 0, {}
  local currentInput

  local function closeAll()
    while #screens > 0 do
      local screen = table.remove(screens)
      if type(screen.exit) == "function" then pcall(screen.exit, screen) end
    end
    Stack.pop(LAYER_ID)
    held = 0
  end

  local function fail(err)
    mod.log:error("Bank screen failed: %s", tostring(err))
    closeAll()
    PcMenu._status = "The BANK stopped.\nSee the log."
  end

  local layer = {}

  function layer.handleInput(input)
    currentInput = input
    if input and input.isDown and input:isDown("b") then
      held = held + 1
      if held >= HOLD_B_FRAMES then closeAll() return end
    else held = 0 end
    local top = screens[#screens]
    if top and top.update then
      local ok, err = pcall(top.update, top, realDt(timing))
      if not ok then fail(err) end
    end
  end

  function layer.draw()
    local first = 1
    for i, screen in ipairs(screens) do
      if screen.isOpaque then first = i end
    end
    for i = first, #screens do
      local screen = screens[i]
      if screen.draw then
        local ok, err = pcall(screen.draw, screen)
        if not ok then fail(err) return end
      end
    end
  end

  local bridgeStack = {}

  function bridgeStack:push(screen, ...)
    screens[#screens + 1] = screen
    if type(screen.enter) == "function" then screen.enter(screen, ...) end
    if #screens == 1 then Stack.push(LAYER_ID, layer, { hideBelow = true }) end
  end

  function bridgeStack:pop()
    local screen = table.remove(screens)
    if screen and type(screen.exit) == "function" then screen.exit(screen) end
    if #screens == 0 then
      Stack.pop(LAYER_ID)
      held = 0
    end
    return screen
  end

  function bridgeStack:top() return screens[#screens] end

  local bridged = setmetatable({}, { __mode = "k" })

  local function bridgeGame(game)
    local data = setmetatable({ screens = opts.screens or {} }, { __index = game.data })
    local out = setmetatable({ stack = bridgeStack, data = data }, {
      __index = function(_, key)
        local value = game[key]
        if value == nil and key == "input" then return currentInput end
        return value
      end,
    })
    bridged[out] = true
    return out
  end

  local function readyGame(game)
    if bridged[game] then return game end
    prepareWidgets()
    if #screens == 0 then
      timing = {}
      held = 0
    end
    return bridgeGame(game)
  end

  local function openBank()
    local game = opts.getGame()
    if not game then return end
    local ok, err = pcall(opts.openBank, readyGame(game))
    if not ok then fail(err) end
  end

  local menu = { rows = {}, cursor = 1, scroll = 0 }
  local menuLayer = {}

  local function closeMenu()
    Stack.pop(MENU_ID)
    menu.rows = {}
  end

  local function clampMenuScroll()
    local visible = math.min(#menu.rows, MENU_MAX_VISIBLE_ROWS)
    if menu.cursor - menu.scroll > visible then menu.scroll = menu.cursor - visible end
    if menu.cursor - menu.scroll < 1 then menu.scroll = menu.cursor - 1 end
    if #menu.rows <= visible then menu.scroll = 0 end
  end

  function menuLayer.handleInput(input)
    local count = #menu.rows
    if count == 0 then closeMenu() return end
    if input:wasPressed("up") then
      menu.cursor = ((menu.cursor - 2) % count) + 1
      playSe(5)
    elseif input:wasPressed("down") then
      menu.cursor = (menu.cursor % count) + 1
      playSe(5)
    elseif input:wasPressed("a") then
      local row = menu.rows[menu.cursor]
      playSe(5)
      if row.onSelect then
        local ok, err = pcall(row.onSelect)
        if not ok then
          mod.log:error("Bank menu failed: %s", tostring(err))
          closeMenu()
        end
      else
        closeMenu()
      end
    elseif input:wasPressed("b") then
      playSe(5)
      closeMenu()
    end
    if #menu.rows > 0 then clampMenuScroll() end
  end

  function menuLayer.draw()
    local count = #menu.rows
    if count == 0 then return end
    local visible = math.min(count, MENU_MAX_VISIBLE_ROWS)
    local widest = 0
    for _, row in ipairs(menu.rows) do widest = math.max(widest, #row.label) end
    local w = math.max(10, widest + 1)
    Window.stdFrame(Window.template(1, 1, w, visible * 2))
    for slot = 1, visible do
      local i = menu.scroll + slot
      local row = menu.rows[i]
      if not row then break end
      local yPx = 10 + (slot - 1) * 16
      if i == menu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(row.label, 20, yPx)
    end
    if menu.scroll + visible < count then
      Chrome.promptArrow((1 + w) * 8 - 12, (1 + visible * 2) * 8 - 10, math.floor(realTime() * 8))
    end
    Window.dialogueFrame()
    local description = menu.rows[menu.cursor].description
    if description then
      local lines = {}
      for line in tostring(description):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
  end

  local function openMenu(rows)
    menu.rows, menu.cursor, menu.scroll = rows, 1, 0
    Stack.push(MENU_ID, menuLayer, { hideBelow = true })
  end

  local engineInput = PcMenu.handleInput
  local engineDraw = PcMenu.draw
  if PcMenu.vrmBankInput then engineInput, engineDraw = PcMenu.vrmBankInput, PcMenu.vrmBankDraw end
  PcMenu.vrmBankInput, PcMenu.vrmBankDraw = engineInput, engineDraw

  local function delegate(input, rows)
    local before = PcMenu.mode
    engineInput(input)
    if before ~= "root" and PcMenu.mode == "root" and rows then PcMenu.cursor = displayIndexOf(rows, PcMenu.cursor) end
  end

  PcMenu.handleInput = function(input)
    if not PcMenu.open then return engineInput(input) end
    local rows, hasBank = buildRows()
    if PcMenu.mode ~= "root" then return delegate(input, hasBank and rows or nil) end
    if not hasBank then
      PcMenu.cursor = math.min(PcMenu.cursor, ENGINE_ROWS)
      return engineInput(input)
    end
    PcMenu.cursor = math.max(1, math.min(PcMenu.cursor, #rows))
    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #rows) + 1
      playSe(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #rows) + 1
      playSe(5)
    elseif input:wasPressed("a") then
      local row = rows[PcMenu.cursor]
      if row.bank then
        playSe(5)
        playSe(2)
        openBank()
      else
        PcMenu.cursor = row.engine
        engineInput(input)
      end
    else
      engineInput(input)
    end
  end

  PcMenu.draw = function()
    if not PcMenu.open or PcMenu.mode ~= "root" then return engineDraw() end
    local rows, hasBank = buildRows()
    if not hasBank then return engineDraw() end
    Window.stdFrame(Window.template(1, 1, 14, #rows * 2))
    for i, row in ipairs(rows) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(row.label, 20, yPx)
    end
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do lines[#lines + 1] = line end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
  end

  return { bridgeGame = readyGame, openMenu = openMenu, isBridged = function(game) return bridged[game] == true end }
end

return Gen3Ui
