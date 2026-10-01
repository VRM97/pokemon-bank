local StatsValues = {}

local MAX_DV, MAX_IV = 15, 31
local MAX_STAT_EXP, MAX_EV = 65535, 255

local function clamp(value, max, min)
  value = tonumber(value) or 0
  return math.max(min or 0, math.min(max, math.floor(value + 0.5)))
end

local function fromDV(dv) return clamp(dv, MAX_DV) * 2 + 1 end

local function toDV(iv) return math.floor(clamp(iv, MAX_IV) / 2) end

local function fromStatExp(value) return math.floor(clamp(value, MAX_STAT_EXP) / 256) end

local function toStatExp(ev) return clamp(ev, MAX_EV) * 256 + 255 end

local function specialDV(dvs) return dvs.special or dvs.specialAttack or dvs.specialDefense end

function StatsValues.hpDV(attack, defense, speed, special) return (attack % 2) * 8 + (defense % 2) * 4 + (speed % 2) * 2 + (special % 2) end

function StatsValues.fromDVs(dvs)
  local atk, def, spe = clamp(dvs.attack, MAX_DV), clamp(dvs.defense, MAX_DV), clamp(dvs.speed, MAX_DV)
  local spc = clamp(specialDV(dvs), MAX_DV)
  local hp = dvs.hp ~= nil and clamp(dvs.hp, MAX_DV) or StatsValues.hpDV(atk, def, spe, spc)
  local spa = dvs.specialAttack ~= nil and clamp(dvs.specialAttack, MAX_DV) or spc
  local spd = dvs.specialDefense ~= nil and clamp(dvs.specialDefense, MAX_DV) or spc
  return {
    hp = fromDV(hp),
    atk = fromDV(atk),
    def = fromDV(def),
    spa = fromDV(spa),
    spd = fromDV(spd),
    spe = fromDV(spe),
  }
end

function StatsValues.toDVs(ivs)
  local attack, defense, speed, special = toDV(ivs.atk), toDV(ivs.def), toDV(ivs.spe), toDV(ivs.spa)
  return {
    hp = StatsValues.hpDV(attack, defense, speed, special),
    attack = attack,
    defense = defense,
    special = special,
    speed = speed,
  }
end

function StatsValues.fromStatExp(statExp)
  local special = statExp.special or statExp.specialAttack or statExp.specialDefense
  return {
    hp = fromStatExp(statExp.hp),
    atk = fromStatExp(statExp.attack),
    def = fromStatExp(statExp.defense),
    spa = fromStatExp(statExp.specialAttack or special),
    spd = fromStatExp(statExp.specialDefense or special),
    spe = fromStatExp(statExp.speed),
  }
end

function StatsValues.toStatExp(evs)
  return {
    hp = toStatExp(evs.hp),
    attack = toStatExp(evs.atk),
    defense = toStatExp(evs.def),
    special = toStatExp(evs.spa),
    speed = toStatExp(evs.spe),
  }
end

return StatsValues
