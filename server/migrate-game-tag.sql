-- Upgrade an existing database to serve more than one game.
--
-- The backend started life single-game, so `players`, `matchmaking` and
-- `matches` carry no notion of WHICH game a captain is playing. That is
-- fine for one title and actively broken for two: a second game pointed at
-- this same server would have its players matched against Battleship
-- players, and the relay — which is deliberately just a post box for opaque
-- JSON lines — would happily carry one game's protocol into the other
-- game's client.
--
-- This adds that missing discriminator. Every existing row is Battleship,
-- so `game` defaults to 'bsb' and the Battleship client needs no change at
-- all: it never sends the field, and the server's default covers it.
--
-- Safe to run more than once (MariaDB 10.4+ / MySQL 8: IF NOT EXISTS).
--
--   C:\xampp\mysql\bin\mysql.exe -u root < server\migrate-game-tag.sql

USE battleship_blitz;

-- `game`  which title this account belongs to ('bsb' = Battleship Blitz).
--         An install of a different game registers separately and gets its
--         own row, so friends, queues and stats never cross over.
-- `profile_json`  per-game profile extras. Battleship's stats have columns
--         of their own above (rp / ship_skin / cannon_skin / theme); rather
--         than growing a column per field per game, other titles put their
--         own shape in here and read it back out of `public_player`.
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS game VARCHAR(16) NOT NULL DEFAULT 'bsb' AFTER id,
  ADD COLUMN IF NOT EXISTS profile_json TEXT NULL AFTER theme;

-- Friend codes only have to be unique WITHIN a game now. Keeping them
-- globally unique would mean two games competing for the same 6-character
-- space for no benefit — nobody can see, search for, or befriend a captain
-- playing a different title.
--
-- The unique index is named `tag` when MySQL created it implicitly from the
-- inline UNIQUE in schema.sql, so drop by that name and rebuild it as a
-- composite. The DROP is not guarded: if it is already gone this migration
-- has been applied, and the ADD below is guarded anyway.
ALTER TABLE players
  DROP INDEX tag;

ALTER TABLE players
  ADD UNIQUE KEY IF NOT EXISTS uniq_game_tag (game, tag);

-- Matchmaking's candidate query filters on the searcher's game and then
-- orders by how long each rival has been waiting, so it reads
-- (game, last_seen) — worth an index once two games share the table.
ALTER TABLE players
  ADD INDEX IF NOT EXISTS idx_game_last_seen (game, last_seen);
