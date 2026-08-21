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

## Verification

* `flutter analyze` — clean (3 pre-existing lints, all untouched files).
* `flutter test` — **42 passing**, up from 22.
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
