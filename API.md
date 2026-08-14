# Pokémon Bank API

```lua
local bank = mod.find("vrm_pokemon_bank")
if bank then
  local boxNum, slot = bank.exports.depositPokemon(mon, { game = game })
  local mon2 = bank.exports.withdrawPokemon(boxNum, slot, game)
end
```

`mod.find` returns `nil` when Pokémon Bank isn't installed or is disabled -- always check the handle before calling into `.exports`. Nothing here depends on any particular save/version being active; the Bank's storage is shared across all of them (see README.md's **Where the data lives**).

## Box numbering: read this before storing a `{ box, index }` pair

A box's **number is a snapshot, not a stable id**. Boxes hold no gaps: the instant a box empties out (its last Pokémon withdrawn, released, or moved away), that box is deleted outright rather than kept as a hole, and every later box's number shifts down by one to fill the space. `boxCount()` is always `(occupied boxes) + 1` -- the `+1` is the one spare empty box every call that can grow the Bank (`depositPokemon`, `movePokemon`) is
guaranteed to find room in.

Practically: don't cache a `{ box, index }` pair across a turn boundary, an event, or any other mod's own deposit/withdraw and expect it to still point at the same Pokémon -- re-resolve it from `listPokemon()` first, or call `getPokemon(box, index)` and compare against what you expect to find there before acting on it (`withdrawPokemon`/`releasePokemon` on a stale pair just does nothing useful -- whatever is actually sitting in that slot by then). This mod's own UI follows the same rule internally.

## Pokémon

- `depositPokemon(mon, opts)` -- `opts.game`, if given, freezes the mon's stats block before storage. There is no box limit. Returns `boxNum, slotIndex`, or `nil, "invalid pokemon"` for a malformed `mon`.
- `depositPartyPokemon(game, opts)` -- bulk deposit from the player's party to the Bank. `game` is required. `opts.boxNum` specifies the target Bank box (defaults to the last box, which is always empty). `opts.indices` is an array of party indices to deposit (defaults to `2..last`, keeping the first Pokémon). Returns an array of `{ box, index, mon }` for each deposited mon, or `nil, "error message"`. Ensures at least one Pokémon remains in the party. When a box fills, remaining mons continue to the next box.
- `depositBoxPokemon(game, pcBoxNum, opts)` -- bulk deposit from a PC box to the Bank. `game` is required. `pcBoxNum` is the source PC box number (1-12). `opts.boxNum` specifies the target Bank box (defaults to the last box). `opts.indices` is an array of PC box slot indices to deposit (defaults to all). Returns an array of `{ box, index, mon }` for each deposited mon, or `nil, "error message"`. When a box fills, remaining mons continue to the next box.
- `withdrawPokemon(boxNum, index, game)` -- removes and returns the mon table, or `nil` if that slot is empty (see box-numbering caveat above). `game` is optional but strongly recommended: when given, catches the mon in the Pokédex (`seen` + `owned`/`caught`) if it wasn't already -- withdrawing is the only Bank action that can land a mon somewhere new (the party or a PC box), so it's the one that can introduce a species the Pokédex hasn't recorded yet. Without `game`, the withdrawal still happens; only the Pokédex write is skipped.
- `withdrawToParty(game, opts)` -- bulk withdraw from the Bank to the player's party. `game` is required. `opts.boxNum` specifies the source Bank box (defaults to the first non-empty box). `opts.indices` is an array of Bank slot indices to withdraw (defaults to all). Returns `{ withdrawn = [array of { mon }], remaining = count }`, or `nil, "error message"`. Withdraws up to the party's capacity (6 total); any remaining mons stay in the Bank.
- `withdrawToBox(game, targetPcBoxNum, opts)` -- bulk withdraw from the Bank to a PC box. `game` is required. `targetPcBoxNum` is the destination PC box number (1-12). `opts.boxNum` specifies the source Bank box (defaults to the first non-empty box). `opts.indices` is an array of Bank slot indices to withdraw (defaults to all). Returns `{ withdrawn = [array of { mon, pcBox }], remaining = count }`, or `nil, "error message"`. Fills the target box first, then overflows to subsequent PC boxes. If all PC boxes are full, remaining mons stay in the Bank.
- `getPokemon(boxNum, index)` -- read-only peek; does not remove.
- `getBox(boxNum)` -- a snapshot copy of one box's slots, indexed `1..boxCapacity()` (`nil` for an empty slot), for a mod that wants to render the Bank as a grid instead of walking `listPokemon()` itself. A copy, not a live reference -- mutating it does nothing to the Bank; call it again after any mutation to see the result. `nil` for a `boxNum` outside `1..boxCount()`.
- `movePokemon(srcBox, srcIdx, destBox, destIdx)` -- relocates within the Bank; landing on an occupied slot swaps the two, landing on an empty slot appends to the destination box (same "all empty grid cells are equivalent, boxes are dense arrays" convention the vanilla PC uses). Returns `true`, or `false` (`"full"` if the 20-slot destination box is at capacity).
- `releasePokemon(boxNum, index)` -- removes it for good; returns whether anything was actually there to remove. No confirmation -- this mod's own UI asks first, but the exported call does not.
- `listPokemon()` -- every stored mon, as a flat array of `{ box, index, mon }`.
- `pokemonCount()` -- total Pokémon across every box.
- `isValidPokemon(mon, game)` -- `true` when `mon.species` exists in `game.data.pokemon` and every move id in `mon.moves` exists in `game.data.moves`. Exported so other mods can reuse the same rule before depositing or when building their own Bank UI.
- `validatePokemonStorage(game)` -- scans `boxes` and `orphaned.mons` bidirectionally: invalid mons in `boxes` move to `orphaned.mons`, mons in `orphaned.mons` that are now valid append to the last box in `boxes`. Returns `{ changed, quarantined, restored, lostMons, restoredMons }`. Does not mark the Bank dirty itself -- call `validateStorage` (below) if you want the combined pass plus dirty handling.
- `listInvalidPokemon()` -- every quarantined mon as `{ index, mon }` (a copy of the list; mutating it does nothing to the Bank).
- `invalidPokemonCount()` -- how many mons are in `orphaned.mons`.
- `boxCount()` -- see **Box numbering** above.
- `boxCapacity()` -- slots per box.
- `reshapeForActiveGame(game, mon)` -- the cross-generation backfill this mod's own `withdrawPokemon`/`withdrawToParty`/`withdrawToBox` already run before a mon leaves the Bank: mirrors `exp`/`experience`, translates `status` between Gen 1 and Gen 2 (Gen 2's `toxic` degrades to plain `PSN` on Gen 1, which has no separate badly-poisoned status; the Gen 2-only `statusTurns`/`toxicCounter` are dropped when heading to Gen 1), mirrors CRYSTAL_251's `heldItem`/Gold's `item`, mirrors Egg incubation/moves, reshapes `moves[i].ppUps`/`maxPp` (see `reshapeMoves` below), and splits/recomputes `stats.specialAttack`/`specialDefense`, backfills `maxHp`/`types`/`catchRate` from `game.data.pokemon`, and rolls a `gender` from the Attack DV/`genderRatio` rule when the mon doesn't have one yet (a Gen 1 mon never does). Mutates and returns `mon`. For a mod that moves a Pokémon between generations on its own path (bypassing this mod's withdraw calls entirely), calling this first gets the same treatment instead of reimplementing it.
- `reshapeMoves(game, mon)` -- just the move-PP piece of the above, in case a mod only needs that: Gen 1 keeps a move's bonus PP on `ppUps` and recomputes the cap on every read, Gen 2 stores the raised cap directly on `maxPp` and keeps no `ppUps` counter; this fills in whichever field the active generation expects from whichever one the mon already carries. Mutates `mon.moves` in place; returns nothing.
- `reshapeStatus(mon)` -- just the status piece of the above, in case a mod only needs that: translates `mon.status` between Gen 1's `SLP`/`PSN`/`BRN`/`FRZ`/`PAR` and Gen 2's `sleep`/`poison`/`burn`/`freeze`/`paralyze` (Gen 2's `toxic` degrades to plain `PSN` on Gen 1; the Gen 2-only `statusTurns`/`toxicCounter` are dropped when heading to Gen 1). Takes no `game` -- it only needs `GameVersion.generation()`. A no-op when `mon.status` is already `nil`. Mutates `mon` in place; returns nothing.
- `healBank(game)` -- heals every Pokémon currently stored in the Bank in place: full HP, status cleared, every move's PP restored to its current-generation cap. `game` is required. Returns how many mons were healed; marks the Bank dirty when it healed at least one. This is what the **AUTO HEAL** option's **AT POKéMON CENTER** choice calls.

## Items

- `depositItem(id, qty, game)` -- `game` is optional but strongly recommended: without it, only the `HM_` id prefix and anything added through `blacklistItem` are checked -- no `game.data.items` lookup means the key-item flag can't be (Gen 1's `def.keyItem` or Gen 2's `def.pocket == "KEY_ITEM"`). Returns `true`, or `false, "blacklisted"/"bad request"`.
- `withdrawItem(id, qty)` -- decrements the Bank's own count only. Does **not** touch any bag -- add it to whatever inventory you mean with your own `Bag.add` first (check its return value before calling this, so a failed add doesn't still remove the item from the Bank -- mirrors what this mod's own UI does).
- `tossItem(id, qty)` -- same effect as `withdrawItem` (decrements the Bank's own count), for when the item is meant to just disappear rather than land in a bag -- fires `item_tossed` instead of `item_withdrawn` so a listener can tell the two apart. Returns `true`, or `false, "not enough"`.
- `itemCount(id)`
- `listItems()` -- a plain `{ id = count }` table (a copy; mutating it does nothing to the Bank).
- `isValidItem(id, game)` -- `true` when `id` is a non-empty string present in `game.data.items`. Exported for other mods.
- `validateItemsStorage(game)` -- scans `items` and `orphaned.items` bidirectionally: unknown ids *and* blacklisted ones (`isBlacklisted`, i.e. an HM/key item) move to `orphaned.items`; ids in `orphaned.items` merge back into `items` only if they're both known and not blacklisted -- a quarantined HM/key item stays quarantined even after it becomes otherwise valid. Returns `{ changed, quarantined, restored, lostItems, restoredItems }` (counts are total item quantities, not distinct ids).
- `listInvalidItems()` -- a plain `{ id = count }` copy of the quarantined stacks.
- `invalidItemCount(id)` -- total quarantined quantity for one id, or across every id when `id` is omitted.
- `isBlacklisted(id, game)` -- true for HMs, key items (needs `game` to check Gen 1's `keyItem` flag or Gen 2's `pocket == "KEY_ITEM"`), and anything added through `blacklistItem`.
- `blacklistItem(id)` -- adds `id` to the Bank's deposit blacklist, on top of the built-in HM/key-item rule. Additive only -- there is no way to lift the built-in rule for either. Lives only in memory: a mod that needs an id blacklisted calls this itself, every load (matches how `mod.options`/manifest declarations already work -- nothing here is a one-time registration that outlives the calling mod being loaded).

## Money

Same asymmetry as `depositItem`/`withdrawItem`: these only change the Bank's own balance. Neither touches the save's own wallet (`game.save.money` on Gen1, `game.save.player.money` on Gen2) -- debit/credit whatever wallet you mean yourself (mirrors what this mod's own DEPOSIT MONEY/WITHDRAW MONEY do, which already branch on `GameVersion.generation()` to hit the right field).

- `bankMoney()` -- the Bank's own money balance, independent of any save's wallet.
- `depositMoney(amount)` -- adds `amount` to the Bank's balance. Returns `true`, or `false, "bad request"` for an `amount <= 0`.
- `withdrawMoney(amount)` -- subtracts `amount` from the Bank's balance. Returns `true`, or `false, "not enough"` for an `amount <= 0` or greater than `bankMoney()`.
- `maxMoney` -- `999999`, the game's own money cap. Not enforced by `depositMoney`/`withdrawMoney` themselves (the Bank's own balance is a plain number, uncapped) -- only relevant if you're about to add the withdrawn amount to the save's wallet, the same way this mod's own WITHDRAW MONEY caps itself against it first.

## Persistence

Every export above that mutates the Bank (`depositPokemon`, `withdrawPokemon`, `movePokemon`, `releasePokemon`, `depositItem`, `withdrawItem`, `depositMoney`, `withdrawMoney`) only changes the in-memory copy -- the actual write to `storage.lua` is deferred to line up with the game's own save (a `save.write` hook), not flushed immediately. This is deliberate: see README.md's **Where the data lives** for why an immediate write would let a reset-without-saving duplicate whatever was just deposited. Nothing to do differently here -- just don't assume a mutation is durable the instant the call returns.

On every `save.loaded`, this mod runs `validateStorage(game)` automatically (Pokémon + items) and shows a summary text box when anything moved. Other mods can call the validation exports directly at any time.

`storage.lua` is **version 3**: `{ version, boxes, currentBox, items, money, ophaned = { mons, items } }`. Loading a lower version file migrates it and marks the Bank dirty so the upgraded shape is written on the next save.

- `validateStorage(game)` -- the combined pass this mod runs on load: calls `validatePokemonStorage` and `validateItemsStorage`, marks the Bank dirty when either reports `changed`, returns `{ changed, pokemon, items, message }` (`message` is a player-facing summary string, or `nil` when nothing moved).
- `flush()` -- forces the pending write immediately instead of waiting for the next save. Returns whether anything was actually pending. Normally unnecessary; reach for it only when a mod has its own reason a Bank change must be durable before the game's own save point (e.g. right before code that risks the process, like a native file-picker call).

## PC menu entry

Pokémon Bank adds a **POKéMON BANK** row to the PC's own main menu (the one offering BILL's PC / Player's PC / PROF.OAK's PC / LOG OFF) through the `ui.pc.items` hook. Two independent ways to control it:

- `setPcEntryEnabled(enabled)` -- pass `false` to hide the row outright regardless of the player's own **SHOW IN PC MENU** option, `true` (or call again) to restore it. Meant for a mod that replaces the PC flow entirely and wants to fold the Bank's entry point into its own UI instead of showing both.
- `pcMenuLabel` -- the exact row label (`"POKéMON BANK"`), for a mod that would rather remove it itself with `mod.ui.removeLabel` inside its own `ui.pc.items` hook (registered with a higher `priority` than this mod's manifest `priority`, so it runs after -- see the engine's decorate-after-`next` hook convention). `setPcEntryEnabled` above is the simpler option for most cases; this is for a mod that wants to make that decision per-call (e.g. only inside its own replacement PC screen) rather than as a standing on/off switch.
- `setPokemonTabEnabled(enabled)` / `setItemsTabEnabled(enabled)` / `setMoneyTabEnabled(enabled)` -- same idea as `setPcEntryEnabled`, one level down: hide (`false`) or restore (`true`, or call again) just the POKéMON, ITEMS or MONEY side, independent of the player's own **POKéMON MENU** / **ITEMS MENU** / **MONEY MENU** options (each combines the same way `setPcEntryEnabled` and **SHOW IN PC MENU** already do -- both the option and the API flag have to allow a tab for it to show). With only one tab enabled (by either mechanism), the **POKéMON BANK** row skips the chooser and opens that tab directly; with none enabled, the row doesn't appear at all. Doesn't affect `open(game, tab)`, `pokemonScreenId`, `itemsScreenId` or `moneyScreenId` below -- those stay reachable regardless, the same way `open` already bypasses **SHOW IN PC MENU**/`setPcEntryEnabled`.
- `isPcEntryEnabled()` / `isPokemonTabEnabled()` / `isItemsTabEnabled()` / `isMoneyTabEnabled()` -- the read side of the four setters above. The player's own **SHOW IN PC MENU** / **POKéMON MENU** / **ITEMS MENU** / **MONEY MENU** options live inside this mod's `mod.options`, which `mod.find()` does not expose (it only hands back `{ id, version, exports }`) -- these are the only way for another mod to know whether a side is actually visible right now. Each returns the already-combined result (the player's option **and** whatever any mod's setter above last chose), the same value the **POKéMON BANK** PC row itself decides with.

## UI

- `open(game, tab)` -- pushes the Bank UI directly, no PC required; `tab` is `"pokemon"` (default), `"items"` or `"money"`. Returns whatever `mod.ui.push` returns, or `nil, "no game"` without one.
- `pokemonScreenId`, `itemsScreenId`, `moneyScreenId` -- the registered screen ids (`mod.content.screens`) backing the three tabs, for a mod that wants to push them through its own navigation instead of `open`.

## Events

Every deposit, withdraw, release and item/money transfer -- through this mod's own UI or through the exports above -- fires one of:

- `mod.vrm_pokemon_bank.pokemon_deposited` -- `{ box, index, mon }`
- `mod.vrm_pokemon_bank.pokemon_withdrawn` -- `{ box, index, mon }`
- `mod.vrm_pokemon_bank.pokemon_released` -- `{ box, index, mon }`
- `mod.vrm_pokemon_bank.item_deposited` -- `{ id, qty }`
- `mod.vrm_pokemon_bank.item_withdrawn` -- `{ id, qty }`
- `mod.vrm_pokemon_bank.item_tossed` -- `{ id, qty }`
- `mod.vrm_pokemon_bank.money_deposited` -- `{ amount }`
- `mod.vrm_pokemon_bank.money_withdrawn` -- `{ amount }`

`mod.events:on("mod.vrm_pokemon_bank.pokemon_deposited", function(payload) ... end)` subscribes the usual way. Remember `box`/`index` in a payload are only a snapshot -- see **Box numbering** above.
