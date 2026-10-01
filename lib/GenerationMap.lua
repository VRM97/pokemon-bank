local GameVersion = require("src.core.GameVersion")

local SPECIES = {
  { "MR_MIME", "MR__MIME", "MR_MIME" },
  { "FARFETCHD", "FARFETCH_D", "FARFETCHD" },
}

local ITEMS = {
  { "THUNDER_STONE", "THUNDERSTONE", "THUNDERSTONE" },
  { "ELIXER", "ELIXER", "ELIXIR" },
  { "MAX_ELIXER", "MAX_ELIXER", "MAX_ELIXIR" },
  { "BERRY", "BERRY", "ORAN_BERRY" },
  { "GOLD_BERRY", "GOLD_BERRY", "SITRUS_BERRY" },
  { "PSNCUREBERRY", "PSNCUREBERRY", "PECHA_BERRY" },
  { "PRZCUREBERRY", "PRZCUREBERRY", "CHERI_BERRY" },
  { "BURNT_BERRY", "BURNT_BERRY", "ASPEAR_BERRY" },
  { "ICE_BERRY", "ICE_BERRY", "RAWST_BERRY" },
  { "BITTER_BERRY", "BITTER_BERRY", "PERSIM_BERRY" },
  { "MINT_BERRY", "MINT_BERRY", "CHESTO_BERRY" },
  { "MIRACLEBERRY", "MIRACLEBERRY", "LUM_BERRY" },
  { "MYSTERYBERRY", "MYSTERYBERRY", "LEPPA_BERRY" },
  { "BLACKBELT_I", "BLACKBELT_I", "BLACK_BELT" },
  { "TM_G3_AERIAL_ACE", "TM_G3_AERIAL_ACE", 328 },
  { "TM_G3_ATTRACT", "TM_ATTRACT", 333 },
  { "TM_BLIZZARD", "TM_BLIZZARD", 302 },
  { "TM_G3_BRICK_BREAK", "TM_G3_BRICK_BREAK", 319 },
  { "TM_G3_BULK_UP", "TM_G3_BULK_UP", 296 },
  { "TM_G3_BULLET_SEED", "TM_G3_BULLET_SEED", 297 },
  { "TM_G3_CALM_MIND", "TM_G3_CALM_MIND", 292 },
  { "TM_DIG", "TM_DIG", 316 },
  { "TM_DOUBLE_TEAM", "TM_DOUBLE_TEAM", 320 },
  { "TM_G3_DRAGON_CLAW", "TM_G3_DRAGON_CLAW", 290 },
  { "TM_DREAM_EATER", "TM_DREAM_EATER", nil },
  { "TM_EARTHQUAKE", "TM_EARTHQUAKE", 314 },
  { "TM_G3_FACADE", "TM_G3_FACADE", 330 },
  { "TM_FIRE_BLAST", "TM_FIRE_BLAST", 326 },
  { "TM_G3_FLAMETHROWER", "TM_G3_FLAMETHROWER", 323 },
  { "TM_G3_FOCUS_PUNCH", "TM_G3_FOCUS_PUNCH", 289 },
  { "TM_G3_FRUSTRATION", "TM_FRUSTRATION", 309 },
  { "TM_G3_GIGA_DRAIN", "TM_GIGA_DRAIN", 307 },
  { "TM_G3_HAIL", "TM_G3_HAIL", 295 },
  { "TM_G3_HIDDEN_POWER", "TM_HIDDEN_POWER", 298 },
  { "TM_HYPER_BEAM", "TM_HYPER_BEAM", 303 },
  { "TM_ICE_BEAM", "TM_G3_ICE_BEAM", 301 },
  { "TM_G3_IRON_TAIL", "TM_IRON_TAIL", 311 },
  { "TM_G3_LIGHT_SCREEN", "TM_G3_LIGHT_SCREEN", 304 },
  { "TM_G3_OVERHEAT", "TM_G3_OVERHEAT", 338 },
  { "TM_G3_PROTECT", "TM_PROTECT", 305 },
  { "TM_PSYCHIC_M", "TM_PSYCHIC_M", 317 },
  { "TM_G3_RAIN_DANCE", "TM_RAIN_DANCE", 306 },
  { "TM_REFLECT", "TM_G3_REFLECT", 321 },
  { "TM_REST", "TM_REST", 332 },
  { "TM_G3_RETURN", "TM_RETURN", 315 },
  { "TM_G3_ROAR", "TM_ROAR", 293 },
  { nil, "TM_ROCK_SMASH", nil },
  { "TM_G3_ROCK_TOMB", "TM_G3_ROCK_TOMB", 327 },
  { "TM_G3_SAFEGUARD", "TM_G3_SAFEGUARD", 308 },
  { "TM_G3_SANDSTORM", "TM_SANDSTORM", 325 },
  { "TM_G3_SECRET_POWER", "TM_G3_SECRET_POWER", 331 },
  { "TM_G3_SHADOW_BALL", "TM_SHADOW_BALL", 318 },
  { "TM_G3_SHOCK_WAVE", "TM_G3_SHOCK_WAVE", 322 },
  { "TM_G3_SKILL_SWAP", "TM_G3_SKILL_SWAP", 336 },
  { "TM_G3_SLUDGE_BOMB", "TM_SLUDGE_BOMB", 324 },
  { "TM_G3_SNATCH", "TM_G3_SNATCH", 337 },
  { "TM_SOLARBEAM", "TM_SOLARBEAM", 310 },
  { "TM_G3_STEEL_WING", "TM_STEEL_WING", 335 },
  { "TM_G3_SUNNY_DAY", "TM_SUNNY_DAY", 299 },
  { "TM_SWIFT", "TM_SWIFT", nil },
  { "TM_G3_TAUNT", "TM_G3_TAUNT", 300 },
  { "TM_G3_THIEF", "TM_THIEF", 334 },
  { "TM_THUNDER", "TM_THUNDER", 313 },
  { "TM_THUNDERBOLT", "TM_G3_THUNDERBOLT", 312 },
  { "TM_G3_TORMENT", "TM_G3_TORMENT", 329 },
  { "TM_TOXIC", "TM_TOXIC", 294 },
  { "TM_G3_WATER_PULSE", "TM_G3_WATER_PULSE", 291 },
}

