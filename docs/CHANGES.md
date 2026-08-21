# What changed in this round

Seven things, in the order they were asked for.

## 1. MANOEUVRE — the cannon stopped covering your own fleet

Your gun used to slide into the middle of your own grid on your turn,
which in MANOEUVRE parks it directly on top of the ships that mode is
entirely about dragging around.

Now the two devices deliberately draw the **same cannon differently**,
and that is the point rather than a desync:

| | Your screen | Your opponent's screen |
| --- | --- | --- |
| **Your cannon** | parked at the back of your grid | slides to the middle of your grid and fires from there |
| **Their cannon** | slides to the middle of their grid | parked at the back of theirs |

Each end only ever pins the gun that would be covering **its own** fleet.
Since every trajectory is derived from that same slide value
(`_cannonMouth`), the cannonball launches from wherever that device is
drawing the muzzle — no separate trajectory maths.

The scrim still marks whose turn it is, over the **enemy** grid while you
can't shoot at it. Never over your own board: that is the one you need to
see and work on.

*Files: `lib/screens/battle_screen.dart` — `_slideFor`, `dimThisHalf`.*

## 2. MANOEUVRE got its own icon

It was sharing TURN BASED's `swap_vert_circle`, so the two cards read as
the same thing at a glance — exactly the distinction the card exists to
draw. Now `open_with` (the "move" cross), which is what the mode is
actually about.

*File: `lib/screens/lan_mode_screen.dart` — `_modeIcon`.*

## 3. Equipped hulls now drive the whole identity

**The problem was that one id had to mean two different things.** Steel
Fleet is both the free starter hull *and* a real, equippable skin, so
"is steel equipped" cannot distinguish *"I chose steel"* from *"I never
chose anything"* — and those two want opposite behaviour. Treating it as
"never chose" silently overruled anyone who picked Steel Fleet on
purpose; treating it as "chose steel" put two untouched profiles into two
identical grey fleets and threw away the only thing telling the sides
apart.

`ProfileStore.shipSkinChosen` records which it is. It flips the first
time you equip *any* hull in the shipyard.

* **Never equipped anything** → host red, challenger blue, as before.
* **Equipped a hull — Steel Fleet included** → that hull, everywhere.

"Everywhere" now really is everywhere: deployment screen, battle grid,
fleet status strip, remaining-ships badge, turn scrim, cannon glow, and
the mode-vote screen's name chips, vote badges and card highlights.

One shared rule in `lib/core/fleet_identity.dart` decides it, so those
screens cannot drift apart again.

### Text stays readable

Hull colours run from Midnight Ops (near black) to Arctic Storm (near
white), so a fixed cream label was invisible on about a third of the
catalogue. Ink is now picked from the fill's own luminance. A test
measures real WCAG contrast across every hull in the catalogue and fails
under 4:1.

> ⚠️ Your own profile has steel equipped from *before* this flag existed,
> so it still counts as "never chose". Tap **Steel Fleet** in the shipyard
> once and you'll sail steel in multiplayer.

## 4. Updates no longer need an uninstall

Nothing provided a signing key, so release builds fell back to the
*debug* keystore — which is generated per machine. The laptop had one,
the GitHub runner made a different one, so the two builds were unrelated
apps as far as Android was concerned.

There is now a real release key (valid to **2056**) at
`android/app/release-key.jks`, gitignored, picked up automatically by
`flutter build apk --release`.

**`android/app/release-key.jks` and `key.properties` cannot be
regenerated. Back them up off this machine** — lose them and the only way
to install a future build is an uninstall, taking the save with it.

CI builds match once four repository secrets are added — see
`docs/RELEASE_SIGNING.md`. Bump the `+N` in `pubspec.yaml` on every build
you intend to install over an existing one; it is at `1.1.0+2`.

> ⚠️ **This one last install still needs an uninstall.** The build already
> on the phone was signed with the CI runner's throwaway debug key, and
> nothing can bridge two different keys. Uninstall once (the phone's
> profile and RP go with it), install this APK, and every build after it
> updates in place.

