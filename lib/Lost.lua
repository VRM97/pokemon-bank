local V = ...

local ListMenu = require("src.ui.ListMenu")

local SCREEN_ID = "PokemonBankLost"

local VIEWS = { "pokemon", "items", "moves" }
local VIEW_TITLE = { pokemon = "LOST PKMN", items = "LOST ITEMS", moves = "LOST MOVES" }

local Module = {}

function Module.install(mod, core)
  local attachLevelIcons = core.attachLevelIcons
  local monName = core.monName

  local function pokemonRows(game)
    local entries = mod.exports.listInvalidPokemon and mod.exports.listInvalidPokemon() or {}
    local rows, mons = {}, {}
    for _, entry in ipairs(entries) do
      local mon = entry.mon
      rows[#rows + 1] = { label = monName(game, mon) }
      mons[#mons + 1] = mon
    end
    return rows, mons
  end

  local function idRows(map)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
    local rows = {}
    for _, id in ipairs(ids) do
      rows[#rows + 1] = { label = core.truncateName(id), right = "x" .. tostring(map[id]) }
    end
    return rows
  end

  local function buildLostScreen(game)
    local state = { view = "pokemon" }
    local screen = { isOpaque = true }
    local list, rebuild, close

    local function nextView()
      local idx = 1
      for i, v in ipairs(VIEWS) do if v == state.view then idx = i break end end
      return VIEWS[(idx % #VIEWS) + 1]
    end

    local function cycleView()
      state.view = nextView()
      rebuild()
    end

    rebuild = function()
      local rows
      if state.view == "pokemon" then
        local mons
        rows, mons = pokemonRows(game)
        list = ListMenu.new(game, VIEW_TITLE[state.view], rows, { noSound = true, wrap = true })
        attachLevelIcons(list, mons)
      elseif state.view == "items" then
        rows = idRows(mod.exports.listInvalidItems and mod.exports.listInvalidItems() or {})
        list = ListMenu.new(game, VIEW_TITLE[state.view], rows, { noSound = true, wrap = true })
      else
        rows = idRows(mod.exports.listInvalidMoves and mod.exports.listInvalidMoves() or {})
        list = ListMenu.new(game, VIEW_TITLE[state.view], rows, { noSound = true, wrap = true })
      end
      list.footer = "SELECT: " .. VIEW_TITLE[nextView()]
    end

    close = function() game.stack:pop() end

    function screen:update(dt)
      local input = game.input
      if input:wasPressed("select") then
        cycleView()
        return
      elseif input:wasPressed("a") or input:wasPressed("b") then
        close()
        return
      end
      list:update(dt)
    end

    function screen:draw()
      list:draw()
    end

    screen.screenId = SCREEN_ID
    screen.gen1ModernUi = core.gen1ModernUiListAdapter(function() return list end, {
      title = function() return VIEW_TITLE[state.view] end,
      select = function() close() end,
      back = function() close() end,
      start = function() cycleView() end,
    })

    rebuild()
    return screen
  end

  mod.content.screens:register(SCREEN_ID, { new = buildLostScreen })

  mod.exports.lostScreenId = SCREEN_ID

  mod.log:info("Pokemon Bank: Lost viewer ready")

  return {
    screenId = SCREEN_ID,
  }
end

return Module
