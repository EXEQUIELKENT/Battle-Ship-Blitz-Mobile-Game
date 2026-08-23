-- Battleship Blitz — upgrade an existing database with a covering index
-- for relay_poll's message lookup.
--
-- relay_poll filters match_msgs by (match_id, sender_id, seq) on every
-- iteration of its wait loop, once per poll, for as long as the match
-- runs. The original idx_match_seq only covered (match_id, seq), so
-- MySQL/MariaDB had to walk and filter sender_id row-by-row once a
-- match's history grew — this replaces it with an index that covers the
-- query exactly.
--
-- Safe to run more than once (MariaDB 10.4+ / MySQL 8: IF NOT EXISTS /
-- IF EXISTS on the clauses).
--
--   C:\xampp\mysql\bin\mysql.exe -u root < server\migrate-relay-latency.sql

USE battleship_blitz;

ALTER TABLE match_msgs
  DROP INDEX IF EXISTS idx_match_seq,
  ADD INDEX IF NOT EXISTS idx_match_sender_seq (match_id, sender_id, seq);
