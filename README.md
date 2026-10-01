# Pokémon Bank

A second storage for Pokémon, items, moves and money that lives **outside every save file**. Deposit a Pokémon, an item, a move or money while playing one save and withdraw it while playing a completely different one, any gen, any slot. The Bank is its own file, so New Game, deleting a save slot or switching versions never touches it.

## How to use it

Open any Pokémon Center PC and select **POKéMON BANK**. Seven tabs:

### POKéMON

The **POKéMON** tab only appears once you've got the **POKéDEX**.

#### POKéMON MANAGER

Browses BANK, PARTY and PC at once (SELECT cycles).

**Crossing generations just works.** A Pokémon's stats and status translate whichever way you cross. The mod also loads on Gen 3. Every Pokémon in the Bank carries a personality value, like the real Gen 3 games, chosen so its gender and shininess stay as they were; it also carries its original trainer's Secret ID and its species. Your trainer gets a Secret ID if the save has none. **An Egg crosses generations too**, hatch timer and moves intact between Gen 2 and a Gen 1 save with [CRYSTAL 251](https://github.com/Deftones565/gen1recomp-mod-crystal-251) or [Kanto Reforged](https://github.com/1Jamie/Kanto-Reforged). Elsewhere it's set aside until viewed from a game that supports it (see **Where the data lives**). It **always** becomes yours the moment you withdraw it.

**Withdrawing a Pokémon registers it in your Pokédex** if it wasn't already seen or owned.

*\* With Kanto Reforged, a Pokémon's ability can change when it goes to Gen 3: Kanto Reforged gives every Pokémon of a species the same ability, while on Gen 3 it's the one its personality value picks out of the two its species can have.*

##### MENU ACTIONS

- **MOVE** Moves Pokémon between slots. A drops it in its new spot, B puts it back where it was.
- **TRANSFER** Send Pokémon to another container.
- **STATS** Opens Pokémon Summary.
- **RELEARN** Allow to Relearn lost moves (only while it has a move waiting to come back, see **MOVES**)
- **ITEM** Take off item and stores into BANK/BAG/PC (only while it holds one)
- **RELEASE**

##### START ACTIONS

- **TRANSFER** Send whole box/party to another container.
- **BOXES** Opens **BOX MANAGER**.
- **ITEMS** Take off all box/party held items and stores into BANK/BAG/PC.
- **LIST/GRID VIEW** Toggles view mode.

#### BOX MANAGER

Browses BANK and PC at once (SELECT cycles), showing a small square marking the current one. Boxes in grid view show a small mark in the bottom-right corner when they hold at least one Pokémon; the mark changes color when the box is full.

**A box holds up to 30 Pokémon by default.** A full box grows another one instead of ever refusing a Pokémon. An emptied-out box is removed automatically depending on the DELETE EMPTY BOX option.

##### MENU ACTIONS

- **MOVE** Swap two boxes. A drops it in its new spot, B puts it back where it was.
- **VIEW** Opens **POKéMON MANAGER** on selected box/party.
- **CHANGE** Sets box as selected box.
- **TRANSFER** Send all Pokémon to another box.
- **RENAME** Renames the box (a blank name reverts it to default).
- **DELETE** Deletes an empty box (BANK only).

##### START ACTIONS

- **LIST/GRID VIEW** Toggles view mode.

### TIME CAPSULE

**TIME CAPSULE**, like POKéMON, only appears once you've got the **POKéDEX**. It is its own separate storage, a flat list with no boxes, and its own tab -- a separate entry from POKéMON, with its own SHOW/HIDE option below.

Lists the capsule's own contents directly, same screen as **POKéMON MANAGER** but as plain lists -- SELECT cycles through **TIME CAPSULE** / **BANK** / **PARTY** / **PC**, all four right there instead of a separate DEPOSIT/WITHDRAW picker.

**It only ever moves a Pokémon forward**: from an earlier generation's save into a later one, never back, mirroring the real Time Capsule's own one-way rule. That same generation floor still applies even after a Pokémon leaves the capsule and drifts back into the general Bank.

A Pokémon that's eligible by generation still needs its species and every one of its moves to actually exist in the game you're withdrawing into. One that clears everything and isn't already holding an item picks up a held item on arrival:

- **Gen 2**: always, the same species-by-catch-rate item the real Time Capsule assigns to a Gen 1 Pokémon.
- **FireRed**: a Gen 1 Pokémon that goes straight there gets the FireRed counterpart of that same item (a BERRY becomes an ORAN BERRY, GOLD BERRY a SITRUS BERRY, and so on). One whose item doesn't exist in Gen 3 (SILVER LEAF, POLKADOT BOW, a Gen 2 TM...), or one sent from Gen 2, gets the item its species can hold in the wild on FireRed instead: the common one, or the rare one if it has no common one. A species with neither arrives empty-handed.

What comes out on Gen 3 is marked as a **fateful encounter** (met location 255), and its stats, moves, IVs and EVs are worked out the way any Pokémon crossing into Gen 3 gets them.

#### MENU ACTIONS

On **BANK**/**PARTY**/**PC**:

- **TO TIME CAPSULE** Sends the Pokémon into the capsule. Refused if it's an Egg, if it's holding an item (remove it first), or if it was caught in a later generation than the one you're playing; nothing at all can go in while you're playing the highest generation this project currently supports, since there's nowhere further for anything to go from there.
- **STATS** Opens Pokémon Summary.

On **TIME CAPSULE**:

- **TO BANK** Hidden while the **POKéMON MENU** tab is off.
- **TO PARTY**
- **TO PC**
- **STATS** Opens Pokémon Summary.
- **RELEASE**

#### START ACTIONS

On **TIME CAPSULE**:

- **TO BANK/PARTY/PC** Moves every Pokémon currently visible in the capsule at once to whichever of BANK/PARTY/PC you choose. Only the ones actually eligible right now move (a mon that isn't eligible yet, or needs LEGALITY CHECKS' FIX confirmation, is simply skipped rather than asked about individually), with the same collapsing TRANSFER confirmation **POKéMON MANAGER**'s own bulk moves use.

### ITEMS

Browses the Bank, Bag and PC at once (SELECT cycles, Left/Right filters by pocket). Gen 1 has a single bag, so its items are sorted into Gen 2's pockets: ITEMS, BALLS, KEY ITEMS and TM/HM. The highlighted item's own description shows under the list on Gen 2.

**TMs go through the MOVES tab instead.** MOVE ITEM refuses one with a message pointing you there. With the MOVES tab turned off, that rule drops too (whatever's already banked as a move stays there regardless). A TM already in the Bank still withdraws normally either way. Everything else deposits freely, with no limit on distinct item stacks.

#### MENU ACTIONS

- **MOVE** Shifts an item within its pocket (Bag only, and only while filtered to one specific pocket, not ALL). Up/Down moves it, A drops it in its new spot, B puts it back where it was.
- **TO BANK/BAG/PC** Send the item to another container.
- **TOSS**

#### START ACTIONS

- **TRANSFER** Withdraws (from BANK) or deposits (from Bag/PC) every currently visible item at once, after confirming.
- **POCKETS** Lists every pocket with how many items it holds.
- **LIST/GRID VIEW** Toggles view mode (FireRed only; Gen 1 and Gen 2 have no item icons, so they always show the list). **GRID VIEW** shows the items as a grid of 6 per row by the Bag's own icons (Left/Right past a row's edge flips the pocket; the highlighted item's name and count show under it instead of its description). **LIST VIEW** goes back to the list, which is the default; the choice is kept per save.

### MOVES

A TM you deposit here is banked as the move it teaches (or adds a use to one already banked) instead of taking up an item slot; withdrawing turns a banked use back into the matching TM item.

Browses BANK, BAG and PC at once (SELECT cycles, Left/Right filters by type). BAG and PC each list their own TM stacks (never HMs) by the move each one teaches, not its own item name.

A move that couldn't fill itself back in automatically, because the Pokémon's moveset was already full, waits for that Pokémon: in **POKéMON MANAGER**, picking it (in the BANK, your party or the PC) offers **RELEARN**, only while it has one like that to bring back. It doesn't touch the Bank's own move stock.

#### MENU ACTIONS

- **TEACH** Only when a banked use of the move actually exists. Spends it directly on a Pokémon, no TM needed, marked **ABLE** or **---** by every way it or a prevolution could ever know that move, not just by TM; already knowing it, or not being able to learn it, refuses it without spending the use. With [Infinite Tms](https://github.com/bastinjul/infinite_tms) / [Reusable Machines](https://github.com/FAFF0x/gen1recomp) / [Reusable Machines - Gen 2](https://github.com/FAFF0x/gen2recomp) / [Reusable Machines - Gen 3](https://github.com/FAFF0x/gen3recomp) installed a successful TEACH doesn't spend the use either.
- **WITHDRAW** (BANK) Moves that many TMs to your Bag, refused if it has no room.
- **DEPOSIT** (BAG/PC) Banks that many uses.
- **TOSS** Discards a quantity for good, after confirming.
- **CANCEL**

#### START ACTIONS

- **TRANSFER** Withdraws (BANK) or deposits (BAG/PC) every currently visible move at once, after confirming.
- **TYPES** Lists every type with how many moves it holds.

### MONEY

Selecting **MONEY** already shows your own MONEY and the Bank's BANK balance in a box under DEPOSIT MONEY/WITHDRAW MONEY/CANCEL, before picking either one.

- **DEPOSIT MONEY** opens an amount box showing the same two balances (Up/Down cycles the digit, Left/Right moves the cursor, START jumps to the max, A confirms, B cancels), capped by how much you're carrying.
- **WITHDRAW MONEY** opens the same amount box, capped by both the Bank's own balance and how much room is left before your money would hit the game's own ¥999999 cap.

### COINS

The **COINS** tab only appears once you've got the **COIN CASE** (Celadon City on Gen 1 and FireRed/LeafGreen, Goldenrod City on Gen 2).

Selecting **COINS** already shows your own COINS and the Bank's BANK balance in a box under DEPOSIT COINS/WITHDRAW COINS/CANCEL, before picking either one.

- **DEPOSIT COINS** opens an amount box showing the same two balances (Up/Down cycles the digit, Left/Right moves the cursor, START jumps to the max, A confirms, B cancels), capped by how much you're carrying.
- **WITHDRAW COINS** opens the same amount box, capped by both the Bank's own balance and how much room is left before your coin case would hit the game's own 9999 cap.

### LINK

Sends Pokémon, items, moves and money straight from your Bank to another player's, over the same LAN peer-to-peer connection or public relay the game's own **LINK CABLE** uses. Opening it asks to save the game first (defaulting to YES) -- a connection like this is exactly the kind of thing worth having a fresh save behind before it starts.

1. Pick **LAN** or **ONLINE**. Under **LAN**, **HOST** shows the address for the other player to type in under **JOIN**. Under **ONLINE**, **HOST** shows a 6-character code for the other player to type in under **JOIN**, no shared network needed. Either way, both sides need the exact same LINK version, and linking to yourself is refused (the same OT id **and** OT name or the same Bank, since each one carries its own persistent id).
2. Build what you're sending: every part of the Bank has its own row (**POKéMON**, **ITEMS**, **MOVES**, **MONEY**, **COINS**; the **TIME CAPSULE** stays out of LINK), followed by any storage another mod registered (see **Storage from other mods**), right before **LOST**. On the lists, **START asks to send (or take back) everything currently visible** in one go; POKéMON flips boxes with Left/Right and opens on the current box, and its Pokémon show their level and offer **STATS**. **LOST** works the same way over whatever your own Bank has quarantined. **MONEY** shows your staged **SEND** total and the Bank's own **BANK** balance before offering **SEND**/**TAKE BACK**, same as the Bank's own MONEY tab shows MONEY/BANK before DEPOSIT/WITHDRAW; **COINS** works the same way for casino coins. A row this save hasn't unlocked yet (POKéMON before the POKéDEX, COINS before the COIN CASE, another mod's storage before its own condition) says so instead of opening; what the other player sends you under it still shows in step 3. A running summary of what's staged (only what isn't zero) sits next to the menu the whole time. **CONFIRM** lists everything that's actually moving (Up/Down scroll it when it doesn't fit) and waits for the other player to confirm too.
3. Once both sides confirm, each one's parcel is on its way: review what's arriving under the same rows (read-only), already checked against your own game, anything it doesn't recognize shows up under **LOST** instead of the normal rows, exactly like **VIEW LOST**. **CONFIRM** again, **GO BACK** to step 2.
4. Once both sides confirm the second time, it all lands in your Bank for good -- whatever was under **LOST** goes straight into the Bank's own quarantine, same as anything a save-load sets aside -- and the game saves immediately.

**Closing the game mid-session does the same as CANCEL**. Whatever you'd set aside is refunded.

**This isn't a trade.** LINK moves Pokémon straight from one Bank to another, not between two parties the way the game's own trade does -- so a Pokémon that evolves by trading **won't evolve** just from crossing over this way. That's intentional.

## Options

LABEL|CHOICES|DEFAULT|DESCRIPTION|
-|-|-|-
SHOW IN PC MENU|NONE / START / MIDDLE / END|END|Where the **POKéMON BANK** row sits on the PC menu: **NONE** hides it, **START** is the very top, **MIDDLE** sits right below BILL's PC, **END** sits right below the player's PC.
POKéMON MENU*|ON / OFF|ON|Turns the POKéMON tab on or off.
TIME CAPSULE MENU*|ON / OFF|ON|Turns the TIME CAPSULE tab on or off, independent of POKéMON.
ITEMS MENU*|ON / OFF|ON|Turns the ITEMS tab on or off.
MOVES MENU*|ON / OFF|ON|Turns the MOVES tab on or off.
MONEY MENU*|ON / OFF|ON|Turns the MONEY tab on or off.
COINS MENU*|ON / OFF|ON|Turns the COINS tab on or off.
LINK MENU*|ON / OFF|ON|Turns the LINK tab on or off.
BOX SIZE|20 / 30 / 50 / 100 / NO LIMIT|30|How many Pokémon a box holds.
DELETE EMPTY BOX|ALL / UNNAMED / NEVER|UNNAMED|When an emptied-out box is removed automatically.
INHERIT TRAINER|ON / OFF|OFF|Makes every withdrawn Pokémon become yours (OT, OT ID and OT name).
LEGALITY CHECKS|OFF / FIX / FORCE FIX / REJECT|OFF|Whether withdrawing a Pokémon whose level/exp, DVs, Stat Exp, moves, held item, catch rate, (Gen 2) gender or shininess couldn't have arisen from legitimate play is left alone, corrected (after asking, or immediately under FORCE FIX), or refused outright -- see below.
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
An Egg (Gen 2, or Gen 1 with CRYSTAL_251 or Kanto-Reforged installed): its species can actually produce one, and every move it knows is one it could plausibly have inherited (an Egg move (Kanto-Reforged's own on Gen 1), a TM/HM move, or, with CRYSTAL_251, one of its own inheritable moves).|An uninheritable move is dropped. **Not fixable** if the species can't produce an Egg at all -- level/EXP, DVs, Stat Exp, catch rate and gender aren't checked (or fixed) on an Egg either way, none of them mean the same thing yet.

**On FireRed (Gen 3)** the checks are its own, against the game's own tables, and **FIX**/**FORCE FIX** apply where a row has a fix:

CHECK|FIX
-|-
The species exists in Gen 3 and, only until the National Dex is unlocked, is a Kanto one.|Not fixable.
Level 1-100, inside the range its EXP gives for its growth rate.|Recomputed off its EXP.
Every IV (0-31) in range; for a Pokémon met in an earlier generation, its HP IV is the one its other IVs give (as its HP DV was).|Clamped into range; the HP IV rederived from the others.
Every EV (0-255) in range and 510 in all.|Clamped into range; if the total is still over 510, all are scaled down together.
Its nature, ability and gender are the ones its personality value gives, and it is shiny only if that value says so.|Derived again from the personality value.
Its personality value goes with its IVs: Gen 3 draws both from the same run of the random generator (methods 1, 2 and 4). Not checked on a Pokémon marked when its personality value was made: a shiny from an earlier generation (its value can't come from that run), one with no candidate that fits its other traits, and the red GYARADOS of the LAKE OF RAGE caught on Gen 2.|Not fixable.
1 to 4 moves, no repeats, each one learnable (by level-up or TM/HM, of its species or one it evolved from). Egg moves are not accepted.|A repeated or unlearnable move is dropped. **Not fixable** if none is left.
Each move's PP is at most its maximum, and that is its base PP plus 0-3 PP Ups.|Recomputed to the nearest valid step.
Its ball is one of Gen 3's (not the DIVE BALL or PREMIER BALL) and its met level is not above its level.|A POKé BALL; the met level limited.
A fateful encounter location (255) comes with the fateful encounter flag. Not checked on a Pokémon met in an earlier generation, unless it went through the TIME CAPSULE (which sets the flag).|The flag is set.
HP not above its maximum; friendship and Pokérus in 0-255.|Limited.
Its held item is not a key item, a machine or anything else the game marks as not holdable.|Removed.
An Egg: only its species, hatch counter and ball.|Ball as above.

Evolutions that require a trade are not checked at all -- the Bank has no way to tell a legitimate one from a hacked one either way.

If what's left still isn't legal after every fix above (a **Not fixable** row, most commonly), nothing is applied at all and the Pokémon stays in the Bank exactly as it was, the same as **REJECT**.

### Game OPTIONS menu

The game's own **OPTIONS** menu has a **POKéMON BANK** row, right before MODS, in each game's own style: just the name on Gen 1, `:OPEN` next to it on Gen 2, and how many options it holds (`N OPTIONS`) on FireRed, like its own option groups. It opens a page with every option above, followed by:
LABEL|DESCRIPTION
-|-
VIEW STATS|Shows a running log of everything the Bank has ever handled, one page per part (POKéMON, TIME CAPSULE, ITEMS, MOVES, MONEY, COINS, plus one for each part of another mod's storage). Every page counts the actions (deposits, withdrawals and, once anything was removed, removals), the LINK exchanges it took part in and what it sent and received; items, moves, money and coins also count how many units, and money and coins their highest balance. The BANK side adds the most deposited Pokémon and the moves taught. Left/Right flips between pages; SELECT switches between all-time totals (BANK) and just this save's own contribution (PLAYER).
VIEW LOST|Browses whatever's currently quarantined (Pokémon, items and banked moves the active game doesn't recognize right now). Left/Right switches between storages once another mod has registered one.
RESTORE DATA\*|Rolls the Bank back to its last backup (see **Where the data lives**), after confirming. Every storage another mod registered is rolled back to its own backup too, but their statistics never are.
DELETE DATA\*|Erases the Bank entirely, including every storage another mod registered, and asks **twice** first, since it can't be undone. Each save's own stats are untouched, since they live in the save, not the Bank.

*\* Takes effect on disk immediately.*

A mod built on top of the Bank can add its own row to this same page (opening its own options list, same look, rather than merging its rows into the ones above) through `registerOptionsPanel` -- see [API.md](./API.md).

## Where the data lives

`bank/storage.lua`, written next to `saves` directory. It is never written into, or read from, `save.modData`, so no save slot carries a copy of it and no save can overwrite it.

The Bank's all-time stats (**VIEW STATS** above) follow the exact same rule, in their own file next to it, `bank/stats.lua`. Only the "THIS SAVE" half of that screen is the exception: it's written into `save.modData` on purpose, since it's meant to travel and rewind with that one save rather than the shared Bank.

**It's written on the same schedule as your save file.** A Bank transaction only changes things in memory; the actual write to `storage.lua` happens alongside the next time the game itself saves (a manual SAVE, an autosave mod, anything that reaches `Game:writeSave`). This is deliberate: if the Bank wrote immediately, resetting without saving after a deposit would leave you with the Pokémon both in the Bank *and* back in your unsaved party. Waiting for the same save point the game already uses means a reset always reverts both together, so nothing can be duplicated or lost that way. Before writing, the previous `storage.lua` rolls into `storage.lua.bak` and the new one stages as `storage.lua.tmp` before the swap (the same backup-and-staged-write discipline the game's own save files use) so a crash mid-write leaves a recoverable copy instead of a half-written file.

**After you load a save**, the Bank checks every stored Pokémon, item and banked move against the active game's data -- TIME CAPSULE's own contents included. A Pokémon whose *species* is unknown or an Egg on a Gen 1 save without CRYSTAL_251 or Kanto-Reforged is set aside in an internal invalid list (not shown in the normal WITHDRAW lists, but browsable any time through **VIEW LOST**); an item whose id is unknown is set aside the same way, and so is an HM or key item found in storage (they can never be deposited going forward, but this catches ones that ended up there some other way); a banked move id this game version doesn't recognize *at all* (a different version, or the mod that added it removed) is set aside too. If something that was invalid becomes valid again it is moved back automatically (Pokémon go to the end of the last box, or straight back into TIME CAPSULE for one of its own); an HM or key item stays set aside even then, since it's still not allowed in the Bank.

**A Pokémon whose *moveset* includes an unknown move is treated differently:** only that move is set aside, every other move it knows stays right where it was, and so does the Pokémon itself. Once a set-aside move is valid again, it fills back into an empty slot on its own, on the next load, for that specific Pokémon wherever it ends up (the Bank, your party, a PC box); if its moveset was already full at that point, it stays waiting there until you bring it back yourself with **RELEARN** in **POKéMON** (see **MOVES**).

## Storage from other mods

A mod can register its own storage inside the Bank: an amount, a list, a map of quantities, or named containers of either. It keeps the Bank's own habits:

- **Its own files.** Each storage is written to `bank/<mod id>_storage.lua` and `bank/<mod id>_stats.lua`, on the same schedule and with the same backup as `storage.lua`. **DELETE DATA** erases them along with everything else, and **RESTORE DATA** rolls each storage back to its own backup (never the statistics files).
- **A tab toggle.** The OPTIONS page gets a SHOW/HIDE toggle for each storage, so it can be hidden like the built-in tabs.
- **A row on the BANK menu.** Right after the built-in tabs (POKéMON, TIME CAPSULE, ITEMS, MOVES, MONEY, COINS) and before LINK, with its own SHOW/HIDE option; a storage can also give each of its parts a row (and an option) of its own, like the built-in tabs.
- **Its own checks when a save loads.** Each part checks what it holds against the game just loaded and sets aside (in **LOST**) what that game doesn't recognize, like the Bank's own tabs.
- **LINK.** Every storage gets its own row in the SEND and RECEIVE menus, chosen by what it holds (an amount box, an item-style picker or a list picker). Anything the other player can't use goes to **LOST**, and everything is refunded if the transfer is cancelled.
- **A different data version doesn't break LINK.** If the two players have different versions of one storage, or only one of them has it, just that storage's row is unavailable and shows why; everything else keeps working.
- **LOST and VIEW STATS.** **VIEW LOST** and LINK's LOST list get one page per storage. **VIEW STATS** gets a page for each part of a storage with the same statistics as the built-in ones (LINK ones only if it takes part in LINK), plus whatever extra statistics its mod adds.

## For mod authors

Pokémon Bank is fully independent and exposes everything it does through `mod.exports`: deposit, withdraw and query every side of the Bank -- Pokémon (including bulk party/PC transfers), items, banked moves and money -- push straight to any tab's own screen or the same chooser the PC's own **POKéMON BANK** row opens, reuse the same BANK/PARTY-or-BAG/PC browsing screens (**Pickers**) TEACH MOVE and RELEARN MOVE are themselves built on, register your own storage next to the Bank's (with its own files, statistics, LINK support and screen), and listen for an event on every deposit, withdraw, release, teach or transfer -- whether it happened through this mod's own UI or through the exports themselves. See [API.md](./API.md) for the full reference.
