# Changelog

## 1.2.0

- New **SHOW POKéMON** / **SHOW ITEMS** options (both on by default) let each side of the Bank be turned off independently, and the new exported `setPokemonTabEnabled(enabled)` / `setItemsTabEnabled(enabled)` let another mod do the same on top of them. With only one side enabled, the **POKéMON BANK** PC row skips the POKéMON/ITEMS chooser and opens that side directly; with neither enabled, the row doesn't appear at all (mirrors how **SHOW IN PC MENU** / `setPcEntryEnabled` already hide the whole row). `open(game, tab)` and the registered screen ids are unaffected -- direct access still bypasses these, same as it already bypasses **SHOW IN PC MENU**.

## 1.1.0

- Withdrawing a Pokémon now catches it in the Pokédex (seen + owned) if it wasn't already, mirroring what evolving one does -- both through this mod's own WITHDRAW <PK><MN> list and through the exported `withdrawPokemon`, which takes a new optional `game` argument to do it. Deposit, release and in-Bank moves are unaffected; only leaving the Bank for the party or a PC box registers it.

## 1.0.0

- Initial release: a second Pokémon/item storage kept outside every save file, so deposits made in one playthrough can be withdrawn in another.
  - **POKéMON**: styled like the vanilla PC's own box menu -- a plain named list (`source/src/ui/BoxMenu.lua`), not a visual box grid -- with WITHDRAW <PK><MN> / DEPOSIT <PK><MN> / RELEASE / CHANGE BOX rows, each opening a list of Pokémon by name and level; WITHDRAW and DEPOSIT offer a STATS submenu before confirming, matching vanilla. 20 slots per box (`boxCapacity`), no cap on the number of boxes -- depositing into a full bank grows it a box at a time instead of ever refusing a Pokémon, and an emptied-out box is deleted rather than kept as a gap (see API.md's box-numbering note for what this means for other mods). No in-game MOVE/reorder, matching vanilla; the exported `movePokemon` covers that programmatically.
  - **ITEMS**: styled like the vanilla Player's PC's own item menu (`source/src/ui/PlayerPC.lua`), not a merged pick-item-then-verb list -- WITHDRAW ITEM / DEPOSIT ITEM rows, each opening an alphabetically sorted list (the Bank's items, or the Bag's). A transfer updates the row in place and reports the result at the bottom without closing the list, matching vanilla. HMs and key items are always refused.
  - New **POKéMON BANK** row on the PC's own main menu, right below the player's own item-storage PC (BILL's PC / Player's PC / POKéMON BANK / PROF.OAK's PC / LOG OFF), toggleable with **SHOW IN PC MENU** and hideable by another mod through the exported `setPcEntryEnabled(false)`.
  - `mod.exports` API for other mods: deposit/withdraw/list/query both Pokémon and items, extend the item blacklist, open the Bank UI directly, control the PC menu row, and read a whole box as a grid-shaped snapshot (`getBox`) -- see API.md. `mod.vrm_pokemon_bank.*` events fire on every mutation, including through the exports.
  - `storage.lua` is written on the same schedule as the game's own save (hooked through `save.write`), not on every deposit/withdraw, so a reset without saving always reverts the Bank and the save file together instead of leaving a duplicated or vanished Pokémon/item behind. Each write rolls the previous file into `storage.lua.bak` and stages the new one as `storage.lua.tmp` first, the same backup-and-staged-write discipline `save.lua` itself uses, with the same recovery order on load. An exported `flush()` forces the write early for a mod that has its own reason to.
  - No dependency on any other mod.
