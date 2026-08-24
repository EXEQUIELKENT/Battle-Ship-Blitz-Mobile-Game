<?php
// Battleship Blitz online backend — connection settings.
//
// These are XAMPP's out-of-the-box defaults. To change them without
// editing this file (and without the change showing up in git), drop a
// `config.local.php` next to it returning just the keys you want to
// override — it is gitignored and wins over everything here.

$defaults = [
    'db_host' => '127.0.0.1',
    'db_port' => 3306,
    'db_name' => 'battleship_blitz',
    'db_user' => 'root',
    'db_pass' => '',

    // How long after a player's last request they stop counting as
    // online. Comfortably longer than the client's heartbeat interval, so
    // one dropped request doesn't blink them offline in friends' lists.
    'online_window_seconds' => 35,

    // Longest a relay poll holds the connection open waiting for the
    // opponent to say something. Longer means lower latency and fewer
    // requests; too long and Apache runs out of workers. Must stay
    // comfortably under the client's own request timeout.
    'poll_hold_seconds' => 8,

    // How often relay_poll re-checks the database while it holds the
    // connection open, split into two phases. During a live match a
    // reply almost always shows up within a second or two of the poll
    // starting — the opponent is actively taking their turn — so the
    // FAST phase checks tightly to shave that latency down. Once the
    // wait drags past `poll_fast_window_seconds` (nobody has moved in a
    // while), it backs off to the gentler SLOW interval so a long-held
    // idle connection isn't spinning the database the whole time.
    'poll_fast_window_seconds' => 1.5,
    'poll_fast_interval_us'    => 20000,   // 20ms during the fast phase
    'poll_slow_interval_us'    => 100000,  // 100ms after backing off

    // How long the LOBBY long-poll (the `poll` action, when the
    // matchmaking screen asks it to `wait`) holds the connection open
    // waiting for something matchmaking-relevant to change — a pairing
    // found, an accept landing, a release. Shorter than
    // `poll_hold_seconds` on purpose: this is a background screen
    // watching for one of a few discrete events, not a live match, so
    // there is no reason to tie up a worker as long.
    'lobby_poll_hold_seconds' => 4,

    // How often the lobby long-poll rechecks while holding. Coarser than
    // the in-match `poll_fast_interval_us` — matchmaking events (another
    // human tapping accept) don't need 20ms precision the way a shot
    // landing mid-rally does, and this loop is competing with every
    // other matchmaking player's own hold for the same database.
    'lobby_poll_interval_us' => 150000, // 150ms

    // How long a "MATCH FOUND" prompt stays open while waiting for both
    // captains to accept. After this with no second yes, the pairing is
    // released and both players go back to searching.
    'pair_hold_seconds' => 30,

    // How long a declined pairing is avoided before that opponent becomes
    // a normal candidate again. Not a hard block — see `queue_join`'s
    // candidate query — just a preference for a different opponent while
    // one is available, so two players stuck in a small online population
    // still end up back together rather than never matching at all.
    'avoid_rematch_seconds' => 300,
];

$local = [];
$localPath = __DIR__ . '/config.local.php';
if (file_exists($localPath)) {
    $loaded = require $localPath;
    if (is_array($loaded)) {
        $local = $loaded;
    }
}

return array_merge($defaults, $local);
