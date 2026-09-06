# Pokémon Bank

A second storage for Pokémon, items, moves and money that lives **outside every save file**. Deposit a Pokémon, an item, a move or money while playing one save and withdraw it while playing a completely different one, any gen, any slot. The Bank is its own file, so New Game, deleting a save slot or switching versions never touches it.

## How to use it

Open any Pokémon Center PC and select **POKéMON BANK**. Five options:

### POKéMON

**MANAGE PKMN** browses the Bank, your party and a PC box at once (SELECT cycles, Left/Right flips boxes). Picking a Pokémon offers TO BANK/PARTY/PC, SWITCH, STATS or RELEASE. On BANK/PC, **START opens MANAGE BOX**; the title also shows MANAGE BOX's own small square whenever the box on screen is the current one. The highlighted Pokémon's own species shows under the list.

**MANAGE BOX** browses BANK and PC at once (SELECT cycles), listing every box with its Pokémon count, a small square next to the name marking the current one. Picking a box offers **VIEW** (closes box manager and jumps straight back to that box Pokémon list), **CHANGE** (makes it the current box), **SWITCH** (swaps two boxes), **TRANSFER** (moves its entire contents at once to a box you then pick overflowing into further boxes if needed) and **RENAME** (opens the naming screen; a blank name reverts it to default). **DELETE** (removes a box outright, only works on an already-empty box) is **BANK** only.

**A box holds up to 20 Pokémon by default.** A full box grows another one instead of ever refusing a Pokémon. An emptied-out box is removed automatically depending on the DELETE EMPTY BOX option.

**Withdrawing registers it in your Pokédex** if it wasn't already seen or owned (the same way evolving one does).

**Crossing generations just works.** A Pokémon's stats and status translate correctly whichever way you cross, and nothing is lost.

