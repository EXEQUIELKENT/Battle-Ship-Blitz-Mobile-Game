# POWER PLAY — card reference

POWER PLAY is a hotspot/online battle mode: turn-based, same flow as TURN
BASED (land a hit and you fire again, miss and the guns pass to your
opponent), but every turn you may be holding one random power-up.

- You draw a card automatically the moment your turn starts, **only if
  your hand is empty** — you never hold more than one at a time.
- Spend it whenever you like during your turn: before you fire, instead
  of firing, or not at all.
- A card that needs a target (see the table) puts the grid into a
  "pick a cell" state when you tap it — the right grid lights up (your
  own, for the two mine cards; the enemy's, for everything else) and a
  banner shows how many cells it still needs, with a tap-to-cancel to
  back out without spending the card.
- The deck is weighted by rarity: **common** cards come up most often,
  **rare** cards least. The full weights are in
  [`lib/models/power_up.dart`](../lib/models/power_up.dart).

Card names, descriptions and rarities below are the source of truth in
the app itself; the "how it actually plays" notes are the mechanics
behind each one.

---

## Common

| Card | What it does |
|---|---|
| **SONAR** | Pick a cell on the enemy grid — get back how many *distinct* ships have any part inside the 3×3 area centred on it. A count only, never positions. |
| **SPOTTER** | No target needed. Reveals one random cell that genuinely holds an enemy hull. Marks it; doesn't fire. |
| **RECON SWEEP** | Pick a row on the enemy grid — get back a yes/no for whether that row holds any ship at all. |
| **DOUBLE TAP** | No target needed — arms your very next shot. If that shot misses, your turn does **not** pass; a hit was never going to pass it anyway. |
| **REPAIR** | No target needed. Undoes one hit on your own **most-damaged** hull that isn't already sunk. Does nothing (and isn't spent) if nothing is eligible. |
| **JAM** | No target needed. Your opponent draws no card on their very next turn — one turn only. |
| **SPRAY** | Pick two cells on the enemy grid. Fires at both. |
| **HARD TURN** | Tap one of **your own** hulls — it swings a quarter turn on the spot. Prefers to pivot about its own origin and only walks outward if that would hang off the board or foul another hull, so it turns roughly where it stands. Unlike SCRAMBLE it will turn a **damaged** hull. Refused (and kept) if the hull has nowhere legal to swing. |

## Uncommon

