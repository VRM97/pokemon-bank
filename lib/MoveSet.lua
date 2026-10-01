local V = ...

local GameVersion = require("src.core.GameVersion")
local GenerationMap = V.require("GenerationMap")

local MoveSet = {}

local function gen3Module(name)
  local ok, module = pcall(require, name)
  return ok and type(module) == "table" and module or nil
end

local function idOf(entry) return type(entry) == "table" and entry.id or entry end

function MoveSet.form(moves)
  if type(moves) ~= "table" then return nil end
  local first = moves[1]
  if type(first) == "number" then return "number" end
  if first ~= nil then return "table" end
  return nil
end

local function gen3Name(number)
  if GameVersion.generation() ~= 3 then return nil end
  local Compat = gen3Module("src.mods.Gen3Compat")
  local name = Compat and Compat.moveName and Compat.moveName(number)
  return type(name) == "string" and not tonumber(name) and name or nil
end

function MoveSet.gen3Known(number) return type(number) == "number" and number > 0 and gen3Name(number) ~= nil end

function MoveSet.toNumber(game, id)
  if type(id) ~= "string" or GameVersion.generation() ~= 3 then return nil end
  local Compat = gen3Module("src.mods.Gen3Compat")
  local n = Compat and Compat.moveId and Compat.moveId(GenerationMap.translateMoveId(id, 3))
  return type(n) == "number" and n > 0 and n or nil
end

function MoveSet.toText(game, number)
  if type(number) ~= "number" then return nil end
  local name = gen3Name(number)
  return name and GenerationMap.translateMoveId(name, 2) or nil
end

function MoveSet.basePp(game, id, number)
  local def = game and game.data and game.data.moves and game.data.moves[id]
  if def and tonumber(def.pp) then return tonumber(def.pp) end
  local M = number and gen3Module("src.core.game3.battle.moves")
  local row = M and M.get and M.get(number)
  return type(row) == "table" and tonumber(row.pp) or nil
end

local function ppStep(base) return base and math.floor(base / 5) or 0 end

local function ppOf(game, id, number, entry)
  local base = MoveSet.basePp(game, id, number)
  local step = ppStep(base)
  local ups = entry.ppUps or (entry.maxPp and base and step > 0 and math.max(0, math.min(3, math.floor((entry.maxPp - base) / step + 0.5)))) or 0
  local max = entry.maxPp or (base and base + ups * step) or entry.pp or 0
  return math.min(entry.pp or max, max), max, ups
end

function MoveSet.altIds(game, mon)
  local out = {}
  if MoveSet.form(mon.moves) == "table" then
    for i, entry in ipairs(mon.moves) do out[i] = MoveSet.toNumber(game, idOf(entry)) or false end
  else
    for i, n in ipairs(mon.moves) do out[i] = MoveSet.toText(game, n) or false end
  end
  return out
end

local function validAlt(mon, form)
  local alt = mon.movesAlt
  if type(alt) ~= "table" or #alt ~= #mon.moves then return false end
  local want = form == "table" and "number" or "string"
  for _, id in ipairs(alt) do
    if id ~= false and type(id) ~= want then return false end
  end
  return true
end

local function idsOf(moves)
  local out = {}
  for i, entry in ipairs(moves) do out[i] = idOf(entry) end
  return out
end

local function sameIds(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

function MoveSet.refresh(game, mon)
  if not MoveSet.form(mon.moves) then mon.movesAlt, mon.movesAltOf = nil, nil return false end
  mon.movesAlt, mon.movesAltOf = MoveSet.altIds(game, mon), idsOf(mon.moves)
  return true
end

function MoveSet.sync(game, mon)
  if type(mon) ~= "table" then return false end
  local form = MoveSet.form(mon.moves)
  if not form then
    local had = mon.movesAlt ~= nil
    mon.movesAlt, mon.movesAltOf = nil, nil
    return had
  end
  local current = idsOf(mon.moves)
  if mon.movesAlt ~= nil and mon.movesAltOf == nil and validAlt(mon, form) then
    mon.movesAltOf = current
    return true
  end
  if mon.movesAlt ~= nil and validAlt(mon, form) and sameIds(mon.movesAltOf, current) then return false end
  if GameVersion.generation() == 3 then return MoveSet.refresh(game, mon) end
  local had = mon.movesAlt ~= nil
  mon.movesAlt, mon.movesAltOf = nil, nil
  return had
end

function MoveSet.reshape(game, mon)
  local form = MoveSet.form(mon.moves)
  if not form then return {} end
  local wantNumber = GameVersion.generation() == 3
  if (form == "number") == wantNumber then return {} end
  MoveSet.sync(game, mon)
  if mon.movesAlt == nil then MoveSet.refresh(game, mon) end
  local alt, leftovers = mon.movesAlt, {}
  local moves, ids, pp, maxPp = {}, {}, {}, {}
  if wantNumber then
    for i, entry in ipairs(mon.moves) do
      local n = MoveSet.toNumber(game, idOf(entry)) or alt[i]
      if n and MoveSet.gen3Known(n) then
        local text = idOf(entry)
        local cur, max = ppOf(game, text, n, type(entry) == "table" and entry or {})
        moves[#moves + 1], ids[#ids + 1] = n, text
        pp[#pp + 1], maxPp[#maxPp + 1] = cur, max
      else leftovers[#leftovers + 1] = entry end
    end
    mon.moves, mon.pp, mon.maxPp, mon.movesAlt, mon.movesAltOf = moves, pp, maxPp, ids, idsOf(moves)
  else
    local movesData = game and game.data and game.data.moves
    for i, n in ipairs(mon.moves) do
      local text = alt[i] and GenerationMap.translateMoveId(alt[i], GameVersion.generation())
      if text and (not movesData or movesData[text] ~= nil) then
        local cur, max, ups = ppOf(game, text, n, { pp = mon.pp and mon.pp[i], maxPp = mon.maxPp and mon.maxPp[i] })
        moves[#moves + 1] = { id = text, pp = cur, ppUps = ups, maxPp = max }
        ids[#ids + 1] = n
      else leftovers[#leftovers + 1] = n end
    end
    mon.moves, mon.pp, mon.maxPp, mon.movesAlt, mon.movesAltOf = moves, nil, nil, ids, idsOf(moves)
  end
  return leftovers
end

return MoveSet