Verified on the built APK: signer `CN=Battleship Blitz`, SHA-256
`746aabaa…392cf8` — matching the keystore — and `versionCode=2`.

## 5. Music pauses when you leave the game

Our audio session is deliberately non-exclusive (`AndroidAudioFocus.none`
/ `mixWithOthers`) so overlapping sound effects can't native-pause each
other. The flip side is that the OS never takes focus away either, so the
menu track happily played on out of a backgrounded app.

It now pauses on background and **resumes from the same position** —
`play()` would restart an asset from bar one, so a two-second glance at a
notification would have rewound the track every time.

*File: `lib/services/sound_service.dart` — `onAppPaused` / `onAppResumed`.*

## 6. Online play, with friends

A new PHP + MySQL backend in `server/` (runs on the XAMPP already on this
machine) adds accounts, friend codes, live presence, stats and
invitations. Setup and endpoint reference: **`server/README.md`**.

**The design in one line:** the server does friends and presence itself,
and for the match it is nothing but a post box.

A hotspot match writes JSON lines to a TCP socket. An online match sends
the *identical* lines through the relay. Both are a `GameLink`
(`SocketLink` / `RelayLink`) and nothing above that layer knows which it
is using — so the mode vote, fleet exchange, firing, MANOEUVRE moves, the
60-second reconnect window and the rematch handshake all work over the
internet **without the game rules gaining a single "if online" branch**.

Two things a socket gives free that the relay had to reproduce:

* **Ordering** — outgoing lines go through one queue drained by a single
  worker, so two sends in the same frame can't race onto the wire out of
  order.
* **Liveness** — HTTP never says the other end went away. The server
  reports how long ago the opponent last spoke to it; since both players
  poll continuously while playing, a few seconds of silence already means
  something is wrong. That reports *presence* rather than closing the
  link, which is what lets the same channel notice them coming back — so
  online matches reconnect exactly like hotspot ones.

Flow: both devices connect → each gets a six-character friend code → swap
codes and add each other → invite anyone who's online. **The inviter
hosts**, so they command the red fleet and fire first, exactly as hosting
a hotspot room does.

### Latency, honestly

`relay_poll` long-polls (holds up to 8s, checks every 100ms). Measured
end-to-end delivery on a LAN is ~250ms — comfortable for the turn-based
modes. **Chaos mode is playable but noticeably less immediate than
hotspot**, which is the one case a relay can't match a direct socket.

### One deliberate trade

**Stats are client-reported.** The game is fully playable offline and the
device owns its profile, so RP and wins are a mirror for friends to look
at, not an authority — someone determined could send whatever numbers
they liked. The alternative is running every match server-side, which
this is not. Prepared statements, hashed tokens and match-membership
checks are all in place; there is no rate limiting or TLS, so put it
behind HTTPS before exposing it to the open internet.

## 7. Local pass-and-play: each player picks their own gear

Two people share one device and therefore one saved profile, but they now
each sail their own hull, cannon and battlefield — same as a hotspot
match, where the two loadouts simply come from two different profiles.

A **GEAR** button on each player's deployment screen (the one moment each
of them is alone with the device) opens a picker of everything the
profile owns, including a "plain side colour" option to opt out of skins
entirely.

The shipyard is still the only place anything is bought, out of one
shared wallet — this is just the two of them dividing up what's already
unlocked. Both seats start on the device owner's equipped gear, so a
player who changes nothing gets exactly what they had before.

*Files: `GameController.localLoadouts`, `placement_screen.dart` —
`_GearDialog`.*

---

## Two bugs the live run caught

Both were in the new online code, and neither would have shown up in a
unit test — they needed two real clients and a real server.

**The host was thrown back to a mode vote it had already won.** The
friends screen treated `await Navigator.push(LanModeScreen)` as "the
match is over". It isn't: `LanModeScreen` hands over to deployment with
`pushReplacement`, so that await completes the moment the vote locks —
mid-match. The cleanup then ran while the battle was still being set up,
ended the match server-side, and let the next poll launch the whole thing
again. The relay log showed it plainly: a second `hello` from the host
right after `mode_locked`, and the match already marked `done`.

