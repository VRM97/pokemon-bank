local EGG_SPECIES = 412

local GameVersion = require("src.core.GameVersion")

local Module = {}

local function buildEggPic()
  if not (love and love.image and love.graphics) then return nil end
  local size, cx, cy, ry = 64, 32, 35, 26
  local data = love.image.newImageData(size, size)
  local function halfWidth(y)
    local t = (y - cy) / ry
    if t < -1 or t > 1 then return nil end
    return 20 * math.sqrt(1 - t * t) * (1 + 0.16 * t)
  end
  local spots = { { 26, 30, 4 }, { 40, 40, 5 }, { 30, 48, 3 }, { 38, 24, 3 } }
  local function inside(x, y)
    local hw = halfWidth(y)
    return hw ~= nil and math.abs(x + 0.5 - cx) <= hw
  end
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      if inside(x, y) then
        local edge = not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
        local r, g, b = 250, 244, 222
        if x + 0.5 - cx > (halfWidth(y) or 0) * 0.45 then r, g, b = 232, 222, 190 end
        for _, spot in ipairs(spots) do
          if (x - spot[1]) ^ 2 + (y - spot[2]) ^ 2 <= spot[3] ^ 2 then r, g, b = 112, 184, 120 end
        end
        if edge then r, g, b = 64, 64, 72 end
        data:setPixel(x, y, r / 255, g / 255, b / 255, 1)
      end
    end
  end
  local image = love.graphics.newImage(data)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return { image = image, w = size, h = size }
end

local function ensureEggPic(Pokemon)
  if type(Pokemon._front) ~= "table" or Pokemon._front[EGG_SPECIES] then return end
  if Pokemon.frontPic(EGG_SPECIES) then return end
  Pokemon._front[EGG_SPECIES] = buildEggPic()
end

function Module.install(mod)
  local ModActions = {
    openSummary = function(game, mon)
      local gen = GameVersion.generation()
      if gen == 3 then
        local ok, SummaryMenu = pcall(require, "src.ui.game3.summary_menu")
        if ok and type(SummaryMenu) == "table" and SummaryMenu.openMenu then
          local shown = mon
          if type(mon) == "table" and (mon.isEgg == true or mon.egg == true) then
            shown = setmetatable({ species = EGG_SPECIES, speciesId = EGG_SPECIES, isEgg = true }, { __index = mon })
            local okPokemon, Pokemon = pcall(require, "src.core.game3.pokemon")
            if okPokemon and type(Pokemon) == "table" then pcall(ensureEggPic, Pokemon) end
          end
          local opened, err = pcall(SummaryMenu.openMenu, { shown }, 1, {})
          if not opened then mod.log:error("could not open the summary: %s", tostring(err)) end
        end
        return
      end
      local Screens = require("src.ui.Screens")
      if gen == 2 then
        Screens.push(game, "Gen2SummaryMenu", { mon = mon, onClose = function() game.stack:pop() end })
        return
      end
      Screens.push(game, "SummaryMenu", mon)
    end,
    makeTabToggle = function(optionKey)
      local enabledByOthers = true
      return {
        enabled = function() return enabledByOthers and mod.options:get(optionKey) == true end,
        setEnabled = function(value)
          enabledByOthers = value ~= false
          return true
        end
      }
    end
  }
  return ModActions
end

return Module
