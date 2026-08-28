local V = ...

local GameVersion = require("src.core.GameVersion")
local SPECIES = {
  { "MR_MIME", "MR__MIME" },
  { "FARFETCHD", "FARFETCH_D" },
}
local ITEMS = {
  { "THUNDER_STONE", "THUNDERSTONE" },
}
local MOVES = {}

local function translate(groups, id, targetGen)
  targetGen = targetGen or GameVersion.generation()
  for _, group in ipairs(groups) do
    for _, value in ipairs(group) do
      if value == id then return group[targetGen] or id end
    end
  end
  return id
end

local GenerationMap = {}

function GenerationMap.translateSpeciesId(id, targetGen) return translate(SPECIES, id, targetGen) end

function GenerationMap.translateItemId(id, targetGen) return translate(ITEMS, id, targetGen) end

function GenerationMap.translateMoveId(id, targetGen) return translate(MOVES, id, targetGen) end

return GenerationMap
