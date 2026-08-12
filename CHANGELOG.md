# Changelog

## 1.9.0

Added Gold (Gen 2) support. Fixes were needed in three places:
- The **POKéMON BANK** row on the game's own OPTIONS menu now anchors on **CANCEL** when **MODS** isn't in the row list, which is the case on Gold's OPTIONS menu (it has no MODS row) -- it used to land after CANCEL instead of before it.
- **A Pokémon can now cross generations cleanly.** A Gen 1 Pokémon's `stats.special` splits into Gold's `stats.specialAttack`/`stats.specialDefense` the moment it's withdrawn into a Gold save, and a Gold Pokémon's split recombines into `stats.special` the moment it's withdrawn into a Red/Blue/Yellow save -- computed with the target generation's own formula over the target generation's own base stats (`dvs`/`statExp`/`level` are the same shape and the same numbers on both, so the target's own math gives the right per-species answer instead of a copy). `exp`/`experience` are kept mirrored both ways, and `maxHp`/`types`/`catchRate` are backfilled from the target generation's own species data where a Gen 1 record doesn't carry them. Everything else a mon carries (`gender`, `item`, `happiness`, `pokerus`, `shiny`, `otName`, `caughtLevel`...) already degrades gracefully on the generation that doesn't use it -- the engine's own Gold code already reads every one of those with a nil-safe fallback.

A Pokémon's **held item is now validated too**, on every save load, the same as the Bank's own item storage: an id the active game doesn't recognize (a mod-added item whose mod is gone, or a Gold held-only item viewed on Red) or one that's HM/key-item blacklisted is stripped off the Pokémon and moved into the same item quarantine `lib/Items.lua` already keeps -- reachable back out with WITHDRAW ITEM once it's valid again, and shown on the load-time report under "Items removed:" alongside everything else that got quarantined.

