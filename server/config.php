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
