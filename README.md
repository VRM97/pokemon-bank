# Pokémon Bank

A second storage for Pokémon, items and money that lives **outside every gen1recomp save file**. Deposit a Pokémon, an item or money while playing one save -- any of Red, Blue, Yellow or Gold, any slot -- and withdraw it while playing a completely different one. The Bank is its own file, so New Game, deleting a save slot or switching versions never touches it.

## How to use it

Open any Pokémon Center PC and select **POKéMON BANK**. On Red/Blue/Yellow it's part of the same WHICH PC list your own bedroom PC opens too; on Gold it's a row on the Pokécenter's "Access whose PC?" screen, next to BILL's PC and PROF.OAK's PC -- Gold's own bedroom PC has no box access at all (same as BILL's storage), so POKéMON BANK is Pokécenter-only there. Three options:
- **POKéMON**:
  - **WITHDRAW PKMN** lists the current box's Pokémon by name and level; picking one offers WITHDRAW (sends it to your party) or STATS.
  - **DEPOSIT PKMN** lists your party the same way; picking one offers DEPOSIT (your last Pokémon can't be deposited) or STATS.
  - **MOVE PKMN** opens a single browsable view instead of a list: SELECT cycles between the Bank, your party and a PC box (BANK > PARTY > PC); Left/Right flips through boxes while viewing the Bank or the PC. Picking a Pokémon offers TO BANK/PARTY/PC (only the two storages you're *not* currently viewing), SWITCH (swap places with another Pokémon in that same storage -- Left/Right still works while picking the target, so the swap can land in a different box), STATS and RELEASE.
  - **RELEASE PKMN** lists the current box, asks to confirm, then it's gone for good.
  - **TRANSFER BOX** picks two whole boxes to move at once, browsable the same way as MOVE PKMN: SELECT alternates only between the Bank and a PC box (Left/Right flips through boxes as usual). A on a non-empty box locks it in as the source and switches you to the other storage -- pick a Bank box and it shows you a PC box next, or the other way around -- with SELECT locked out from there so you can only land on a box in that other storage. A again asks to confirm, then moves every Pokémon across, overflowing into the following boxes if it doesn't all fit in one; B while picking the destination backs out to choosing a different source instead of leaving the screen.
  - **CHANGE BOX** lists every box with its Pokémon count (`*` marks the current one) -- see **How many boxes** below for how many there are.
- **ITEMS**:
  - **WITHDRAW ITEM** lists the Bank's items (sorted alphabetically); picking one asks a quantity and adds it to your Bag (refused if your Bag has no room).
  - **DEPOSIT ITEM** lists your Bag's items the same way; picking one asks a quantity and stores it (refused up front for HMs and key items -- see **What can't be deposited** below).
  - **MOVE ITEM** opens a single browsable view of three item storages: BANK, BAG and *Player*'s PC, SELECT cycles between them. Picking an item offers TO BANK/BAG/PC (only the two storages you're *not* currently viewing, asking a quantity and moving it there), SWITCH (BAG only -- swaps its place with another item in your Bag, the same reordering the real Bag menu's own SELECT does), TOSS (your Bag and PC both refuse an HM/key item first, same as their own vanilla TOSS does) and CANCEL.
  - **TOSS ITEM** lists the Bank's items and permanently deletes a quantity of the one you pick, after asking to confirm -- nothing here can be an HM or key item, since those can never enter the Bank to begin with.
  - Neither list closes after a transfer -- the row updates in place and the result shows at the bottom, so you can move several items in one visit, exactly like the vanilla PC does.
- **MONEY**:
  - **DEPOSIT MONEY** and **WITHDRAW MONEY** each open an amount box showing your own MONEY and the Bank's BANK balance above it: Up/Down change the amount by 1 (wrapping at 1/max), Left/Right by 100 (capped, not wrapping), START jumps straight to the max, A confirms, B cancels.
  - Depositing is capped by how much money you're carrying; withdrawing is capped by both the Bank's own balance and how much room is left before your money would hit the game's own ¥999999 cap.

Withdrawing into a full party, or depositing your Bag's last non-key item stack it needs a slot for, behaves the same way the vanilla PC/Bag do: you're told, nothing is lost.

**Withdrawing register it in your Pokédex** if it wasn't already seen/owned there -- the same way evolving one does. Depositing, releasing and moving Pokémon within the Bank never touch the Pokédex; only taking one out (to your party, or straight to a PC box through another mod's Bank integration) does.

**Crossing generations just works.** Deposit a Pokémon on Red and withdraw it on Gold, or the other way around, and its stats come out right on either side -- Gold's split Special Attack/Special Defense is recalculated from the same DVs and level the moment it's withdrawn there, and recombines into Red's single Special the same way going back. A status condition crosses too (a badly-poisoned Pokémon from Gold lands as plain poisoned on Red, since Red has no such distinction). Nothing about the Pokémon is lost either way; a Gold-only detail (held item, gender, Pokérus, shininess, and so on) simply has nothing to do on Red and reappears exactly as it was once you're back on Gold.

**An Egg crosses generations too**, hatch timer and already-rolled moves intact either way -- withdrawing it on Gold or on a Red/Blue/Yellow save with [CRYSTAL_251](https://github.com/Deftones565/gen1recomp-mod-crystal-251) installed picks up right where it left off. A plain Red/Blue/Yellow save has no Day Care breeding at all, so an Egg deposited from elsewhere is set aside the same way an unknown Pokémon is (see **Where the data lives** below) until it's viewed from a game that knows what to do with it. An Egg **always** becomes yours (OT, OT ID and OT name) the moment you withdraw it.

Set **SHOW IN PC MENU** option to off (on by default) hides the row if you'd rather not see it; another mod can also hide it outright -- see [API.md](./API.md).

Turn on **SHOW FIRST IN PC MENU** (off by default) to move the **POKéMON BANK** row to the very top of the PC menu.

**POKéMON MENU**, **ITEMS MENU** and **MONEY MENU** (all on by default) let you turn off any side independently. With two or more on, the row opens a chooser listing just the enabled ones, as above. With only one on, the row skips the chooser and opens that side directly. With all off, the row doesn't appear at all, same as turning off **SHOW IN PC MENU**. A mod can also hide any side outright, on top of these options -- see [API.md](./API.md).

Turn on **INHERIT TRAINER** (off by default) to make every *other* Pokémon you withdraw become yours too, the same way: OT, OT ID and OT name change to your own the moment it leaves the Bank.

**AUTO HEAL** (NEVER by default) fully heals a Pokémon -- HP restored, status cured, every move's PP topped back up to its current cap -- at a moment you choose: **ON DEPOSIT** (the instant it enters the Bank, through DEPOSIT PKMN, MOVE PKMN or either bulk export), **ON WITHDRAW** (the instant it leaves, through WITHDRAW PKMN, MOVE PKMN or either bulk export), or **AT POKéMON CENTER** (every Pokémon already sitting in the Bank, the moment the game's own Nurse actually heals your party -- a blackout/whiteout doesn't count, only an actual Center visit does). Mod authors can also heal the whole Bank at once on demand -- see [API.md](./API.md).

## How many boxes

**No limit.** Depositing into a full bank grows it a box at a time instead of ever refusing a Pokémon. An emptied-out box (the last Pokémon in it withdrawn, released, or moved out) is deleted rather than left as a gap, so the Bank always has exactly one spare empty box past however many are actually in use -- it shrinks back down on its own as you empty it out, too.

## What can't be deposited

**HMs and key items never leave the save.** Their DEPOSIT option is refused with a message rather than hidden, so it's clear why. Everything else -- TMs, medicine, balls, battle items -- deposits freely, with no capacity limit on the item list either (any number of distinct stacks).

## Where the data lives

One file, `bank/storage.lua`, written next to `saves/` and `options.lua` in a portable install, or in the OS save directory otherwise -- the same place/rule the game's own saves and options follow (see  `SaveData.portableFs()`). It is never written into, or read from, `save.modData`, so no save slot carries a copy of it and no save can overwrite it.

**It's written on the same schedule as your save file.** A Bank transaction only changes things in memory; the actual write to `storage.lua` happens alongside the next time the game itself saves (a manual SAVE, an autosave mod, anything that reaches `Game:writeSave`). This is deliberate: if the Bank wrote immediately, resetting without saving after a deposit would leave you with the Pokémon both in the Bank *and* back in your unsaved party -- free duplication. Waiting for the same save point the game already uses means a reset always reverts both together, so nothing can be duplicated or lost that way. Before writing, the previous `storage.lua` rolls into `storage.lua.bak` and the new one stages as `storage.lua.tmp` before the swap -- the same backup-and-staged-write discipline the game's own save files use -- so a crash mid-write leaves a recoverable copy instead of a half-written file.

**After you load a save**, the Bank checks every stored Pokémon and item against the active game's data. A Pokémon whose species or any move is unknown is set aside in an internal invalid list (not shown in the normal WITHDRAW lists); an item whose id is unknown is set aside the same way, and so is an HM or key item found in storage (they can never be deposited going forward, but this catches ones that ended up there some other way -- an older save, a mod change, and so on). If something that was invalid becomes valid again -- because you installed the mod that defines it, or switched to a version that includes it -- it is moved back automatically (Pokémon go to the end of the last box); an HM or key item stays set aside even then, since it's still not allowed in the Bank. You get a short summary message when anything moved.

The game's own **OPTIONS** menu has a **POKéMON BANK** row, independent of **SHOW IN PC MENU** -- it opens a page with three actions:
- **EXPORT DATA** opens your device's own file dialog (Windows/macOS/Linux) so you can save the Bank's entire contents wherever you like, as a `.lua` file. Where no dialog is available (mobile, consoles), it writes to `bank/export.lua` instead, rolling any file already there into `bank/export.lua.bak` first so exporting again never loses the previous one.
- **IMPORT DATA** opens the same dialog to pick a file to load and, after you confirm, **replaces the Bank's current contents with it** -- anything deposited since that export was made is gone. Without a dialog, it reads `bank/export.lua` back in instead.
- **DELETE DATA** erases the Bank's storage folder entirely -- every box, item, stored ¥, and any leftover export files -- back to nothing. Since there's no way to get any of it back afterward, it's the only Bank action that asks **twice** before going through, unlike the single confirmation RELEASE PKMN or TOSS ITEM ask for.

The file dialog **blocks the game** while it's open, the same as choosing a ROM to import does. EXPORT/IMPORT/DELETE all take effect on disk immediately rather than waiting for the next save, unlike a normal deposit/withdraw (see **Where the data lives** above).

## For mod authors

Pokémon Bank is fully independent and exposes everything it does through `mod.exports`. See [API.md](./API.md) for the full reference.