local MOVES = {
  { "PSYCHIC_M", "PSYCHIC_M", "PSYCHIC" },
  { "CONVERSION_2", "CONVERSION2", "CONVERSION_2" },
  { "DRAGON_BREATH", "DRAGONBREATH", "DRAGONBREATH" },
  { "ANCIENT_POWER", "ANCIENTPOWER", "ANCIENTPOWER" },
  { "DYNAMIC_PUNCH", "DYNAMICPUNCH", "DYNAMICPUNCH" },
  { "EXTREME_SPEED", "EXTREMESPEED", "EXTREMESPEED" },
  { "FEINT_ATTACK", "FAINT_ATTACK", "FAINT_ATTACK" },
  { "FEATHER_DANCE", "FEATHER_DANCE", "FEATHERDANCE" },
  { "GRASS_WHISTLE", "GRASS_WHISTLE", "GRASSWHISTLE" },
  { "SMELLING_SALTS", "SMELLING_SALTS", "SMELLINGSALT" },
}

local MAX_SLOTS = 9

local function translate(groups, id, targetGen)
  targetGen = targetGen or GameVersion.generation()
  for _, group in ipairs(groups) do
    for slot = 1, MAX_SLOTS do
      if group[slot] ~= nil and group[slot] == id then return group[targetGen] or id end
    end
  end
  return id
end

local GenerationMap = { groups = { species = SPECIES, items = ITEMS, moves = MOVES } }

function GenerationMap.translateSpeciesId(id, targetGen) return translate(SPECIES, id, targetGen) end

function GenerationMap.translateItemId(id, targetGen) return translate(ITEMS, id, targetGen) end

function GenerationMap.translateMoveId(id, targetGen) return translate(MOVES, id, targetGen) end

return GenerationMap
