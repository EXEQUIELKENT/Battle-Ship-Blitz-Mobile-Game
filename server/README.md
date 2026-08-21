# Battleship Blitz — online play server

Small PHP + MySQL backend that adds friends, presence and internet
matches to the game. It runs on XAMPP as-is; anything that can serve PHP
8 and reach a MySQL/MariaDB will do.

## What it does — and deliberately doesn't

It handles **accounts, friends, presence and invitations**, and then acts
as a **post box for the match itself**.

That last part is the whole design. A hotspot match works by the two
devices writing JSON lines to each other over a TCP socket. An online
match sends the *identical* lines to this server, which stores them and
hands them back to the other player in order. Both are a `GameLink` on
the client (`SocketLink` vs `RelayLink`), and nothing above that layer
knows which it is using — so the mode vote, fleet exchange, firing,
MANOEUVRE moves, the 60-second reconnect window and the rematch
handshake all work over the internet without the game rules gaining a
single "if online" branch.

The server never validates a move or holds any game state. It doesn't
need to: it isn't refereeing, it's relaying.

## Setup

1. **Start Apache and MySQL** (XAMPP Control Panel).

2. **Create the database** — once:

   ```
   C:\xampp\mysql\bin\mysql.exe -u root < server\schema.sql
   ```

3. **Check it answers.** If the project sits in `htdocs`, Apache is
   already serving this folder:

   ```
   curl -X POST -H "Content-Type: application/json" -d "{\"a\":\"ping\"}" ^
     http://localhost/Battle-Ship-Blitz-Mobile-Game/server/api.php
   ```

   Expect `{"ok":true,"service":"battleship-blitz","version":1}`.

4. **Point the game at it.** Main menu → **FRIENDS — PLAY ONLINE**, and
   enter the address *without* `api.php`:

   ```
   http://192.168.1.5/Battle-Ship-Blitz-Mobile-Game/server
   ```

   Use the **machine's LAN IP**, not `localhost` — a phone reading
   `localhost` looks at itself. `ipconfig` will tell you which.

Non-default MySQL credentials go in `server/config.local.php` (gitignored):

```php
<?php
return ['db_user' => 'bbz', 'db_pass' => 'secret'];
```

## Playing over the actual internet

On a LAN this works immediately. To reach players outside the house the
server needs to be reachable from outside, which means either:

* **A tunnel**, easiest for testing — e.g. `ngrok http 80`, then use the
  `https://…ngrok-free.app/Battle-Ship-Blitz-Mobile-Game/server` URL it
  prints. Nothing to configure on the router.
* **Port forwarding** on the router to this machine's port 80, using
  your public IP (and ideally a dynamic-DNS name).
* **Any PHP host.** Upload `server/`, import `schema.sql`, set
  `config.local.php`. Nothing here is XAMPP-specific.

Whichever you pick, both players enter the same address.

## How a match gets started

1. Both devices connect and each gets a six-character **friend code**.
2. They add each other by code; one accepts.
3. Whoever is online can be invited. **The inviter hosts** — so they
   command the red fleet and fire first, exactly as hosting a hotspot
   room does.
4. On accept the match goes `active`, both clients open a `RelayLink`,
   and the normal flow takes over: mode vote → deployment → battle.

## Endpoints

All are `POST` with a JSON body containing `a` (the action) and, except
for `ping`/`register`, a `token`. All return JSON with an `ok` flag; on
failure `error` carries a sentence written to be shown to a player.

| Action | Body | Purpose |
| --- | --- | --- |
| `ping` | — | Health check. |
| `register` | `name` | Creates this installation's account. Returns `id`, `tag`, `token`. |
| `sync` | profile fields | Mirrors local stats up so friends can see them. |
| `poll` | — | Friends + requests + presence + any live match. Doubles as the heartbeat. |
| `find` | `tag` | Look a captain up by friend code. |
| `request` | `tag` | Send a friend request (auto-accepts a mutual one). |
| `respond` | `playerId`, `accept` | Answer a request. |
| `unfriend` | `playerId` | Remove a friend. |
| `invite` | `playerId` | Challenge a friend. Returns `matchId`. |
| `invite_respond` | `matchId`, `accept` | Answer a challenge. |
| `match_end` | `matchId` | Free the seat when leaving. |
| `relay_send` | `matchId`, `lines[]` | Post protocol lines to the opponent. |
| `relay_poll` | `matchId`, `since` | Long-poll for theirs. Returns `lines`, `seq`, `peerAgo`, `status`. |

### Latency

`relay_poll` holds the connection open for up to 8 seconds (`config.php`)
and returns the instant something arrives, checking every 100ms. Measured
end-to-end delivery on a LAN is around **250ms**, which is comfortable for
the turn-based modes. **Chaos mode is playable but noticeably less
immediate than hotspot** — both fleets firing continuously is the one case
where a relay can't match a direct socket.

## Security notes

This is a hobby game server for playing with friends, and it is built
accordingly — but not carelessly:

* Every query is a **prepared statement**; no string-built SQL anywhere.
* Tokens are stored as **SHA-256 hashes**, so a database dump can't be
  used to sign in as anyone.
* Match endpoints check membership: a third party can neither read nor
  write another pair's match. Invites are restricted to accepted friends.
  Both are covered by tests in `test/online_relay_live_test.dart`.
* **Stats are client-reported.** The game is fully playable offline and
  the device owns its own profile, so RP and wins are a mirror for
  friends to look at, not an authority. Someone determined could send
  whatever numbers they liked. That is a deliberate trade, not an
  oversight — the alternative is running every match server-side.
* There is **no rate limiting and no TLS**. Before exposing this to the
  open internet, put it behind HTTPS (a tunnel gives you this free) and
  consider a basic per-IP throttle.

## Testing it

With Apache and MySQL up:

```
flutter test test/online_relay_live_test.dart
```

It registers throwaway accounts, walks the whole friend → invite →
relay path against the live server, and checks ordering, large messages
and the access rules. With no server running it skips itself, so a normal
`flutter test` never depends on the stack being up.

## Housekeeping

Nothing expires on its own. To clear out old test accounts and finished
matches:

```sql
USE battleship_blitz;
DELETE FROM matches WHERE status = 'done' AND updated_at < NOW() - INTERVAL 1 DAY;
DELETE FROM players WHERE last_seen < NOW() - INTERVAL 90 DAY;
```

`match_msgs` and `friendships` cascade with their parents.
