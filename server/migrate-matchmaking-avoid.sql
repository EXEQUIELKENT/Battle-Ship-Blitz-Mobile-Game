-- Battleship Blitz — upgrade an existing database so matchmaking prefers
-- a different opponent after a decline instead of immediately re-pairing
-- the same two players.
--
-- Safe to run more than once.
--
--   C:\xampp\mysql\bin\mysql.exe -u root < server\migrate-matchmaking-avoid.sql

USE battleship_blitz;

-- One row per "player_id declined a pairing with avoid_id", read by
-- `queue_join` as a soft preference (not a hard exclusion) — see
-- schema.sql for the full explanation.
CREATE TABLE IF NOT EXISTS matchmaking_avoid (
  player_id  INT NOT NULL,
  avoid_id   INT NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (player_id, avoid_id),
  CONSTRAINT fk_ma_player FOREIGN KEY (player_id)
    REFERENCES players(id) ON DELETE CASCADE,
  CONSTRAINT fk_ma_avoid FOREIGN KEY (avoid_id)
    REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB;