Fixed by hanging the "match finished" signal off `NetworkService`
dropping out of online mode — a match spans several routes, so no single
route's lifetime marks it — plus a guard against ever launching the same
match id twice.

**A saved token whose account no longer exists locked you out.** Only hit
because I reset the test database, but it happens for real whenever the
server is reinstalled, the account is removed, or the address now points
at a different server. The app held a token the server had never issued
and reported "not signed in" forever. It now re-registers silently.


---

# Thematic skin families (imported from Claude Design)

Six new families from the **Skin system architecture** design, each
bringing a hull set, a cannon with its own shell, and a battlefield:

| Family | Fleet | Cannon · Shell | Battlefield |
| --- | --- | --- | --- |
| Blackpowder | Blackpowder Fleet | Bell-Mouth Broadside · Round Shot | Pirate Seas |
| Iron Pact | Iron Pact | MK-IV Autoloader · Sabot Shell | Fleet Command |
| Brass | Brass Consortium | Pressure Battery · Governor Sphere | Brass Works |
| Rime | Rime Wardens | Icebreaker Mortar · Rime Shard | Rime Field |
| Cinder | Cinder Hold | Magma Bombard · Ember Slug | Cinder Straits |
| Helios | Helios Drift | Ion Lance · Plasma Bolt | Helios Grid |

**The point is that these are structural, not chromatic.** The original
nine skins are one hull drawing in nine colourways. Each of these is five
bespoke hull classes: a pirate carrier is three canvas blocks, a naval one
is an angled flight deck with an island, a steam one is two paddle wheels.
The design's own acceptance test is that a family stays readable with the
colour stripped out — and it does.

## How it was ported

Every path is copied **verbatim** from the design's SVG through a small
parser (`lib/art/svg_path.dart`), rather than hand-translated into
`moveTo`/`cubicTo` calls. Fifty-odd drawings translated by hand would be
unreadable and impossible to check; this way any shape can be diffed
against the design a character at a time.

Two details that would otherwise have looked wrong:

* **Non-uniform viewBoxes.** Hulls are authored in one 300×100 box with
  `preserveAspectRatio="none"`, so the same drawing stretches to a 5-cell
  carrier or a 2-cell destroyer.
* **Non-scaling strokes.** Every stroke in the design carries
  `vector-effect="non-scaling-stroke"`. The transform is applied to the
  *path*, not the canvas, so ink stays constant on screen — without this a
  ship at grid size is a solid blob of outline.

## What changed in the game

* **`muzzleFraction` is now per-gun.** It was one constant; the design
  gives each family its own barrel length (0.44 for a stubby bell-mouth up
  to 0.72 for a naval autoloader). Since it is the single value
  `battle_screen` reads to spawn the shell, honouring it is what makes a
  long gun genuinely throw from further out.
* **The shell belongs to the cannon.** Equip the Ion Lance and plasma
  bolts fly, whatever water they cross. Both appear together on the store
  card — the design's own rule, so the pairing is visible before you buy.
* **Boards replace the grid, not the palette.** Ice floes with crack
  lines, basalt with molten seams, riveted plate with bolted seams — plus
  each family's own hit and miss markers. Coordinates, cell count and tap
  targets are untouched: a marker is still one cell, drawn differently.
* **Damage is deliberately not themed.** You have to read "that hull is
  hit" at a glance on an opponent's board, and putting a gameplay signal
  behind a cosmetic would be a bad trade. The ships change; the wounds
  don't.
* **Skins now show against the AI too**, which they never did. Your half
  is your gear; the AI keeps plain blue hulls and the standard gun, so the
  two sides stay instantly separable.

## A live bug this uncovered

**Ownership keys were not scoped by item type.** `owned` is one flat set
shared by hulls, cannons and battlefields, so an id appearing in two
catalogues was silently one purchase — buying the **Arctic Front**
battlefield (900 RP) handed you the **Arctic Storm** hull (750 RP) for
free. That was already happening on your save. Six families across three
catalogues would have turned one collision into eighteen.

