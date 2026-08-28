local V = ...

local SCREEN_ID = "PokemonBankLost"

local Module = {}

function Module.install(mod, core)
  local function buildLostScreen(game)
    return core.lostBrowser(game, {
      screenId = SCREEN_ID,
      getMons = function()
        local mons = {}
        local entries = mod.exports.listInvalidPokemon and mod.exports.listInvalidPokemon() or {}
        for _, entry in ipairs(entries) do mons[#mons + 1] = entry.mon end
        local capsuleEntries = mod.exports.listInvalidTimeCapsulePokemon and mod.exports.listInvalidTimeCapsulePokemon() or {}
        for _, entry in ipairs(capsuleEntries) do mons[#mons + 1] = entry.mon end
        return mons
      end,
      getItems = function() return mod.exports.listInvalidItems and mod.exports.listInvalidItems() or {} end,
      getMoves = function() return mod.exports.listInvalidMoves and mod.exports.listInvalidMoves() or {} end,
    })
  end

  mod.content.screens:register(SCREEN_ID, { new = buildLostScreen })
  mod.exports.lostScreenId = SCREEN_ID
  mod.log:info("Pokemon Bank: Lost viewer ready")
  return { screenId = SCREEN_ID }
end

return Module