**An Egg crosses generations too**, hatch timer and moves intact between Gen 2 and a Gen 1 save with [CRYSTAL 251](https://github.com/Deftones565/gen1recomp-mod-crystal-251). Elsewhere it's set aside until viewed from a game that supports it (see **Where the data lives**). It **always** becomes yours the moment you withdraw it.

#### TIME CAPSULE

**TIME CAPSULE** is its own separate storage, a flat list with no boxes. It only ever moves a Pokémon **forward**: from an earlier generation's save into a later one, never back, mirroring the real Time Capsule's own one-way rule.

- **DEPOSIT PKMN** browses the Bank, your party and a PC box, same as MANAGE PKMN's own list. A Pokémon refuses to go in if it's an Egg or if it's holding an item (remove it first); nothing at all can go in while you're playing the highest generation this project currently supports, since there's nowhere further for anything to go from there.
- **WITHDRAW PKMN** lists everything currently sitting in the capsule. Picking one offers **TO BANK** (Hidden on TIME CAPSULE STORAGE MODE)/**TO PARTY**/**TO PC**, **STATS** or **RELEASE**. **START** does the same for every Pokémon in the capsule that's actually eligible right now, asking for one destination box up front (PC boxes only, under that same **STORAGE MODE**) and sending all of them there at once, overflowing into further boxes exactly like a normal deposit.

A Pokémon that's eligible by generation still needs its species and every one of its moves to actually exist in the game you're withdrawing into. One that clears everything and isn't already holding an item always picks up a held item on arrival, the same species-by-catch-rate item the real Time Capsule assigns.

That same generation floor still applies even after a Pokémon leaves the capsule and drifts back into the general Bank.

### ITEMS

Browses the Bank, Bag and PC at once (SELECT cycles, on Gen 2, Left/Right filters by pocket). Picking an item offers TO BANK/BAG/PC, SWITCH (Bag only) or TOSS. **START** withdraws (from BANK) or deposits (from Bag/PC) every currently visible item at once, after confirming. The highlighted item's own description shows under the list on Gen 2.

**TMs go through the MOVES tab instead.** MOVE ITEM refuses one with a message pointing you there. With the MOVES tab turned off, that rule drops too (whatever's already banked as a move stays there regardless). A TM already in the Bank still withdraws normally either way. Everything else deposits freely, with no limit on distinct item stacks.

### MOVES

A TM you deposit here is banked as the move it teaches (or adds a use to one already banked) instead of taking up an item slot; withdrawing turns a banked use back into the matching TM item.

Selecting **MOVES** opens **MANAGE MOVES** directly when there's nothing to RELEARN right now (see below); otherwise it offers the choice between the two.

- **MANAGE MOVES** browses BANK, BAG and PC at once (SELECT cycles, Left/Right filters by type); BAG and PC each list their own TM stacks (never HMs) by the move each one teaches, not its own item name. Picking a move offers **TEACH** (only when a banked use of it actually exists -- spends it directly on a Pokémon, no TM needed, marked **ABLE** or **---** by every way it or a prevolution could ever know that move, not just by TM; already knowing it, or not being able to learn it, refuses it without spending the use; with [Infinite Tms](https://github.com/bastinjul/infinite_tms) / [Reusable Machines](https://github.com/FAFF0x/gen1recomp) / [Reusable Machines - Gen 2](https://github.com/FAFF0x/gen2recomp) installed a successful TEACH doesn't spend the use either), **WITHDRAW** (BANK, as that many TMs to your Bag, refused if it has no room) or **DEPOSIT** (BAG/PC, as that many banked uses), **TOSS** (discards a quantity for good, after confirming) and **CANCEL**. **START** withdraws (BANK) or deposits (BAG/PC) every currently visible move at once, after confirming.
- **RELEARN MOVE** recovers a move that couldn't fill itself back in automatically because the Pokémon's moveset was already full. It only shows up when there's one like that to bring back. Doesn't touch the Bank's own move stock.

### MONEY

Selecting **MONEY** already shows your own MONEY and the Bank's BANK balance in a box under DEPOSIT MONEY/WITHDRAW MONEY/CANCEL, before picking either one.

- **DEPOSIT MONEY** opens an amount box showing the same two balances (Up/Down cycles the digit, Left/Right moves the cursor, START jumps to the max, A confirms, B cancels), capped by how much you're carrying.
- **WITHDRAW MONEY** opens the same amount box, capped by both the Bank's own balance and how much room is left before your money would hit the game's own ¥999999 cap.

### LINK

Sends Pokémon, items, moves and money straight from your Bank to another player's, over the same LAN peer-to-peer connection or public relay the game's own **LINK CABLE** uses. Opening it asks to save the game first (defaulting to YES) -- a connection like this is exactly the kind of thing worth having a fresh save behind before it starts.

1. Pick **LAN** or **ONLINE**. Under **LAN**, **HOST** shows the address for the other player to type in under **JOIN**. Under **ONLINE**, **HOST** shows a 6-character code for the other player to type in under **JOIN**, no shared network needed. Either way, both sides need the exact same LINK version and BANK data version, and so is linking to yourself (the same OT id **and** OT name or the same Bank, since each one carries its own persistent id).
2. Build what you're sending: **POKéMON**, **TIME CAPS.**, **ITEMS** and **MOVES**, and on all four **START asks to send (or take back) everything currently visible** in one go. POKéMON's own BANK side still flips boxes with Left/Right. ITEMS and MOVES also work like their own BANK tabs here: Left/Right cycles pockets/types. **LOST** works the same way over whatever your own Bank has quarantined. **MONEY** shows your staged **SEND** total and the Bank's own **BANK** balance before offering **SEND MONEY**/**TAKE BACK**, same as the Bank's own MONEY tab shows MONEY/BANK before DEPOSIT/WITHDRAW. A running summary sits next to the menu the whole time. **CONFIRM** shows the same summary in full and waits for the other player to confirm too.
3. Once both sides confirm, each one's parcel is on its way: review what's arriving (**POKéMON**/**TIME CAPS.**/**ITEMS**/**MOVES**/**MONEY**, read-only), already checked against your own game, anything it doesn't recognize shows up under **LOST** instead of the normal rows, exactly like **VIEW LOST**. **CONFIRM** again, **GO BACK** to step 2.
4. Once both sides confirm the second time, it all lands in your Bank for good -- whatever was under **LOST** goes straight into the Bank's own quarantine, same as anything a save-load sets aside -- and the game saves immediately.

**Closing the game mid-session does the same as CANCEL**. Whatever you'd set aside is refunded.

**This isn't a trade.** LINK moves Pokémon straight from one Bank to another, not between two parties the way the game's own trade does -- so a Pokémon that evolves by trading **won't evolve** just from crossing over this way. That's intentional.

## Options

LABEL|CHOICES|DEFAULT|DESCRIPTION|
-|-|-|-
SHOW IN PC MENU|NONE / START / MIDDLE / END|END|Where the **POKéMON BANK** row sits on the PC menu: **NONE** hides it, **START** is the very top, **MIDDLE** sits right below BILL's PC, **END** sits right below the player's PC.
POKéMON MENU*|ON / OFF|ON|Turns the POKéMON tab on or off.
ITEMS MENU*|ON / OFF|ON|Turns the ITEMS tab on or off.
MOVES MENU*|ON / OFF|ON|Turns the MOVES tab on or off.
MONEY MENU*|ON / OFF|ON|Turns the MONEY tab on or off.
LINK MENU*|ON / OFF|ON|Turns the LINK tab on or off.
BOX SIZE|20 / 30 / NO LIMIT|20|How many Pokémon a box holds.
DELETE EMPTY BOX|ALL / UNNAMED / NEVER|UNNAMED|When an emptied-out box is removed automatically.
INHERIT TRAINER|ON / OFF|OFF|Makes every withdrawn Pokémon become yours (OT, OT ID and OT name).
LEGALITY CHECKS|OFF / FIX / FORCE FIX / REJECT|OFF|Whether withdrawing a Pokémon whose level/exp, DVs, Stat Exp, moves, held item, catch rate, (Gen 2) gender or shininess couldn't have arisen from legitimate play is left alone, corrected (after asking, or immediately under FORCE FIX), or refused outright -- see below.
STORAGE MODE|BANK / TIME CAPSULE / BOTH|BANK|Which storage the POKéMON tab opens -- see above.
AUTO HEAL|NEVER / ON DEPOSIT / ON WITHDRAW / AT POKéMON CENTER|NEVER|Fully heals a Pokémon at the chosen moment (**AT POKéMON CENTER** heals the whole Bank).
REPORT MODE|NONE / MESSAGE / FULL|FULL|Controls how you're notified when a load moves anything to or from quarantine (**FULL** shows the REPORT screen).

*\* With two or more on, the row opens a chooser listing just the enabled ones, as above. With only one on, the row skips the chooser and opens that side directly. With all off, the row doesn't appear at all, same as setting **SHOW IN PC MENU** to **NONE**.*

These options are also exposed through the manifest's `options_schema`, so a native launcher can list and edit them before starting the game.

### LEGALITY CHECKS

This checks whether a Pokémon could withdraw straight into the game you're **currently playing** -- every comparison below is against that game's own data, never whichever game the Pokémon was originally deposited from. **OFF** doesn't check any of it. **REJECT** refuses a Pokémon that fails any check below, and it stays in the Bank. **FIX** asks first (**"This Pokémon needs to be fixed. OK?"**, once for a single withdraw, once for the whole batch on a bulk one) and, only if you agree, applies the fix in that same row before letting it leave. **FORCE FIX** applies the exact same fixes, without asking:

CHECK|FIX
-|-
Level 1-100, and consistent with its own EXP for its growth curve.|Recomputed off its own EXP; clamped into 1-100 instead when there's no EXP to compare against.
Every DV (0-15) in range, including the HP DV matching the other four's own low bits.|Clamped into range; the HP DV is rederived from the other four's own bits.
Every Stat Exp (0-65535) in range, plus, on Gen 2, the five combined (0-65535) too.|Clamped into range; on Gen 2, if the combined total is still over the cap, all five are scaled down proportionally.
1 to 4 moves, no duplicates, each one learnable (by level-up, TM/HM, or, on Gen 2, an egg move) by its own species or any species it evolved from, **checked against the game you're currently playing**. On a withdraw across generations, this is checked against the *destination* game's own learnsets, which can genuinely differ from the origin game's for the same species and move.|A duplicate or unlearnable move is dropped, not swapped for a different one; anything past the first 4 that still fit is truncated. **Not fixable** if nothing learnable is left.
PP Ups (0-3, or Gen 2's equivalent max PP) in range for each move.|Recomputed to the nearest valid step for whatever PP Ups it actually has.
Its held item, if any, is one that could actually be held: on Gen 2, not a key item and not flagged as never tossable; with CRYSTAL_251 installed, not mail, a key item, a badge or a machine either.|Removed.
On Gen 1: its catch rate matches its own species or any species it evolved from -- evolving never updates it, so an evolved Pokémon legitimately keeps whichever catch rate it had at the moment it was actually caught.|Reset to its own current species' catch rate.
On Gen 2: its gender matches what its own DVs and species gender ratio produce -- or, with CRYSTAL_251 installed, what its own DVs produce under CRYSTAL_251's own (different) gender formula, since that's the one that actually rolled it back when it was still a Gen 1 Pokémon.|Rederived straight off its own DVs, unless it already matches CRYSTAL_251's own formula, which is left alone.
On Gen 2: its shininess matches what its own DVs produce.|Rederived straight off its own DVs -- can only ever turn an unearned shiny off, never on, since going the other way would mean altering the DVs it's derived from too.
An Egg (Gen 2, or Gen 1 with CRYSTAL_251 installed): its species can actually produce one, and every move it knows is one it could plausibly have inherited (an Egg move, a TM/HM move, or, with CRYSTAL_251, one of its own inheritable moves).|An uninheritable move is dropped. **Not fixable** if the species can't produce an Egg at all -- level/EXP, DVs, Stat Exp, catch rate and gender aren't checked (or fixed) on an Egg either way, none of them mean the same thing yet.

Evolutions that require a trade are not checked at all -- the Bank has no way to tell a legitimate one from a hacked one either way.

If what's left still isn't legal after every fix above (a **Not fixable** row, most commonly), nothing is applied at all and the Pokémon stays in the Bank exactly as it was, the same as **REJECT**.

### Game OPTIONS menu

The game's own **OPTIONS** menu has a **POKéMON BANK** row: it opens a page with every option above, followed by:
LABEL|DESCRIPTION
-|-
VIEW STATS|Shows a running log of everything the Bank has ever handled. SELECT switches between all-time totals and just this save's own contribution.
VIEW LOST|Browses whatever's currently quarantined (Pokémon, items and banked moves the active game doesn't recognize right now). SELECT cycles between the three lists.
RESTORE DATA\*|Rolls the Bank back to its last backup (see **Where the data lives**), after confirming.
DELETE DATA\*|Erases the Bank entirely and asks **twice** first, since it can't be undone. Each save's own stats are untouched, since they live in the save, not the Bank.

*\* Takes effect on disk immediately.*

A mod built on top of the Bank can add its own row to this same page (opening its own options list, same look, rather than merging its rows into the ones above) through `registerOptionsPanel` -- see [API.md](./API.md).

## Where the data lives

`bank/storage.lua`, written next to `saves` directory. It is never written into, or read from, `save.modData`, so no save slot carries a copy of it and no save can overwrite it.

The Bank's all-time stats (**VIEW STATS** above) follow the exact same rule, in their own file next to it, `bank/stats.lua`. Only the "THIS SAVE" half of that screen is the exception: it's written into `save.modData` on purpose, since it's meant to travel and rewind with that one save rather than the shared Bank.

**It's written on the same schedule as your save file.** A Bank transaction only changes things in memory; the actual write to `storage.lua` happens alongside the next time the game itself saves (a manual SAVE, an autosave mod, anything that reaches `Game:writeSave`). This is deliberate: if the Bank wrote immediately, resetting without saving after a deposit would leave you with the Pokémon both in the Bank *and* back in your unsaved party. Waiting for the same save point the game already uses means a reset always reverts both together, so nothing can be duplicated or lost that way. Before writing, the previous `storage.lua` rolls into `storage.lua.bak` and the new one stages as `storage.lua.tmp` before the swap (the same backup-and-staged-write discipline the game's own save files use) so a crash mid-write leaves a recoverable copy instead of a half-written file.

**After you load a save**, the Bank checks every stored Pokémon, item and banked move against the active game's data -- TIME CAPSULE's own contents included. A Pokémon whose *species* is unknown or an Egg on a Gen 1 save without CRYSTAL_251 is set aside in an internal invalid list (not shown in the normal WITHDRAW lists, but browsable any time through **VIEW LOST**); an item whose id is unknown is set aside the same way, and so is an HM or key item found in storage (they can never be deposited going forward, but this catches ones that ended up there some other way); a banked move id this game version doesn't recognize *at all* (a different version, or the mod that added it removed) is set aside too. If something that was invalid becomes valid again it is moved back automatically (Pokémon go to the end of the last box, or straight back into TIME CAPSULE for one of its own); an HM or key item stays set aside even then, since it's still not allowed in the Bank.

**A Pokémon whose *moveset* includes an unknown move is treated differently:** only that move is set aside, every other move it knows stays right where it was, and so does the Pokémon itself. Once a set-aside move is valid again, it fills back into an empty slot on its own, on the next load, for that specific Pokémon wherever it ends up (the Bank, your party, a PC box); if its moveset was already full at that point, it stays waiting there until you bring it back yourself with **RELEARN MOVE** on the MOVES tab.

## For mod authors

Pokémon Bank is fully independent and exposes everything it does through `mod.exports`: deposit, withdraw and query every side of the Bank -- Pokémon (including bulk party/PC transfers), items, banked moves and money -- push straight to any tab's own screen or the same chooser the PC's own **POKéMON BANK** row opens, reuse the same BANK/PARTY-or-BAG/PC browsing screens (**Pickers**) TEACH MOVE and RELEARN MOVE are themselves built on, and listen for an event on every deposit, withdraw, release, teach or transfer -- whether it happened through this mod's own UI or through the exports themselves. See [API.md](./API.md) for the full reference.
