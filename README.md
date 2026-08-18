# Pokémon Bank

A second storage for Pokémon, items, moves and money that lives **outside every save file**. Deposit a Pokémon, an item, a move or money while playing one save and withdraw it while playing a completely different one, any gen, any slot. The Bank is its own file, so New Game, deleting a save slot or switching versions never touches it.

## How to use it

Open any Pokémon Center PC and select **POKéMON BANK**. Four options:

### POKéMON

- **MOVE PKMN** browses the Bank, your party and a PC box at once (SELECT cycles, Left/Right flips boxes). Picking a Pokémon offers TO BANK/PARTY/PC, SWITCH, STATS or RELEASE.
- **WITHDRAW PKMN** lists the current box's Pokémon by name and level; picking one offers WITHDRAW (sends it to your party) or STATS.
- **DEPOSIT PKMN** lists your party the same way; picking one offers DEPOSIT (your last Pokémon can't be deposited) or STATS.
- **RELEASE PKMN** lists the current box and asks to confirm.
- **TRANSFER BOX** moves an entire box at once: pick a source box (A), then a box on the other side as the destination, confirm, and every Pokémon moves across, overflowing into further boxes if needed.
- **CHANGE BOX** lists every box with its Pokémon count (`*` marks the current one).

**No box limit.** A full Bank grows another box instead of ever refusing a Pokémon, and an emptied-out box is removed automatically.

**Withdrawing registers it in your Pokédex** if it wasn't already seen or owned (the same way evolving one does).

**Crossing generations just works.** A Pokémon's stats and status translate correctly whichever way you cross, and nothing is lost.

**An Egg crosses generations too**, hatch timer and moves intact between Gold and a Gen 1 save with [CRYSTAL_251](https://github.com/Deftones565/gen1recomp-mod-crystal-251). Elsewhere it's set aside until viewed from a game that supports it (see **Where the data lives**). It **always** becomes yours the moment you withdraw it.

### ITEMS

- **MOVE ITEM** browses the Bank, Bag and PC at once (SELECT cycles). Picking an item offers TO BANK/BAG/PC, SWITCH (Bag only) or TOSS.
- **WITHDRAW ITEM** lists the Bank's items (sorted alphabetically); picking one asks a quantity and adds it to your Bag (refused if your Bag has no room).
- **DEPOSIT ITEM** lists your Bag's items the same way; picking one asks a quantity and stores it (refused up front for HMs and key items).
- **TOSS ITEM** lists the Bank's items and permanently deletes a quantity you pick, after confirming.

**TMs go through the MOVES tab instead.** DEPOSIT ITEM and MOVE ITEM refuse one with a message pointing you there. With the MOVES tab turned off, that rule drops too -- a TM deposits like any other item, since there's nowhere else for it to go right now (whatever's already banked as a move stays there regardless). A TM already in the Bank still withdraws normally either way. Everything else deposits freely, with no limit on distinct item stacks.

### MOVES

A TM you deposit here is banked as the move it teaches (or adds a use to one already banked) instead of taking up an item slot; withdrawing turns a banked use back into the matching TM item.

- **DEPOSIT MOVE** lists your Bag's TM stacks (never HMs). Picking one asks a quantity and converts it into that many banked uses of the move it teaches.
- **WITHDRAW MOVE** lists every banked move (sorted alphabetically); picking one asks a quantity and adds that many TMs to your Bag (refused if your Bag has no room).
- **TEACH MOVE** spends one banked use directly, no TM needed: pick a move, then a Pokémon, marked **ABLE** or **---** by every way it (or a prevolution) could ever know that move, not just by TM. A move already known, or one it can't learn, is refused and the use isn't spent. With [Reusable Machines](https://github.com/FAFF0x/gen1recomp) installed, a successful teach doesn't spend the use either.
- **RELEARN MOVE** recovers a move that couldn't fill itself back in automatically because the Pokémon's moveset was already full. It only shows up when there's one like that to bring back. Doesn't touch the Bank's own move stock.

### MONEY

- **DEPOSIT MONEY** opens an amount box showing your own MONEY and the Bank's BANK balance (Up/Down cycles the digit, Left/Right moves the cursor, START jumps to the max, A confirms, B cancels), capped by how much you're carrying.
- **WITHDRAW MONEY** opens the same amount box, capped by both the Bank's own balance and how much room is left before your money would hit the game's own ¥999999 cap.

### LINK

Sends Pokémon, items, moves and money straight from your Bank to another player's, over the same LAN peer-to-peer connection or public relay the game's own **LINK CABLE** uses. Opening it asks to save the game first (defaulting to YES) -- a connection like this is exactly the kind of thing worth having a fresh save behind before it starts.

1. Pick **LAN** or **ONLINE**. Under **LAN**, **HOST** shows the address for the other player to type in under **JOIN**. Under **ONLINE**, **HOST** shows a 6-character code for the other player to type in under **JOIN**, no shared network needed. Either way, both sides need the exact same LINK version and BANK data version -- a mismatch is refused with a message.
2. Build what you're sending: **POKéMON**, **ITEMS** and **MOVES** each browse BANK and SEND (SELECT toggles between them; picking a Pokémon or a quantity of an item/move offers **SEND**/**TAKE BACK** and **STATS**), **MONEY** does the same with **SEND MONEY**/**TAKE BACK**. **CONFIRM** shows a summary and waits for the other player to confirm too. **CANCEL** ends the link and returns everything you'd set aside.
3. Once both sides confirm, each one's parcel is on its way: review what's arriving (**POKéMON**, opening straight to its STATS/**ITEMS**/**MOVES**/**MONEY**, read-only), already checked against your own game -- anything it doesn't recognize (a Pokémon, item or move only the other player's mods know about) shows up under **LOST** instead of the normal rows, exactly like **VIEW LOST**. **CONFIRM** again, **GO BACK** to STEP 2 (pulls the other player back with you), or **CANCEL** -- either way, at this point, still with no changes on either side.
4. Once both sides confirm the second time, it all lands in your Bank for good -- whatever was under **LOST** goes straight into the Bank's own quarantine, same as anything a save-load sets aside -- and the game saves immediately.

**This isn't a trade.** LINK moves Pokémon straight from one Bank to another, not between two parties the way the game's own trade does -- so a Pokémon that evolves by trading won't evolve just from crossing over this way. That's intentional.

## Options

LABEL|CHOICES|DEFAULT|DESCRIPTION|
-|-|-|-
SHOW IN PC MENU|NONE / START / MIDDLE / END|END|Where the **POKéMON BANK** row sits on the PC menu: **NONE** hides it, **START** is the very top, **MIDDLE** sits right below BILL's PC, **END** sits right below the player's PC.
POKéMON MENU*|ON / OFF|ON|Turns the POKéMON tab on or off.
ITEMS MENU*|ON / OFF|ON|Turns the ITEMS tab on or off.
MOVES MENU*|ON / OFF|ON|Turns the MOVES tab on or off.
MONEY MENU*|ON / OFF|ON|Turns the MONEY tab on or off.
LINK MENU*|ON / OFF|ON|Turns the LINK tab on or off.
INHERIT TRAINER|ON / OFF|OFF|Makes every withdrawn Pokémon become yours (OT, OT ID and OT name).
AUTO HEAL|NEVER / ON DEPOSIT / ON WITHDRAW / AT POKéMON CENTER|NEVER|Fully heals a Pokémon at the chosen moment (**AT POKéMON CENTER** heals the whole Bank).
LOAD REPORT|NONE / MESSAGE / REPORT|REPORT|Controls how you're notified when a load moves anything to or from quarantine.

*\* With two or more on, the row opens a chooser listing just the enabled ones, as above. With only one on, the row skips the chooser and opens that side directly. With all off, the row doesn't appear at all, same as setting **SHOW IN PC MENU** to **NONE**.*

### Game OPTIONS menu

The game's own **OPTIONS** menu has a **POKéMON BANK** row, independent of **SHOW IN PC MENU**: it opens a page with every option above, followed by ~~five~~ three actions:

- **VIEW STATS** shows a running log of everything the Bank has ever handled. SELECT switches between all-time totals and just this save's own contribution.
- **VIEW LOST** browses whatever's currently quarantined (Pokémon, items and banked moves the active game doesn't recognize right now). SELECT cycles between the three lists. Read-only, same data the load-time **LOAD REPORT** summarizes; each entry moves itself back automatically once viewed from a game that recognizes it again.
- ~~**EXPORT DATA\*** writes the Bank's entire contents to `bank/export.lua`, backing up any previous export first.~~
- ~~**IMPORT DATA\*** reads that file back in and, after confirming, **replaces the Bank's current contents with it**.~~
- **DELETE DATA\*** erases the Bank entirely and asks **twice** first, since it can't be undone. Each save's own stats are untouched, since they live in the save, not the Bank.

*\* Take effect on disk immediately.*

## Where the data lives

`bank/storage.lua`, written next to `saves` and `options.lua` in a portable install, or in the OS save directory otherwise. It is never written into, or read from, `save.modData`, so no save slot carries a copy of it and no save can overwrite it.

The Bank's all-time stats (**VIEW STATS** above) follow the exact same rule, in their own file next to it, `bank/stats.lua`. Only the "THIS SAVE" half of that screen is the exception: it's written into `save.modData` on purpose, since it's meant to travel and rewind with that one save rather than the shared Bank.

**It's written on the same schedule as your save file.** A Bank transaction only changes things in memory; the actual write to `storage.lua` happens alongside the next time the game itself saves (a manual SAVE, an autosave mod, anything that reaches `Game:writeSave`). This is deliberate: if the Bank wrote immediately, resetting without saving after a deposit would leave you with the Pokémon both in the Bank *and* back in your unsaved party. Waiting for the same save point the game already uses means a reset always reverts both together, so nothing can be duplicated or lost that way. Before writing, the previous `storage.lua` rolls into `storage.lua.bak` and the new one stages as `storage.lua.tmp` before the swap (the same backup-and-staged-write discipline the game's own save files use) so a crash mid-write leaves a recoverable copy instead of a half-written file.

**After you load a save**, the Bank checks every stored Pokémon, item and banked move against the active game's data. A Pokémon whose *species* is unknown or an Egg on a Gen 1 save without CRYSTAL_251 is set aside in an internal invalid list (not shown in the normal WITHDRAW lists, but browsable any time through **VIEW LOST**); an item whose id is unknown is set aside the same way, and so is an HM or key item found in storage (they can never be deposited going forward, but this catches ones that ended up there some other way); a banked move id this game version doesn't recognize *at all* (a different version, or the mod that added it removed) is set aside too. If something that was invalid becomes valid again it is moved back automatically (Pokémon go to the end of the last box); an HM or key item stays set aside even then, since it's still not allowed in the Bank.

**A Pokémon whose *moveset* includes an unknown move is treated differently:** only that move is set aside, every other move it knows stays right where it was, and so does the Pokémon itself. Once a set-aside move is valid again, it fills back into an empty slot on its own, on the next load, for that specific Pokémon wherever it ends up (the Bank, your party, a PC box); if its moveset was already full at that point, it stays waiting there until you bring it back yourself with **RELEARN MOVE** on the MOVES tab.

## For mod authors

Pokémon Bank is fully independent and exposes everything it does through `mod.exports`: deposit, withdraw and query every side of the Bank -- Pokémon (including bulk party/PC transfers), items, banked moves and money -- push straight to any tab's own screen or the same chooser the PC's own **POKéMON BANK** row opens, reuse the same BANK/PARTY-or-BAG/PC browsing screens (**Pickers**) TEACH MOVE and RELEARN MOVE are themselves built on, and listen for an event on every deposit, withdraw, release, teach or transfer -- whether it happened through this mod's own UI or through the exports themselves. See [API.md](./API.md) for the full reference.
