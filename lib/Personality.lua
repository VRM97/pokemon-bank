local Personality = {}

local bit = rawget(_G, "bit")

local function bxor(a, b)
  if bit then return bit.bxor(a, b) % 4294967296 end
  local r, p = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end

local function random16() return love.math.random(0, 65535) end

function Personality.nature(pid) return pid % 25 end

function Personality.abilitySlot(pid) return pid % 2 end

function Personality.gender(pid, ratio)
  if ratio == nil or ratio >= 255 then return nil end
  if ratio == 0 then return "male" end
  if ratio == 254 then return "female" end
  return (pid % 256) < ratio and "female" or "male"
end

function Personality.unownForm(pid)
  local function twoBits(shift) return math.floor(pid / 2 ^ shift) % 4 end
  return (twoBits(24) * 64 + twoBits(16) * 16 + twoBits(8) * 4 + twoBits(0)) % 28
end

local function setTwoBits(x, shift, value) return math.floor(x + (value - math.floor(x / 2 ^ shift) % 4) * 2 ^ shift) end

function Personality.isShiny(pid, tid, sid)
  local trainer = bxor(tid % 65536, sid % 65536)
  local pidXor = bxor(math.floor(pid / 65536), pid % 65536)
  return bxor(trainer, pidXor) < 8
end

local TWO32 = 4294967296
local LCG_MUL, LCG_ADD, LCG_INV = 0x41C64E6D, 0x6073, 0xEEB9EB65

local function mul32(a, b)
  local hi, lo = math.floor(a / 65536), a % 65536
  return ((hi * b) % 65536 * 65536 + lo * b) % TWO32
end

local function advance(seed) return (mul32(seed, LCG_MUL) + LCG_ADD) % TWO32 end

local function rewind(seed) return mul32((seed - LCG_ADD) % TWO32, LCG_INV) end

local function shiftRight(value, bits) return math.floor(value / 2 ^ bits) end

local function clampIV(v) return math.max(0, math.min(31, math.floor(tonumber(v) or 0))) end

local function ivWords(ivs)
  return clampIV(ivs.hp) + clampIV(ivs.atk) * 32 + clampIV(ivs.def) * 1024,
    clampIV(ivs.spe) + clampIV(ivs.spa) * 32 + clampIV(ivs.spd) * 1024
end

local function seedsBeforeIVs(first, second)
  local LAG0, LAG1, LOWER, UPPER = 0x67D3, 0xC907, 0x3443, 0xC34E
  local tmp = shiftRight((second - mul32(LCG_MUL, first)) % TWO32, 16) * LAG1 % TWO32
  local lo = mul32(shiftRight((tmp + LOWER) % TWO32, 15), LAG0)
  local mid = (lo + LAG0) % TWO32
  local up = mul32(shiftRight((tmp + UPPER) % TWO32, 15), LAG0)
  local seeds = {}
  local function add(low)
    low = low % LAG1
    repeat
      local seed = first + low
      if shiftRight(advance(seed), 16) % 32768 * 65536 == second then
        seed = rewind(seed)
        seeds[#seeds + 1] = seed
        seeds[#seeds + 1] = (seed + 0x80000000) % TWO32
      end
      low = low + LAG1
    until low >= 0x10000
  end
  add(lo)
  add(mid)
  if mid ~= up then add(up) end
  return seeds
end

local function seedsBeforeSkippedIVs(first, third)
  local RMULT2, LAG0, LAG1_IVS, LOWER, UPPER = 0xDC6C95D9, 0x6C31, 0x2E90, 0x1574621D, 0x157488D6
  local tmp = shiftRight((first - mul32(third, RMULT2)) % TWO32, 16) * LAG0 % TWO32
  local lo, up = shiftRight((tmp + LOWER) % TWO32, 15), shiftRight((tmp + UPPER) % TWO32, 15)
  local seeds = {}
  local function add(low)
    repeat
      local seed = rewind(rewind(third + low))
      if shiftRight(seed, 16) % 32768 * 65536 == first then
        seed = rewind(seed)
        seeds[#seeds + 1] = seed
        seeds[#seeds + 1] = (seed + 0x80000000) % TWO32
      end
      low = low + LAG0
    until low >= 0x10000
  end
  add(mul32(lo, LAG1_IVS) % LAG0)
  if lo ~= up then add(mul32(up, LAG1_IVS) % LAG0) end
  return seeds
end

local function sequentialPID(origin)
  local afterLow = advance(origin)
  return shiftRight(advance(afterLow), 16) * 65536 + shiftRight(afterLow, 16)
end

function Personality.candidatesFromIVs(ivs)
  local word1, word2 = ivWords(ivs)
  local first, second = word1 * 65536, word2 * 65536
  local out = {}
  for _, before in ipairs(seedsBeforeIVs(first, second)) do
    out[#out + 1] = { pid = sequentialPID(rewind(rewind(before))), method = 1 }
    out[#out + 1] = { pid = sequentialPID(rewind(rewind(rewind(before)))), method = 2 }
  end
  for _, before in ipairs(seedsBeforeSkippedIVs(first, second)) do
    out[#out + 1] = { pid = sequentialPID(rewind(rewind(before))), method = 4 }
  end
  return out
end

function Personality.fromIVs(ivs, accept, roll)
  roll = roll or random16
  local candidates = Personality.candidatesFromIVs(ivs)
  for i = #candidates, 2, -1 do
    local j = roll() % i + 1
    candidates[i], candidates[j] = candidates[j], candidates[i]
  end
  for _, candidate in ipairs(candidates) do
    if accept(candidate.pid) then return candidate.pid end
  end
  return nil
end

function Personality.matchesIVs(pid, ivs)
  for _, candidate in ipairs(Personality.candidatesFromIVs(ivs)) do
    if candidate.pid == pid then return true end
  end
  return false
end

function Personality.generate(opts)
  opts = opts or {}
  local roll = opts.random16 or random16
  local tid, sid = tonumber(opts.tid) or 0, tonumber(opts.sid) or 0
  local wantShiny = opts.shiny == true
  local form = opts.unownForm

  local function fits(pid)
    if pid == 0 then return false end
    local actual = Personality.gender(pid, opts.ratio)
    if opts.gender and actual ~= nil and actual ~= opts.gender then return false end
    if form and Personality.unownForm(pid) ~= form then return false end
    return not (opts.taken and opts.taken(pid))
  end

  local function formBits()
    local choices = {}
    for v = form, 255, 28 do choices[#choices + 1] = v end
    return choices[roll() % #choices + 1]
  end

  if opts.ivs and not wantShiny then
    local pid = Personality.fromIVs(opts.ivs, function(candidate)
      return not Personality.isShiny(candidate, tid, sid) and fits(candidate)
    end, roll)
    if pid then return pid end
  end

  local last
  for _ = 1, 4000 do
    local high, low = roll(), roll()
    local v = form and formBits()
    if v then
      high = setTwoBits(setTwoBits(high, 8, math.floor(v / 64) % 4), 0, math.floor(v / 16) % 4)
    end
    if wantShiny then
      local base = bxor(bxor(tid % 65536, sid % 65536), high)
      local start = roll() % 8
      for k = 0, 7 do
        local pid = high * 65536 + bxor(base, (start + k) % 8)
        last = pid
        if fits(pid) then return pid end
      end
    else
      if v then low = setTwoBits(setTwoBits(low, 8, math.floor(v / 4) % 4), 0, v % 4) end
      local pid = high * 65536 + low
      last = pid
      if not Personality.isShiny(pid, tid, sid) and fits(pid) then return pid end
    end
  end
  return last
end

return Personality