Keys are now `ship:` / `cannon:` / `theme:` scoped, and old saves migrate
**generously**: every bare id expands into a typed key for each catalogue
containing it. Under the old build you really could equip both arctic
items, so scoping strictly now would repossess something you had been
using — nobody should be charged for a bug on our side.

## Pricing

Taken from the design where it states one, filled in at the same band
where it doesn't. Hulls 650–2800 RP, cannons 600–2600, battlefields
800–2200. `FleetFamily.setPrice` also exposes the design's one-tap
matched set at 80% of the three pieces bought separately; the store
button for it is **not built yet** — the data is there, the UI isn't.

---

## Verification

* `flutter analyze` — clean (3 pre-existing lints, all untouched files).
* `flutter test` — **64 passing**, up from 22.
  * `test/fleet_identity_test.dart` (10) — both halves of the
    steel-is-ambiguous problem, plus measured label contrast across the
    whole hull catalogue.
  * `test/online_relay_live_test.dart` (10) — runs against the **real**
    PHP server: register → befriend → invite → relay, checking message
    ordering under a burst, a full resume snapshot round trip, and the
    access rules (a stranger can neither read nor write another pair's
    match, nor invite a non-friend; a forged token is refused). Skips
    itself when no server is running, so a normal test run never depends
    on Apache being up.
  * `test/fleet_family_test.dart` (22) — the SVG parser (including the
    infinite loop a malformed path used to cause, which this test found),
    all 30 hulls plus every cannon, shell and board actually emitting
    geometry, the design's geometry tokens, and the ownership scoping.

Seen on screen: all six fleets in the shipyard and all six cannons with
their shells beside them; Cinder Hold deployed and fought on Cinder
Straits with the Magma Bombard, its ash-puff miss markers landing on both
grids, and the AI opposite in plain blue with the standard gun.

**Not visually confirmed:** the shell in flight. It draws (the store card
and the tests both exercise the same painter) but a 430 ms projectile is
not something the screenshot pipeline catches reliably, so I never got a
clean frame of one mid-arc.

---

# Skin fixes, BLITZ mode, and match chat

## The design import, corrected

Four things the first pass got wrong or left out.

### Ink was too heavy at small sizes

The design marks every stroke `vector-effect="non-scaling-stroke"`, and
that was reproduced literally: a stroke stayed a fixed number of device
pixels however small the drawing got. Correct to the letter, wrong in
effect. The design *authors* its 2–4px ink against a ship drawn 300 units
wide; the game draws that same ship at a fraction of the size inside a
grid cell. Fixed ink on a shrinking hull is ink that grows relative to
everything around it, until a destroyer at grid scale is mostly outline.

Ink now scales with the drawing below the design's reference size and
stops scaling at or above it, with a floor so hairlines don't flicker. At
full size the result is pixel-for-pixel what the design specifies;
smaller, the proportions hold instead of the absolute weight. One choke
point (`FamilyCanvas.ink`), so no piece of art can opt out.

### The reload ring was still the generic one

Every family draws its own platform — a timber-and-wheel carriage, a
bolted deck plate, a rock slab, a floating ring — at its own height and
its own radius. The cooldown sweep ignored all of that: a flat white hoop
on a fixed circle around the widget's centre, which on most families sat
off the artwork entirely.

The sweep now follows each family's own mount geometry and takes its
colours, running from the family's trim up to its glow as the gun comes
back online, over a dark track so it still reads on the pale families.
Rime Wardens is the case that proves the point: ice-blue glow on an
ice-blue mount is invisible without the track underneath it.

### A gun could fire from outside its own barrel

While measuring the mounts, the muzzle turned out to be wrong too. The
design's token table gives each family a `muzzle` fraction, and those were
used verbatim — but they are proportions of an idealised gun, not
measurements of the drawing. Iron Pact's was off by 60%: `battle_screen`
reads exactly one value to decide where a shell is born, so the MK-IV
Autoloader's shells were appearing above the top edge of their own widget.

