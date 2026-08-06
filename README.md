# Pokémon Bank

A second storage for Pokémon and items that lives **outside every save file**. Deposit a Pokémon or an item while playing one save -- any of Red, Blue or Yellow, any slot -- and withdraw it while playing a completely different one. The Bank is its own file, so New Game, deleting a save slot or switching versions never touches it.

## How to use it

Open any PC and select **POKéMON BANK**, a new row this mod adds right below your own item-storage PC. Two options:
- **POKéMON** opens a menu of its own:
  - **WITHDRAW <PK><MN>** lists the current box's Pokémon by name and level; picking one offers WITHDRAW (sends it to your party) or STATS.
  - **DEPOSIT <PK><MN>** lists your party the same way; picking one offers DEPOSIT (your last Pokémon can't be deposited) or STATS.
  - **RELEASE** lists the current box, asks to confirm, then it's gone for good.
  - **CHANGE BOX** lists every box with its Pokémon count (`*` marks the current one) -- see **How many boxes** below for how many there are.
  - There is no MOVE/reorder option here -- withdraw and re-deposit to reorganize, or see `movePokemon` in [API.md](./API.md) for a programmatic way.
- **ITEMS** opens a menu of its own too:
  - **WITHDRAW ITEM** lists the Bank's items (sorted alphabetically); picking one asks a quantity and adds it to your Bag (refused if your Bag has no room).
  - **DEPOSIT ITEM** lists your Bag's items the same way; picking one asks a quantity and stores it (refused up front for HMs and key items -- see **What can't be deposited** below).
  - Neither list closes after a transfer -- the row updates in place and the result shows at the bottom, so you can move several items in one visit, exactly like the vanilla PC does.

Withdrawing into a full party, or depositing your Bag's last non-key item stack it needs a slot for, behaves the same way the vanilla PC/Bag do: you're told, nothing is lost.

**Withdrawing catches it in your Pokédex** if it wasn't already seen/owned there -- the same way evolving one does. Depositing, releasing and moving Pokémon within the Bank never touch the Pokédex; only taking one out (to your party, or straight to a PC box through another mod's Bank integration) does.

Set **SHOW IN PC MENU** option to off (on by default) hides the row if you'd rather not see it; another mod can also hide it outright -- see [API.md](./API.md).

**SHOW POKéMON** and **SHOW ITEMS** (both on by default) let you turn off either side independently. With both on, the row opens the POKéMON/ITEMS chooser as above. With only one on, the row skips the chooser and opens that side directly. With both off, the row doesn't appear at all, same as turning off **SHOW IN PC MENU**. A mod can also hide either side outright, on top of these options -- see [API.md](./API.md).

## How many boxes

**No limit.** Depositing into a full bank grows it a box at a time instead of ever refusing a Pokémon. An emptied-out box (the last Pokémon in it withdrawn, released, or moved out) is deleted rather than left as a gap, so the Bank always has exactly one spare empty box past however many are actually in use -- it shrinks back down on its own as you empty it out, too.

## What can't be deposited

**HMs and key items never leave the save.** Their DEPOSIT option is refused with a message rather than hidden, so it's clear why. Everything else -- TMs, medicine, balls, battle items -- deposits freely, with no capacity limit on the item list either (any number of distinct stacks).

## Where the data lives

One file, `bank/storage.lua`, written next to `saves/` and `options.lua` in a portable install, or in the OS save directory otherwise -- the same place/rule the game's own saves and options follow (see  `SaveData.portableFs()`). It is never written into, or read from, `save.modData`, so no save slot carries a copy of it and no save can overwrite it.

**It's written on the same schedule as your save file.** A Bank transaction only changes things in memory; the actual write to `storage.lua` happens alongside the next time the game itself saves (a manual SAVE, an autosave mod, anything that reaches `Game:writeSave`). This is deliberate: if the Bank wrote immediately, resetting without saving after a deposit would leave you with the Pokémon both in the Bank *and* back in your unsaved party -- free duplication. Waiting for the same save point the game already uses means a reset always reverts both together, so nothing can be duplicated or lost that way. Before writing, the previous `storage.lua` rolls into `storage.lua.bak` and the new one stages as `storage.lua.tmp` before the swap -- the same backup-and-staged-write discipline the game's own save files use -- so a crash mid-write leaves a recoverable copy instead of a half-written file.

## For mod authors

Pokémon Bank is fully independent and exposes everything it does through `mod.exports`. See [API.md](./API.md) for the full reference.
