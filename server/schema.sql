-- Battleship Blitz — online play backend
--
-- Run once:  mysql -u root < server/schema.sql
-- (XAMPP:    C:\xampp\mysql\bin\mysql.exe -u root < server\schema.sql)
--
-- Upgrading an EXISTING database (created before matchmaking existed)?
-- Run server/migrate-matchmaking.sql instead — it applies just the diff.

CREATE DATABASE IF NOT EXISTS battleship_blitz
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE battleship_blitz;

-- ---------------------------------------------------------------- players
--
-- One row per installed copy of the game. There are no passwords: the app
-- registers itself once, keeps the returned token in its own local
-- storage, and sends it with every request. Only the token's SHA-256 is
-- stored, so a dump of this table cannot be used to impersonate anybody.
CREATE TABLE IF NOT EXISTS players (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  tag          VARCHAR(8)  NOT NULL UNIQUE,   -- friend code, e.g. "K7X2QM"
  name         VARCHAR(32) NOT NULL,
  token_hash   CHAR(64)    NOT NULL,
  rp           INT         NOT NULL DEFAULT 1000,
  wins         INT         NOT NULL DEFAULT 0,
  losses       INT         NOT NULL DEFAULT 0,
  best_streak  INT         NOT NULL DEFAULT 0,
  ship_skin    VARCHAR(24) NOT NULL DEFAULT 'steel',
  ship_chosen  TINYINT(1)  NOT NULL DEFAULT 0,
  cannon_skin  VARCHAR(24) NOT NULL DEFAULT 'mk1',
  theme        VARCHAR(24) NOT NULL DEFAULT 'classic',
  last_seen    DATETIME    NOT NULL,
  created_at   DATETIME    NOT NULL,
  INDEX idx_token (token_hash),
  INDEX idx_last_seen (last_seen)
) ENGINE=InnoDB;

-- ------------------------------------------------------------ friendships
--
-- One row per PAIR, not per direction. `requester_id` is whoever sent the
-- request, which is what lets the other end tell "waiting for them" apart
-- from "they are waiting for me" while status is still 'pending'.
CREATE TABLE IF NOT EXISTS friendships (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  requester_id  INT NOT NULL,
  addressee_id  INT NOT NULL,
  status        ENUM('pending','accepted') NOT NULL DEFAULT 'pending',
  created_at    DATETIME NOT NULL,
  UNIQUE KEY uniq_pair (requester_id, addressee_id),
  INDEX idx_requester (requester_id),
  INDEX idx_addressee (addressee_id),
  CONSTRAINT fk_fr_requester FOREIGN KEY (requester_id)
    REFERENCES players(id) ON DELETE CASCADE,
  CONSTRAINT fk_fr_addressee FOREIGN KEY (addressee_id)
    REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------- matches
--
-- A match starts life as an invitation ('inviting'), becomes 'active' when
-- the guest accepts, and is 'done' once either player leaves for good.
-- The host is always the player who sent the invite — which is what makes
-- them the red fleet and gives them the opening shot, exactly as hosting a
-- hotspot room does.
-- 'found' is a matchmaking pairing that NEITHER side has agreed to yet:
-- both captains must tap accept before it becomes 'active' and the relay
-- opens. host_ready/guest_ready track who has accepted so far.
CREATE TABLE IF NOT EXISTS matches (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  host_id     INT NOT NULL,
  guest_id    INT NOT NULL,
  status      ENUM('inviting','found','active','done') NOT NULL DEFAULT 'inviting',
  host_ready  TINYINT(1) NOT NULL DEFAULT 0,
  guest_ready TINYINT(1) NOT NULL DEFAULT 0,
  created_at  DATETIME NOT NULL,
  updated_at  DATETIME NOT NULL,
  INDEX idx_host (host_id, status),
  INDEX idx_guest (guest_id, status),
  CONSTRAINT fk_m_host  FOREIGN KEY (host_id)  REFERENCES players(id) ON DELETE CASCADE,
  CONSTRAINT fk_m_guest FOREIGN KEY (guest_id) REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------------ matchmaking
--
-- The "find a match" queue. One row per searching player; pairing two of
-- them creates a match with status 'found' and deletes both rows. Rows
-- whose owner stops answering are swept by the next queue operation.
CREATE TABLE IF NOT EXISTS matchmaking (
  player_id INT NOT NULL PRIMARY KEY,
  joined_at DATETIME NOT NULL,
  CONSTRAINT fk_q_player FOREIGN KEY (player_id)
    REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ------------------------------------------------------ matchmaking_avoid
--
-- Remembers "player_id declined a pairing with avoid_id" for a while.
-- `queue_join` reads this to PREFER a different opponent over the one
-- just declined — it's a preference, not a hard exclusion, so if the
-- avoided player is the only one left in the queue, they still get
-- paired again rather than leaving both of them stuck searching forever.
-- Rows older than `avoid_rematch_seconds` are swept the same way stale
-- queue/match rows are.
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

-- ------------------------------------------------------------ match_msgs
--
-- The relay itself. Every line the two clients would have written to each
-- other's socket in a hotspot match is stored here instead and read back
-- in `seq` order — so the game protocol on both ends is byte-for-byte the
-- same one LAN play already uses, and neither the vote, the fleet
-- exchange, firing, manoeuvres, resume nor rematch needed changing to
-- work over the internet.
CREATE TABLE IF NOT EXISTS match_msgs (
  seq        BIGINT AUTO_INCREMENT PRIMARY KEY,
  match_id   INT NOT NULL,
  sender_id  INT NOT NULL,
  body       MEDIUMTEXT NOT NULL,
  created_at DATETIME NOT NULL,
  -- Covers relay_poll's own lookup (match_id + sender_id + seq) exactly,
  -- so each iteration of its wait loop stays a fast index lookup instead
  -- of a range scan filtered row-by-row, no matter how long a match's
  -- history gets.
  INDEX idx_match_sender_seq (match_id, sender_id, seq),
  CONSTRAINT fk_mm_match FOREIGN KEY (match_id)
    REFERENCES matches(id) ON DELETE CASCADE
) ENGINE=InnoDB;