`muzzleY` is now read off the artwork. The shell leaves the hole it
visibly comes out of, for every family, by construction.

### The firing storyboard's exhaust

"Same 260 ms. Different beat." The timing is fixed for all six families
and unchanged; what varies is the shape of what comes out. Blackpowder
hangs a grey cloud up and to the left; Iron Pact vents hard sideways from
the muzzle brake and is done in a third of the time; Brass throws two jets
sideways rather than upward; Rime's vapour sinks instead of rising and
sheds ice motes; Cinder's ash cloud throws hot motes out of the top;
Helios makes no smoke at all and bleeds off an expanding ring, because the
design is explicit that "recoil is a ring, not a kick".

## A second board bug this turned up

**Brass Works and Fleet Command were nearly the same battlefield.** Brass
Works' field was a steel-blue a few points from Fleet Command's — at
store-card size, the same board twice. The plates, seams and bolt grid
were always right; the colour was doing the damage. It is now brass.

The regression guard for this is worth a note. The obvious test — sum the
RGB channel differences and require a minimum — was written first and was
actively misleading: it scored the two boards that genuinely looked
identical *further apart* than a pair that reads clearly as teal versus
blue. What separates boards at a glance is hue or lightness, not distance
travelled through RGB, so the test compares those instead. Checked both
ways: it fails on the old value and passes on the new one.

## The store sells the design, not the swatch

The Shipyard's shell is deliberately unchanged — navy header, gold RP
pill, three tabs, cream cards. What changed is what a card may show.

The old cards were honest about the old skins: one hull drawing in a pair
of tint colours, so a single battleship silhouette said everything there
was to say. A family is not that, and none of it survives being reduced to
one ship on a blue square.

* **Hull cards** show the carrier large on the family's own water, then
  the other four classes as a strip. That is the design's own acceptance
  test made visible: the card proves all five change.
* **Cannon cards** carry the shell on the disc beside the gun, so the
  pairing is visible before purchase rather than at the first shot.
* **Battlefield cards** preview the real board with its own markers.
* **The nine originals still equip**, but they no longer lead. They sit
  behind a LEGACY divider that opens on a tap — and opens by itself when
  what you have equipped is inside it, because a store that hides what you
  are wearing is worse than a store with a long list.

**The matched set is now built.** It was designed last time and left as
data; it leads the GAMEPLAY tab. One tap takes a family's hull, gun and
battlefield at 80%, and the quoted price discounts only what you are still
missing — buy the hull this week and the set doesn't charge you for it
again next week. An unaffordable set changes nothing at all: a half-bought
set is impossible.

## BLITZ

A fourth mode: CHAOS and MANOEUVRE at once. No turn order, no waiting —
both fleets fire on their own reload timers, and any hull that has not
been hit yet can run for fresh water while the shells are still in the
air.

It is defined as its two parents combined rather than as a third thing.
`hasTurns` and `canRearrange` are properties of a mode now, and every rule
reads those instead of naming modes, so nothing needed a second clause for
a mode that behaves exactly like its parents.

Appended to the enum rather than slotted in beside them, deliberately:
`LanBattleMode.index` is what goes over the wire in the vote and in a
resume snapshot, so inserting anywhere else would silently reinterpret an
in-flight match against an older build.

## Match chat

Hotspot and online play get a chat spanning the mode vote, deployment, the
battle and the result — **one conversation, not four**. A line sent while
your opponent is still laying out their fleet is still there when they
reach the battle, and after the match either captain can scroll back
through the whole exchange.

Held as state on `NetworkService` rather than pushed through the message
stream, for the same reason the votes are: that stream is a broadcast, so
anything emitted while the other end is mid-route-change is dropped
permanently. A list the next screen reads on its first frame has no such
window.

**Nothing here sits on top of the board**, which ruled out the obvious
designs — a docked panel steals height from two grids already sharing one
screen, and a full-screen sheet blinds you while shells are in the air.
So: closed, it is a single small pill, and on the battle screen it lives
in the middle band, the one strip of that layout which isn't a grid. An
arriving line surfaces as a one-line toast beside the pill, which reads
without opening anything. Opened, it is a corner panel over a fully
transparent barrier — the board stays visible around it, one tap outside
puts it away, and it shrink-wraps, so a two-line exchange gets a two-line
panel rather than a third of the screen.

