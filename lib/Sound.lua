local V = ...

local GameVersion = require("src.core.GameVersion")

local Sound = {}

function Sound.playSound(game, name)
  pcall(function() require("src.core.Sound").play(game.data, name) end)
end

function Sound.playSaveSound(game)
  Sound.playSound(game, GameVersion.generation() == 2 and "Sfx_Save" or "Save")
end

function Sound.playCry(game, species)
  pcall(function() require("src.core.Sound").playCry(game.data, species) end)
end

return Sound