**[CRYSTAL_251](https://github.com/Deftones565/gen1recomp-mod-crystal-251) held items are recognized too**, when that mod is installed: it keeps a Pokémon's held item on `mon.heldItem` instead of Gold's `mon.item`. Both fields are kept mirrored to the same id -- so a Pokémon holding an item under CRYSTAL_251 shows up holding it on Gold once withdrawn there, and the other way around -- and validated as the one item they actually represent, not counted twice. Nothing about this touches CRYSTAL_251 on any other boot: `mod.find("CRYSTAL_251")` itself is the capability check, since that mod never loads anywhere but a Gen 1 boot that has it installed.

## 1.8.0

New **POKéMON BANK** row on the game's own OPTIONS menu: opens a full OPTIONS-style page with **EXPORT DATA**, **IMPORT DATA** and **DELETE DATA**.

EXPORT/IMPORT DATA open the host's own native file dialog (Windows/macOS/Linux) so the player picks exactly where the `.lua` file goes, rather than a fixed path; IMPORT still asks to confirm first, since it replaces everything currently stored. Where no dialog can be opened (mobile, consoles), both fall back to a fixed `bank/export.lua`, rolling any file already there into `bank/export.lua.bak` first.

DELETE DATA removes the Bank's entire storage folder (every box, item, stored money and any leftover export files), behind two separate confirmations rather than the usual one, there's no way to get any of it back afterward.

## 1.7.1

Startup validation now also quarantines any HM or key item found sitting in the Bank's item storage, matching `depositItem`'s own blacklist (covers items that got in before the rule applied, e.g. older saves). An item already in quarantine stays there while it's still an HM or key item, even if it's otherwise a valid, known item id -- it no longer gets auto-restored.

Added basic [Gen1 Modern UI](https://github.com/ArmstrongThomas/gen1-modern-ui) compatibility for **TRANSFER BOX**, **MOVE PKMN** and **MOVE ITEM** -- the three screens its generic presenter couldn't already recognize on its own.

## 1.7.0

New **MOVE PKMN** option under POKéMON: a single browsable view of the Bank, the party and a PC box in place of a plain list. SELECT cycles between the three (BANK > PARTY > PC); Left/Right flips through boxes. Picking a Pokémon opens TO BANK/PARTY/PC (whichever two storages aren't the one currently shown), SWITCH (swap it with another Pokémon in that same storage, navigating boxes to reach the target), STATS and RELEASE. TO BANK/PARTY/PC reuse the bulk transfer exports below for the Bank side; direct PARTY <-> PC moves stay internal to this screen, matching the vanilla PC's own party/box rules (party never drops below one, box capacity 20).

New **TRANSFER BOX** option under POKéMON: a two-step box picker. Press A on a non-empty box locks it in as the source and switches to the other storage (a Bank box picked first shows the PC next, and vice versa); A again asks to confirm, then moves every Pokémon in the source box to the one on screen, overflowing into the following boxes if it doesn't all fit in one.

New bulk transfer exports: `depositPartyPokemon(game, opts)` and `depositBoxPokemon(game, pcBoxNum, opts)` move several Pokémon from the party or a PC box into the Bank at once; `withdrawToParty(game, opts)` and `withdrawToBox(game, targetPcBoxNum, opts)` move several Bank Pokémon out to the party or a PC box at once (both fill the target box then overflow into the next ones with room). All four default to sensible index sets (party keeps its first Pokémon, PC/Bank box transfers default to everything) -- see API.md for the full reference. TRANSFER BOX and MOVE PKMN's TO BANK/TO PC options are built on top of these.

New **MOVE ITEM** option under ITEMS: the same idea as MOVE PKMN but for the three item storages -- SELECT cycles BANK > BAG > PC, with the same top-right `{cursor}/{total}` counter MOVE PKMN shows. Picking an item opens TO BANK/BAG/PC (whichever two aren't the one currently shown), SWITCH (BAG only -- reorders it like the real Bag menu; shown in acquisition order instead of alphabetically so the reorder is actually visible, unlike every other list here) and TOSS, which works in all three storages here (unlike the standalone TOSS ITEM below, which stays Bank-only) -- the Bag and PC sides refuse an HM/key item first, same as their own vanilla TOSS.

New **TOSS ITEM** option under ITEMS: lists the Bank's own items and permanently deletes a chosen quantity after confirming, mirroring the vanilla PC's own item toss. New export `tossItem(id, qty)` -- same storage effect as `withdrawItem`, but fires `item_tossed` instead of `item_withdrawn` so a listener can tell "left for a bag" apart from "discarded" (mirrors `releasePokemon` vs `withdrawPokemon`).

New **SHOW FIRST IN PC MENU** option (off by default): moves the **POKéMON BANK** row to the very top of the PC menu.

## 1.6.0

Replaced the custom `invalidPokemon`/`invalidItems` quarantine system with the game's native `orphaned` structure for parity with base game behavior. Storage schema bumped to **version 3** (`orphaned.mons`, `orphaned.items`); upgrading from version 2 automatically migrates existing quarantined data. The validation report now uses the game's `QuarantineReport` UI instead of a custom text box, showing detailed information about which Pokémon/items were moved to the LOST box and which were restored. The `orphaned` structure is automatically removed when empty, matching SaveData's cleanup behavior.

## 1.5.0

After loading a save, the Bank now validates all four storage lists (valid Pokémon, valid items, invalid Pokémon, invalid items) against the active game's data. Unknown species or moves quarantine a Pokémon into `invalidPokemon`; unknown item ids quarantine stacks into `invalidItems`. Entries that become valid again (e.g. after installing the mod that defines them) move back automatically -- restored Pokémon are appended to the end of the last box. A summary message is shown when anything moved. Storage schema bumped to **version 2** (`invalidPokemon`, `invalidItems`); upgrading an existing `storage.lua` marks it dirty so it is rewritten on the next save. New exports: `isValidPokemon`, `isValidItem`, `validatePokemonStorage`, `validateItemsStorage`, `validateStorage`, `listInvalidPokemon`, `invalidPokemonCount`, `listInvalidItems`, `invalidItemCount` -- see API.md.

## 1.4.1

- Internal: split the single `main.lua` into three library modules loaded the same way `vrm_unified_pc_system` loads its own (`mod:read`/`load`, since the mod's own directory isn't on `package.path`) -- `lib/Pokemon.lua` (box storage, WITHDRAW/DEPOSIT/RELEASE/CHANGE BOX), `lib/Items.lua` (item storage, the HM/key-item blacklist, WITHDRAW ITEM/DEPOSIT ITEM) and `lib/Money.lua` (money storage, DEPOSIT MONEY/WITHDRAW MONEY and its amount picker). The shared persistence layer (`storage.lua` read/write, the `save.write` flush hook) and the PC-entry chooser stay in `main.lua`, since one `storage.lua` and one PC row back all three tabs. No behavior change.

## 1.4.0

New exports `isPcEntryEnabled()` / `isPokemonTabEnabled()` / `isItemsTabEnabled()` / `isMoneyTabEnabled()` -- the read side of `setPcEntryEnabled` / `setPokemonTabEnabled` / `setItemsTabEnabled` / `setMoneyTabEnabled`, since the player's own **SHOW IN PC MENU** / **POKéMON MENU** / **ITEMS MENU** / **MONEY MENU** options weren't reachable through `mod.find()` before -- another mod integrating with the Bank had no way to check whether a side was actually visible.

## 1.3.0

The Bank can now hold **money** too, as a third **MONEY** option next to POKéMON/ITEMS: **DEPOSIT MONEY** and **WITHDRAW MONEY** open an amount picker (Up/Down by 1, Left/Right by 100, START jumps to the max) showing your own MONEY and the Bank's BANK balance above the amount. Deposits are capped by how much you're carrying; withdrawals by both the Bank's own balance and the room left before your money would cross the game's own ¥999999 cap. New **MONEY MENU** option (on by default, mirrors **POKéMON MENU**/**ITEMS MENU**) and exported `setMoneyTabEnabled(enabled)` let it be turned off independently. The **POKéMON BANK** row's chooser now lists whichever of the three sides are enabled, bottom-aligned so a third row no longer pushes CANCEL past the bottom of the screen -- with exactly one enabled (by option or by another mod), the row still skips straight to it, same as before. New exports: `bankMoney()`, `depositMoney(amount)`, `withdrawMoney(amount)`, `maxMoney`, `moneyScreenId`; `open(game, tab)` accepts `"money"`. New events `mod.vrm_pokemon_bank.money_deposited` / `money_withdrawn`, both `{ amount }`.

## 1.2.0

New **POKéMON MENU** / **ITEMS MENU** options (both on by default) let each side of the Bank be turned off independently, and the new exported `setPokemonTabEnabled(enabled)` / `setItemsTabEnabled(enabled)` let another mod do the same on top of them. With only one side enabled, the **POKéMON BANK** PC row skips the POKéMON/ITEMS chooser and opens that side directly; with neither enabled, the row doesn't appear at all (mirrors how **SHOW IN PC MENU** / `setPcEntryEnabled` already hide the whole row). `open(game, tab)` and the registered screen ids are unaffected -- direct access still bypasses these, same as it already bypasses **SHOW IN PC MENU**.

## 1.1.0

Withdrawing a Pokémon now catches it in the Pokédex (seen + owned) if it wasn't already, mirroring what evolving one does -- both through this mod's own WITHDRAW PKMN list and through the exported `withdrawPokemon`, which takes a new optional `game` argument to do it. Deposit, release and in-Bank moves are unaffected; only leaving the Bank for the party or a PC box registers it.

## 1.0.0

Initial release: a second Pokémon/item storage kept outside every save file, so deposits made in one playthrough can be withdrawn in another.
  - **POKéMON**: styled like the vanilla PC's own box menu -- a plain named list -- with WITHDRAW PKMN / DEPOSIT PKMN / RELEASE / CHANGE BOX rows, each opening a list of Pokémon by name and level; WITHDRAW and DEPOSIT offer a STATS submenu before confirming, matching vanilla. 20 slots per box (`boxCapacity`), no cap on the number of boxes -- depositing into a full bank grows it a box at a time instead of ever refusing a Pokémon, and an emptied-out box is deleted rather than kept as a gap (see API.md's box-numbering note for what this means for other mods). No in-game MOVE/reorder, matching vanilla; the exported `movePokemon` covers that programmatically.
  - **ITEMS**: styled like the vanilla Player's PC's own item menu (`source/src/ui/PlayerPC.lua`), not a merged pick-item-then-verb list -- WITHDRAW ITEM / DEPOSIT ITEM rows, each opening an alphabetically sorted list (the Bank's items, or the Bag's). A transfer updates the row in place and reports the result at the bottom without closing the list, matching vanilla. HMs and key items are always refused.
  - New **POKéMON BANK** row on the PC's own main menu, right below the player's own item-storage PC (BILL's PC / Player's PC / POKéMON BANK / PROF.OAK's PC / LOG OFF), toggleable with **SHOW IN PC MENU** and hideable by another mod through the exported `setPcEntryEnabled(false)`.
  - `mod.exports` API for other mods: deposit/withdraw/list/query both Pokémon and items, extend the item blacklist, open the Bank UI directly, control the PC menu row, and read a whole box as a grid-shaped snapshot (`getBox`) -- see API.md. `mod.vrm_pokemon_bank.*` events fire on every mutation, including through the exports.
  - `storage.lua` is written on the same schedule as the game's own save (hooked through `save.write`), not on every deposit/withdraw, so a reset without saving always reverts the Bank and the save file together instead of leaving a duplicated or vanished Pokémon/item behind. Each write rolls the previous file into `storage.lua.bak` and stages the new one as `storage.lua.tmp` first, the same backup-and-staged-write discipline `save.lua` itself uses, with the same recovery order on load. An exported `flush()` forces the write early for a mod that has its own reason to.