| Card | What it does |
|---|---|
| **SALVO** | Pick a cell on the enemy grid — fires three shots in a horizontal line centred on it, clamped to stay on the board (a SALVO tapped flush against an edge still fires three, just shifted). |
| **DEPTH CHARGE** | Pick a cell on the enemy grid — fires a 2×2 block anchored there (also edge-clamped). |
| **CHAIN SHOT** | Pick a cell on the enemy grid — an ordinary single shot. If it hits, one bonus shot automatically follows at a random *unfired* cell orthogonally adjacent to it. No bonus shot on a miss. |
| **HOT SHOT** | No target needed — arms your side. The next hit **you** score also damages one more cell of that same hull (the nearest cell that isn't hit yet) — and can complete the kill on its own. One-shot: spent the instant it triggers, and ignores misses in between (it waits for your actual next hit). |
| **RAPID FIRE** | No target needed. Your next three hits reload at half the normal cooldown. |
| **SCRAMBLE** | No target needed. One of your own currently-undamaged hulls jumps to a random legal spot on your board. Does nothing (and isn't spent) if every hull is already damaged. |
| **COUNTER BATTERY** | No target needed — arms your defence. The next hit you *take* queues one bonus shot for your own next turn; that bonus shot never ends your turn even if it misses. |
| **AUTO DODGE** | Tap one of **your own** hulls to prime it. The next shot that would hit *that* hull is reported to your opponent as a miss and does no damage — and the hull immediately slips to the nearest legal water, so their map of it is now wrong. One-shot. If it is boxed in with nowhere to go, the dodge fizzles and the shot lands normally. Your own board shows a primed hull with wake chevrons. |
| **ARMOUR PLATE** | Tap one of **your own** hulls — it shrugs off the next **two** hits. Each deflected shell is reported to your opponent as a miss, does no damage, and spends one plate. Your own board draws the plates as bolted bands, one per plate left, so you can watch them wear down. |

## Rare

| Card | What it does |
|---|---|
| **BARRAGE** | No target needed. Four random shots land on enemy water you haven't already fired at. |
| **CROSS FIRE** | Pick a cell on the enemy grid — fires a five-cell plus shape centred on it (edge-clamped). |
| **DECOY** | No target needed — arms your defence. The next hit you'd take is instead reported to your opponent as a miss and does no damage to you. One-shot. |
| **PATCH CREW** | No target needed. Undoes one hit on **every** damaged, not-yet-sunk hull you have — REPAIR's effect, but fleet-wide. |
| **MINEFIELD** | Pick a cell on **your own** grid. If your opponent ever fires on that exact cell the mine throws the shell straight back: it costs them their next turn AND ricochets into a random still-afloat hull of **their own** fleet. Triggers on the cell regardless of whether their shot was a hit or a miss. Both screens fly the bounce. |
| **TRAP LINE** | Pick a cell on **your own** grid — mines three cells in a line from it (same shape as SALVO, edge-clamped). The *first* one your opponent hits springs the whole trap — same turn cost and same ricochet into their own fleet as MINEFIELD — and the other two go inert with it. |
| **SPY SHIP** | Pick a cell on the **enemy** grid you have not already fired at — a one-cell scout takes up station there. At the start of every one of your turns while it survives, it names one enemy hull cell touching it, marked on your board the way SPOTTER's find is. Only one scout at a time. A **JAM** silences your draw but not your scout. See below for how it is removed. |

---

## Removing an enemy SPY SHIP

The scout sits in **your** water and both players can see it there. You
cannot shoot it: you only ever fire at the *opposite* board, so no shot
either player could take would ever reach it.

Instead you **run it down** — steer one of your own hulls onto its cell
with **HARD TURN**, **AUTO DODGE** or **SCRAMBLE**, and it is crushed.
Its owner is told immediately and stops getting reports.

That is a deliberate design constraint, not a shortcut. Whose turn it is
is never sent between the two devices: each end works it out
independently from the shot outcomes they both see (see
`BattleScreen._maybePassTurn`). So "spend a turn to scuttle it" has no
shot to ride on and would leave the two devices disagreeing about whose
guns are live. Moving a hull rides on `sendMove`, which both devices
already mirror exactly.

---

## Visual reference

Legend used in every diagram below:

```
.   open water              @   the cell you tap
X   a shot this card fires  ?   a cell this card only CHECKS (no shot)
M   a mine you've set       ▓   an enemy hull (shown only so the diagram makes sense)
✕   a hit that already landed, shown for context — not fired by the card itself
```

Grids are drawn as seen from the **shooter's** side unless a diagram is
explicitly marked "your own grid."

## Multi-shot cards and the turn

Every shot of a multi-shot card is fired as one action, and each shell
gets its own arc across the water rather than all of them appearing at
once.

**If ANY shell of the volley lands, you keep the guns** — the same
"a hit lets you fire again" rule the rest of the game runs on. Earlier
shells are tagged `hold` so a miss among them cannot hand the turn over
early, and the final shell no longer decides it alone: a SALVO that holes
a hull twice and misses with its third shell used to pass the turn
anyway, which read as a hit being counted as a miss. See
`GameController.volleyScoredHit`.

A shaped card skips any cell you have already fired at, so late in a
match it can fire fewer shots than its shape suggests. If *every* cell it
would reach has already been fired at, the card is refused and stays in
your hand rather than being spent on nothing — which matters most at a
corner, where the slide can carry the whole shape away from the cell you
actually tapped.

### Shots with a fixed shape (enemy grid)

**SALVO** — three in a line, centred on the tap. Slides to stay on the
board rather than losing a cell at the edge — flush against a wall it's
still three shots, just shifted:

```
. . . . .          tapped on the edge:
. X @ X .          X @ X . .
. . . . .
```

**DEPTH CHARGE** — a 2×2 block, tapped cell as its corner:

```
@ X
X X
```

**CROSS FIRE** — a five-cell plus, centred on the tap:

```
. . X . .
. X @ X .
. . X . .
```

**SPRAY** — exactly the two cells you tap, no shape at all:

```
. X . . .
. . . . .
. . . X .
```

**BARRAGE** — four random cells, no target needed, never one you've
already fired at:

```
. X . . .
. . . X .
X . . . .
. . X . .
```

**CHAIN SHOT** — your tapped shot, then (only on a hit) one bonus shot
at a random *unfired* cell orthogonally next to it:

```
. . . . .
. . 1 . .    1 = your tapped shot (a hit)
. 2 . . .    2 = the automatic bonus shot
. . . . .
```

### Mines (your own grid)

**MINEFIELD** — one mined cell. The first time your opponent fires on
it, hit or miss, they lose their next turn:

```
. . .
. M .
. . .
```

**TRAP LINE** — three mined cells in a SALVO-shaped line. The first one
they hit springs the whole trap; the other two go inert with it:

```
. . . . .
. M M M .
. . . . .
```

### Information (enemy grid)

**SONAR** — every cell in a 3×3 around the tap is *checked*, not shot;
you get back how many distinct ships touch any `?`:

```
. . . . .
. ? ? ? .
. ? @ ? .      -> "2 ships in that area"
. ? ? ? .
. . . . .
```

**RECON SWEEP** — the whole row you tap is checked at once:

```
? ? ? ? ?    <- tapped row     -> "row has a ship" / "row is empty"
```

**SPOTTER** — no target; one random cell that genuinely holds an enemy
hull is revealed for you:

```
. . . . .            . . . . .
. . . . .     -->     . ▓ . . .   <- picked for you, not fired at
. . . . .            . . . . .
```

### Hull repair (your own fleet)

**REPAIR** — undoes one hit on your single most-damaged, not-yet-sunk
hull:

```
CRUISER  [✕][✕][ ]   before
CRUISER  [✕][ ][ ]   after — one hit undone
```

**PATCH CREW** — the same undo, but on every damaged hull at once:

```
DESTROYER [✕][ ]        -> [ ][ ]
CRUISER   [✕][✕][ ]     -> [✕][ ][ ]
```

**SCRAMBLE** — one currently-undamaged hull jumps to a random legal
spot on your own board (a damaged hull is never the one picked):

```
before                after
. . . . .              . . . . .
. ▓ ▓ . .    -->        . . . . .
. . . . .              . . ▓ ▓ .
```

**HOT SHOT** — arms itself, then rides your next hit: that hit also
damages the nearest still-unhit cell of the same hull, which can finish
it off on its own:

```
DESTROYER  [✕][ ]     1: your shot hits index 0
     ↓ HOT SHOT bonus
DESTROYER  [✕][✕]     2: nearest unhit cell also damaged — sunk
```

### Turn flow & timing

**DOUBLE TAP** — arms your very next shot only:

```
[fire] -> MISS -> turn stays yours -> [fire again]
          (normally a miss ends it right here)
```

**RAPID FIRE** — your next three HITS reload at half speed, then it's
spent:

```
shot 1 hit -> reload 50%
shot 2 hit -> reload 50%
shot 3 hit -> reload 50%
shot 4 hit -> reload 100% (back to normal)
```

**JAM** — costs your opponent exactly one draw:

```
you: [use JAM] ---------> opponent's next turn: no card drawn
```

**COUNTER BATTERY** — arms your defence; pays out on your next turn:

```
you: [use COUNTER BATTERY]        (armed)
opponent hits you  -------------> +1 bonus shot queued
your next turn: [bonus shot, never ends your turn] -> [normal shot]
```

**DECOY** — arms your defence for exactly one incoming hit:

```
you: [use DECOY]                          (armed)
opponent's next hit on you  ------------> reported to them as a MISS,
                                           you take no damage
```

---

## Notes for anyone tuning the deck

- Every card resolves through one of four routes, which is what keeps
  twenty cards from being twenty bespoke systems: **local** (fires,
  cooldown, turn flow — no network message beyond the shots
  themselves), **local + mirror** (mutates your own board, then tells
  your opponent so their copy of your fleet stays in step), **defender
  answers** (a request your opponent's device evaluates against its own
  board, because only it has the real answer), and **defender flag** (a
  one-shot condition armed on whichever device needs to check it next).
- Card weights, the full `PowerUpDef` table, and the targeting-shape
  geometry (`PowerUpShapes`) all live in
  [`lib/models/power_up.dart`](../lib/models/power_up.dart) — the deck
  is a single table there, so it's cheap to re-tune after playtesting.
- The gameplay wiring — draw timing, turn-flow (`hold`/`forcePass`),
  and each card's actual effect — lives in
  [`lib/services/game_controller.dart`](../lib/services/game_controller.dart)'s
  POWER PLAY block, with coverage in
  [`test/power_play_test.dart`](../test/power_play_test.dart).
