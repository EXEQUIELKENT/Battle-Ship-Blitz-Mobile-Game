# Battleship Blitz — online play backend

One PHP front controller (`api.php`) plus a MySQL/MariaDB database. Every
request is a POST with a JSON body carrying an `a` (action) field; every
response is JSON.

## Design, in one line

This server does account/friends/presence/matchmaking work itself, and for
the match itself it is nothing but a post box. The two clients exchange
exactly the same JSON lines they would have written to a TCP socket in a
hotspot match — the relay stores them and hands them back in order — so
the entire game protocol (mode vote, fleet exchange, firing, manoeuvres,
reconnect, rematch) works over the internet without a single change to the
game logic on either end. See the docblock at the top of `api.php` and the
comments above `relay_send`/`relay_poll` for the detail.


## More than one game

This deployment serves several titles. Because the relay is deliberately just
a post box for opaque JSON lines, it would happily carry one game's protocol
into another game's client — so the games are kept apart at the only place it
matters: `players.game`.

| | |
|---|---|
| `register` | files the new account under the request's `game` (whitelisted in `GAMES` at the top of `api.php`; anything unknown, or absent, is `bsb`) |
| `find` / `request` | only ever see captains playing the caller's own game |
| `queue_join` | only pairs you with a searcher of the same game |
| `ping` | advertises `games`, so each client can recognise a server it can use |

Everything after that is already safe: a match names two player rows, and the
relay only serves the two of them.

An account is per game. Installing a second title registers a second, separate
captain with its own friend code, friends and stats — which is what you want,
since none of those mean anything across games.

Stats that only one game has go in `players.profile_json`, written by `sync`
and handed back by every endpoint that returns a player. Battleship's own
figures (RP, ship/cannon skins, theme) predate this and keep their columns.

Existing installs: run `server/migrate-game-tag.sql`. Every row already there
becomes `bsb`, and the Battleship client needs no change — it never sends the
field and the default covers it.
## Setup

1. Create the database and tables:
   ```
   mysql -u root < server/schema.sql
   ```
   (XAMPP: `C:\xampp\mysql\bin\mysql.exe -u root < server\schema.sql`)

   Upgrading an existing install instead? Run the matching
   `server/migrate-*.sql` script for whatever it's missing — each one
   documents what it adds at the top of the file — rather than the full
   schema.

2. Point the game at this server: in-app, Online → enter this server's
   address (e.g. `http://192.168.1.7/Battle-Ship-Blitz-Mobile-Game/server`).
   The client tolerates the address with or without `api.php` and with or
   without a trailing slash.

3. `config.php` holds every tunable (DB connection, presence/poll timing,
   matchmaking timeouts) with defaults meant to run unmodified on a
   default XAMPP install. To override any of them without editing a
   tracked file, drop a `config.local.php` next to it returning just the
   keys to change — it's gitignored and wins over `config.php`.

## Endpoints (`a` values)

**Account & presence**
| Action | Does |
|---|---|
| `ping` | Health check — no auth. |
| `register` | Creates an account for this install and returns the token the app stores locally. Called once, on first entry to the online screen. |
| `sync` | Pushes this device's local profile (name, RP, equipped skins, …) up so friends see current stats. |
| `poll` | The friends screen's heartbeat — one request returns friends, requests, the live match if any, and queue state. Can long-poll (`wait`) for the matchmaking screen. |

**Friends**
| Action | Does |
|---|---|
| `find` | Search for captains to add as friends, by tag or name. |
| `request` | Send a friend request, by id or tag. |
| `respond` | Accept or decline an incoming friend request. |
| `unfriend` | Remove an existing friendship, either direction. |

**Direct invites**
| Action | Does |
|---|---|
| `invite` | Invite a friend to a match. The inviter becomes the HOST (red fleet, opening shot). |
| `invite_respond` | Accept or decline an invitation. |

**Matchmaking**
| Action | Does |
|---|---|
| `queue_join` | "Find a match" — joins the search queue, or pairs immediately if someone is already waiting. |
| `queue_leave` | Stop searching, or decline an already-found pairing. |
| `accept_match` | One captain's yes to a found pairing; the second yes opens the relay. |
| `match_end` | Marks a match done (surrender, disconnect-abandon, etc). |

**The relay itself** — see the comments directly above each case in
`api.php` for the exact wait/wake mechanism.
| Action | Does |
|---|---|
| `relay_send` | Posts one or more protocol lines into a match. |
| `relay_poll` | Long-polls for the opponent's lines since a given sequence number. |

## A note on `match_msgs`

Every relay line either player has ever sent lives in `match_msgs`, keyed
by an auto-increment `seq`. Nothing reads it back once a match reaches
`status = 'done'` — the client tears its connection down the moment it
sees that status — so `sweep_matchmaking()` (run opportunistically from
`queue_join`) deletes old rows for finished matches on the
`match_msgs_retention_seconds` schedule in `config.php`. Nothing else
prunes this table; a database restored from a very old backup with that
sweep never having run will have a large `match_msgs` table until the next
`queue_join` anywhere triggers a sweep.