Quick phrases exist for the same reason: mid-battle, raising a keyboard is
the thing most likely to cost somebody a shot.

Length is capped at both ends and the log is bounded. The cap is enforced
again on arrival, not just at the sender — the sender is the other device,
which is not something to take on trust.

## Gear on the deployment screen

The GEAR button was pass-and-play only. It is now on hotspot and online
deployment too, which is where you can see your fleet laid out and is the
last moment before the guns are live.

In a network match it re-equips your profile — there is no second seat on
this device to keep it separate from — and then **announces the change to
your opponent**. They are drawing your fleet from the gear you sent in the
handshake; without the announcement they would keep rendering the hull you
arrived in for the whole match. It reuses the `hello` shape rather than
inventing a second message, so the receiving side already knows how to
apply it: this is the same announcement, made again.

## Player 2's drag landed on the wrong cells

On Player 2's turn to deploy, the drop highlight and the ghost ship under
the finger disagreed — and the longer the ship, the further apart they
were, so the destroyer looked nearly right and the carrier looked broken.

Two facts were in tension, and both are true. Player 2's board is inside a
180° `RotatedBox`, and `RenderBox.globalToLocal` unwinds that correctly —
so the obvious suspect was innocent, which is what made this hard to spot.
The drag ghost is *not* inside that rotation: `Draggable` renders
`feedback` into the root `Overlay`. So the finger marks the ghost's
top-left in SCREEN space, which under a half turn is the ship's far end in
BOARD space — and that was being treated as the ship's origin.

Because the turn is exactly 180°, the correction is exact rather than
approximate: subtracting the ship's own extent recovers the origin.

---

## Verification

* `flutter analyze` — clean (1 pre-existing lint).
* `flutter test` — **96 passing**, up from 64.

Seen on screen, on a 442×853 phone-shaped window:

* Cinder Hold's Magma Bombard with its reload ring riding the rock-slab
  collar in molten orange, mid-sweep and full; the same for Iron Pact's
  bolted deck plate and Rime Wardens' ice-armoured mount, which is the
  pale-on-pale case the dark track exists for.
* **The shell in flight** — the caveat left open last time. The Ember Slug
  mid-arc between muzzle and target, and the Rime Shard over the ice.
* Helios Drift's discharge: two expanding cyan rings at the emitter and no
  smoke at all.
* Brass Works and Fleet Command side by side in the store, now plainly
  different boards.
* All six matched-set cards, with Blackpowder correctly quoting 1160 RP
  rather than 1450 because its cannon was already owned.
* A full BLITZ match over two instances: both sides firing seconds apart
  with no turn handoff, a carrier dragged to fresh water mid-battle and
  the move mirrored to the opponent, and both cannons parked at the back
  of their own waters throughout.
* Chat carried from the vote screen through deployment into the battle and
  on to the result, with the toast landing inside the middle band and
  covering neither grid.
* Gear changed on the LAN deployment screen: the fleet, the dock and the
  label all switched to Blackpowder live.
* Player 2's carrier dragged onto the flipped board, highlight and ghost
  now covering the same five cells, and the ship landing exactly where the
  highlight showed.

---

# Band, platform, and the deployment battlefield

## The fleet strips got their width back

Putting the chat button in the middle band cost both fleet strips 38px,
and those strips are five fixed-size hulls in a `spaceEvenly` row — so
the space came straight out of the gaps between the ships and they
visibly bunched up.

The button is now behind a tab. By default the band carries only a thin
chevron beside the ship counter; swipe it right and the chat pill comes
out, swipe it left and it tucks away, and the strips animate back to full
width the moment it does. A message arriving while it is tucked away pops
it out on its own, because a toast with nothing to appear beside is no
toast at all — and the tab keeps an unread dot either way, so swiping it
shut never hides that something is waiting.

