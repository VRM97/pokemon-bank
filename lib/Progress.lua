-- Story progress read off each generation's own flags, for entry.isUnlocked (Storage.lua).
local GameVersion = require("src.core.GameVersion")

local Progress = {}

local function gen2Event(game, id)
  local events = game and game.world and game.world.events
  if type(events) == "table" and type(events.get) == "function" then return events:get(id) == true end
  local bytes = game and type(game.save) == "table" and game.save.events
  if type(bytes) ~= "table" then return false end
  local byte = tonumber(bytes[math.floor(id / 8)]) or 0
  return math.floor(byte / 2 ^ (id % 8)) % 2 == 1
end

local function gen2EngineFlag(game, id)
  local flags = game and type(game.save) == "table" and game.save.engineFlags
  return type(flags) == "table" and flags[id] == true
end

local function gen1Event(game, name)
  local flags = game and type(game.save) == "table" and game.save.flags
  return type(flags) == "table" and flags[name] == true
end

local function gen3Flag(id)
  local okSpace, Space = pcall(require, "src.core.game3.scripting.space")
  local okFlags, Flags = pcall(require, "src.core.game3.scripting.flags")
  if not (okSpace and okFlags and type(Space) == "table" and type(Flags) == "table") then return false end
  return Flags.getFlag(Space.store, nil, id) == true
end

local function check(game, flags)
  local generation = GameVersion.generation()
  if generation == 1 then return gen1Event(game, flags[1]) end
  if generation == 2 then
    local g2 = flags[2]
    if g2.engine then return gen2EngineFlag(game, g2.engine) end
    return gen2Event(game, g2.event)
  end
  if generation == 3 then return gen3Flag(flags[3]) end
  return false
end

function Progress.gotPokedex(game)
  return check(game, {
    "EVENT_GOT_POKEDEX",
    { engine = 11 },
    0x829
  })
end

function Progress.gotCoinCase(game)
  return check(game, {
    "EVENT_GOT_COIN_CASE",
    { event = 1650 },
    0x243,
  })
end

return Progress
