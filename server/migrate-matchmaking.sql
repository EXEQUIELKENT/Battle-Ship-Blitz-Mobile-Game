-- Battleship Blitz — upgrade an existing database for matchmaking.
--
-- Adds the "find a match" queue and the both-captains-must-accept state to
-- a database created before they existed. Safe to run more than once
-- (MariaDB 10.4+ / MySQL 8: IF NOT EXISTS / IF EXISTS on the clauses).
--
--   C:\xampp\mysql\bin\mysql.exe -u root < server\migrate-matchmaking.sql

USE battleship_blitz;

-- Matches gain 'found' (paired by matchmaking, nobody has accepted yet)
-- plus one flag per side tracking who HAS accepted. Friend invitations
-- keep working exactly as before; only their status set grows wider.
ALTER TABLE matches
  MODIFY status ENUM('inviting','found','active','done') NOT NULL DEFAULT 'inviting',
  ADD COLUMN IF NOT EXISTS host_ready  TINYINT(1) NOT NULL DEFAULT 0 AFTER guest_id,
  ADD COLUMN IF NOT EXISTS guest_ready TINYINT(1) NOT NULL DEFAULT 0 AFTER host_ready;

-- The find-a-match queue: one row per searching captain.
CREATE TABLE IF NOT EXISTS matchmaking (
  player_id INT NOT NULL PRIMARY KEY,
  joined_at DATETIME NOT NULL,
  CONSTRAINT fk_q_player FOREIGN KEY (player_id)
    REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB;