Two things fell out of looking at it properly:

* **The strip now measures instead of assuming.** At a fixed 11.5px per
  cell the five hulls total 195px of content that cannot shrink, so on a
  narrow phone — or with the chat tab out — the row had no way to fit and
  would simply overflow. It now takes the smaller of the old size and
  what the space allows, so it keeps exactly the proportions it always
  had whenever there is room, and degrades instead of breaking when there
  isn't.
* **Player 2's row is no longer stubbornly blue.** The top strip was
  painted a hardcoded steel blue while the bottom one wore the equipped
  battlefield's deck — the last patch of default palette on an otherwise
  fully themed screen. Each row now wears its own captain's deck, with a
  hairline between them since they can now legitimately match.

## The reload went back onto the mounting

The standard cannon has always been a barrel standing on a disc, with the
cooldown running round that disc: the reload reads as something the
*mounting* does. Drawing the family sweep on each family's own drawn
mount put it on the cannon itself, which is a different and worse thing —
on a wide mount like the Magma Bombard's rock collar, the arc cut
straight across the gun's body.

Every family now gets a real platform: a rimmed plate drawn behind the
gun in that family's own metal, with the sweep running round it. The art
is inset slightly about its own mount so a ring of platform always shows,
and the inset is sized so the widest of the six still fits inside the
widget — there is a test for that, because "it fits" is a fact about six
different mount radii and not something to eyeball.

The inset moves the muzzle, so `muzzleFrac` accounts for it. That value
is the single thing the battle screen reads to decide where a shell is
born, and if it kept quoting the authored position the shell would leave
from a point the barrel no longer reaches.

## Buy logic

Checked rather than assumed, and it was already right: buying a hull adds
a hull and nothing else, for all six families in all three directions,
with each piece charged its own catalogue price exactly once and
re-equipping something you already own free. That is now pinned by tests
rather than left to inspection — a family shares one id across three
catalogues, which is precisely the shape of mistake that hands over all
three, and it is worth a guard even when it isn't currently broken.

What *was* wrong was a trap on the one card that legitimately charges for
three things at once. The matched-set card sat at the top of a list where
every other card buys on a tap anywhere on it, and it leads with a large
board preview that looks exactly like the battlefield cards below it.
Reach for what looks like one battlefield, pay for a hull and a cannon
too. **Only the EQUIP SET button buys now**, and the card spells out
which pieces it is adding and which you already own and are not being
charged for again.

## The deployment screen shows the battlefield you equipped

It didn't, in any mode. A player who had bought Cinder Straits laid their
fleet out on the default steel-blue water and only saw what they owned
once the shooting started — so the one screen where you stare at your own
board for a solid minute was also the one that ignored your choice of
board.

The grid, the deck behind it and the dock tray now all come from the
equipped battlefield, in vs-AI, pass-and-play, hotspot and online alike.
Changes are live: pick a different battlefield in the GEAR dialog and the
screen changes underneath it while it is still open.

Smooth, and in two different ways because two different things are
changing. The deck and tray are plain colours, so they tween. The grid is
not — a family board is real artwork rather than a palette, with nothing
to tween between — so it cross-fades, two boards briefly stacked. The
drop-target key stays on the container *outside* the cross-fade, so the
placement maths keeps measuring one stable box while the switch is in
flight.

The hint line under the grid now takes its ink from the deck's luminance
too, since decks run from Cinder Straits' near-black to Rime Field's
near-white and a fixed navy hint disappeared on half of them.

---

## Verification

`flutter analyze` clean (1 pre-existing lint); `flutter test` **100
passing**, up from 96. Not exercised on a device this round — that is
being done separately.

New guards worth naming, all of which check a fact that is awkward to
confirm by eye:

* the reload platform fits inside the cannon widget for all six families,
  and the visible ring has real width;
* the muzzle moves with the art when it is inset, and still sits above
  its own mount and inside the art box;
* one piece of a family is one piece — six families, three directions,
  ownership and equipped state both;
* each piece is charged its own price once, and re-equipping is free.
