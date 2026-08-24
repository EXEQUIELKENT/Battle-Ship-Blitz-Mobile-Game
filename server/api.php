<?php
/**
 * Battleship Blitz — online play backend.
 *
 * One front controller. Every request is POST with a JSON body carrying
 * an `a` (action) field; every response is JSON. server/README.md has the
 * endpoint list, the setup steps and the design notes.
 *
 * The design in one line: this server does account/friends/presence work
 * itself, and for the match itself it is nothing but a post box. The two
 * clients exchange exactly the same JSON lines they would have written to
 * a TCP socket in a hotspot match — the relay stores them and hands them
 * back in order, so the entire game protocol (mode vote, fleet exchange,
 * firing, manoeuvres, reconnect, rematch) works over the internet without
 * a single change to the game logic on either end.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
// The game is a native app, not a browser page, so CORS is not strictly
// needed — but the Flutter web build talks to this too, and allowing it
// costs nothing here.
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$config = require __DIR__ . '/config.php';

// ---------------------------------------------------------------- helpers

function respond(array $payload, int $status = 200): void
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(string $message, int $status = 400): void
{
    respond(['ok' => false, 'error' => $message], $status);
}

function db(array $config): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
        $config['db_host'],
        (int) $config['db_port'],
        $config['db_name']
    );
    try {
        $pdo = new PDO($dsn, $config['db_user'], $config['db_pass'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            // Every action on this file is a brand-new PHP process/request
            // (there is no app server keeping state between them), so
            // without this, EVERY call — including `relay_send` on every
            // shot fired and each iteration of the matchmaking/relay long
            // polls re-connecting on the next request — pays a fresh TCP
            // (and on some hosts, auth) handshake to MySQL before it can
            // even run its first query. A persistent connection is keyed
            // to the (host, user, db) triple and reused by the *same* PHP
            // worker process on its next request, which is exactly the
            // pattern a poll-then-immediately-repoll loop produces. Safe
            // here because nothing in this file opens a transaction that
            // could be left dangling for the next request to inherit.
            PDO::ATTR_PERSISTENT         => true,
        ]);
    } catch (PDOException $e) {
        // Deliberately vague to the client, specific in the server log:
        // a connection string is not something to hand out.
        error_log('battleship_blitz: DB connect failed: ' . $e->getMessage());
        fail('The game server cannot reach its database.', 503);
    }
    return $pdo;
}

function body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function str_field(array $in, string $key, int $max, string $default = ''): string
{
    $value = isset($in[$key]) && is_scalar($in[$key]) ? trim((string) $in[$key]) : $default;
    if ($value === '') {
        $value = $default;
    }
    // mb_substr keeps a multi-byte name from being cut mid-character.
    return mb_substr($value, 0, $max);
}

function int_field(array $in, string $key, int $default = 0): int
{
    return isset($in[$key]) && is_numeric($in[$key]) ? (int) $in[$key] : $default;
}

/** A short, unambiguous friend code. No O/0/I/1 — these get read aloud. */
function make_tag(PDO $pdo): string
{
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for ($attempt = 0; $attempt < 40; $attempt++) {
        $tag = '';
        for ($i = 0; $i < 6; $i++) {
            $tag .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        $stmt = $pdo->prepare('SELECT 1 FROM players WHERE tag = ?');
        $stmt->execute([$tag]);
        if (!$stmt->fetchColumn()) {
            return $tag;
        }
    }
    fail('Could not allocate a friend code — try again.', 503);
}

/**
 * Resolves the caller from their token and stamps `last_seen`.
 *
 * That stamp is the entire presence system: any request at all counts as
 * "I am here", so the heartbeat the friends screen already makes keeps a
 * player visibly online without a second mechanism, and a player who
 * force-quits simply stops stamping and fades out on their friends'
 * screens once the window lapses.
 */
function require_player(PDO $pdo, array $in): array
{
    $token = str_field($in, 'token', 128);
    if ($token === '') {
        fail('Not signed in.', 401);
    }
    $hash = hash('sha256', $token);
    $stmt = $pdo->prepare('SELECT * FROM players WHERE token_hash = ?');
    $stmt->execute([$hash]);
    $player = $stmt->fetch();
    if (!$player) {
        fail('Not signed in.', 401);
    }
    $pdo->prepare('UPDATE players SET last_seen = NOW() WHERE id = ?')
        ->execute([$player['id']]);
    return $player;
}

/** The public shape of a player — never includes the token hash. */
function public_player(array $row, int $onlineWindow): array
{
    return [
        'id'          => (int) $row['id'],
        'tag'         => $row['tag'],
        'name'        => $row['name'],
        'rp'          => (int) $row['rp'],
        'wins'        => (int) $row['wins'],
        'losses'      => (int) $row['losses'],
        'bestStreak'  => (int) $row['best_streak'],
        'ship'        => $row['ship_skin'],
        'shipChosen'  => ((int) $row['ship_chosen']) === 1,
        'cannon'      => $row['cannon_skin'],
        'theme'       => $row['theme'],
        'online'      => isset($row['seconds_since_seen'])
            ? ((int) $row['seconds_since_seen']) <= $onlineWindow
            : false,
        'lastSeenAgo' => isset($row['seconds_since_seen'])
            ? (int) $row['seconds_since_seen']
            : null,
    ];
}

/** The match's shape as the client sees it, from either seat. */
function match_payload(array $m, int $myId): array
{
    $iAmHost = ((int) $m['host_id']) === $myId;
    // Both captains have to agree before a matchmaking pairing opens the
    // relay — these two flags are what the "waiting for them" state reads.
    $iAccepted = $iAmHost
        ? ((int) $m['host_ready']) === 1
        : ((int) $m['guest_ready']) === 1;
    $peerAccepted = $iAmHost
        ? ((int) $m['guest_ready']) === 1
        : ((int) $m['host_ready']) === 1;
    return [
        'id'           => (int) $m['id'],
        'status'       => $m['status'],
        'youAreHost'   => $iAmHost,
        'peerId'       => $iAmHost ? (int) $m['guest_id'] : (int) $m['host_id'],
        'peerName'     => $iAmHost ? $m['guest_name'] : $m['host_name'],
        'youAccepted'  => $iAccepted,
        'peerAccepted' => $peerAccepted,
    ];
}

/**
 * Housekeeping for the find-a-match queue, safe to call from any request
 * that touches it: forget searches whose owner has gone quiet, and
 * release pairings neither captain accepted in time so both players
 * return to the lobby instead of staring at a dead prompt forever.
 */
function sweep_matchmaking(PDO $pdo, int $queueTtl, int $pairTtl, int $avoidTtl): void
{
    $pdo->prepare(
        'DELETE q FROM matchmaking q
         JOIN players p ON p.id = q.player_id
         WHERE TIMESTAMPDIFF(SECOND, p.last_seen, NOW()) > ?'
    )->execute([$queueTtl]);

    $pdo->prepare(
        "UPDATE matches SET status = 'done', updated_at = NOW()
         WHERE status = 'found'
           AND updated_at < NOW() - INTERVAL ? SECOND"
    )->execute([$pairTtl]);

    // Expired "just declined this player" preferences — after this window
    // a previously-declined opponent is a normal candidate again instead
    // of being passed over forever.
    $pdo->prepare(
        'DELETE FROM matchmaking_avoid
         WHERE created_at < NOW() - INTERVAL ? SECOND'
    )->execute([$avoidTtl]);
}

/**
 * Everything the friends/matchmaking screens need in one shot: friends
 * with live presence, incoming/outgoing requests, the one live match (if
 * any), and whether this player is still in the find-a-match queue.
 * Pulled out of the `poll` action so the lobby long-poll below can call
 * it repeatedly without duplicating the queries.
 */
function poll_state(PDO $pdo, array $me, int $window): array
{
    // Every placeholder is distinct even where the value repeats:
    // native (non-emulated) prepares will not let one named parameter
    // be bound to several positions.
    $stmt = $pdo->prepare(
        "SELECT p.*, TIMESTAMPDIFF(SECOND, p.last_seen, NOW()) AS seconds_since_seen,
                f.status, f.requester_id
         FROM friendships f
         JOIN players p
           ON p.id = IF(f.requester_id = :me_side, f.addressee_id, f.requester_id)
         WHERE f.requester_id = :me_req OR f.addressee_id = :me_addr
         ORDER BY (TIMESTAMPDIFF(SECOND, p.last_seen, NOW()) <= :win) DESC, p.name ASC"
    );
    $stmt->execute([
        'me_side' => $me['id'],
        'me_req'  => $me['id'],
        'me_addr' => $me['id'],
        'win'     => $window,
    ]);

    $friends = [];
    $incoming = [];
    $outgoing = [];
    foreach ($stmt->fetchAll() as $row) {
        $entry = public_player($row, $window);
        if ($row['status'] === 'accepted') {
            $friends[] = $entry;
        } elseif ((int) $row['requester_id'] === (int) $me['id']) {
            $outgoing[] = $entry;
        } else {
            $incoming[] = $entry;
        }
    }

    // Any live match involving me — an invitation I have been sent, one
    // I have sent, a matchmaking pairing waiting on accepts, or a game
    // already under way.
    $stmt = $pdo->prepare(
        "SELECT m.*, h.name AS host_name, g.name AS guest_name
         FROM matches m
         JOIN players h ON h.id = m.host_id
         JOIN players g ON g.id = m.guest_id
         WHERE (m.host_id = ? OR m.guest_id = ?) AND m.status <> 'done'
         ORDER BY m.id DESC LIMIT 1"
    );
    $stmt->execute([$me['id'], $me['id']]);
    $matchRow = $stmt->fetch();
    $match = $matchRow ? match_payload($matchRow, (int) $me['id']) : null;

    // Am I still standing in the find-a-match queue?
    $stmt = $pdo->prepare('SELECT 1 FROM matchmaking WHERE player_id = ?');
    $stmt->execute([$me['id']]);
    $searching = (bool) $stmt->fetchColumn();

    return [
        'friends'   => $friends,
        'incoming'  => $incoming,
        'outgoing'  => $outgoing,
        'match'     => $match,
        'searching' => $searching,
    ];
}

/**
 * A fingerprint of only the parts of [poll_state] worth waking a long
 * poll up for: a pairing found, an accept landing, a request arriving,
 * search state flipping. Deliberately excludes anything that free-runs
 * on its own — `seconds_since_seen`/`online` tick over on a timer with
 * no real event behind them — or the very first recheck inside the hold
 * would already look "changed" and the long poll would never actually
 * hold, defeating the point.
 */
function poll_fingerprint(array $state): string
{
    $ids = static fn(array $players) => array_map(
        static fn(array $p) => (int) $p['id'],
        $players
    );
    $m = $state['match'];
    return md5(json_encode([
        'f' => $ids($state['friends']),
        'i' => $ids($state['incoming']),
        'o' => $ids($state['outgoing']),
        's' => $state['searching'],
        'm' => $m === null
            ? null
            : [$m['id'], $m['status'], $m['youAccepted'], $m['peerAccepted']],
    ]));
}

$in     = body();
$action = str_field($in, 'a', 32);
$pdo    = db($config);
$window = (int) $config['online_window_seconds'];

switch ($action) {

    // ------------------------------------------------------------ health
    case 'ping':
        respond(['ok' => true, 'service' => 'battleship-blitz', 'version' => 1]);

    // ---------------------------------------------------------- register
    //
    // Creates an account for this installation and returns the token the
    // app stores locally. Called once, on first entry to the online
    // screen; after that the app just reuses its saved token.
    case 'register': {
        $name = str_field($in, 'name', 32, 'Captain');
        $token = bin2hex(random_bytes(32));
        $tag = make_tag($pdo);
        $stmt = $pdo->prepare(
            'INSERT INTO players (tag, name, token_hash, last_seen, created_at)
             VALUES (?, ?, ?, NOW(), NOW())'
        );
        $stmt->execute([$tag, $name, hash('sha256', $token)]);
        $id = (int) $pdo->lastInsertId();
        respond(['ok' => true, 'id' => $id, 'tag' => $tag, 'token' => $token]);
    }

    // -------------------------------------------------------------- sync
    //
    // Pushes this device's local profile up so friends see current stats.
    // The game stays entirely playable offline, so the device's own copy
    // is the authority here — the server is a mirror for other people to
    // read, not a scoreboard to be defended.
    case 'sync': {
        $me = require_player($pdo, $in);
        $stmt = $pdo->prepare(
            'UPDATE players SET name = ?, rp = ?, wins = ?, losses = ?,
                    best_streak = ?, ship_skin = ?, ship_chosen = ?,
                    cannon_skin = ?, theme = ?
             WHERE id = ?'
        );
        $stmt->execute([
            str_field($in, 'name', 32, $me['name']),
            max(0, int_field($in, 'rp', (int) $me['rp'])),
            max(0, int_field($in, 'wins', (int) $me['wins'])),
            max(0, int_field($in, 'losses', (int) $me['losses'])),
            max(0, int_field($in, 'bestStreak', (int) $me['best_streak'])),
            str_field($in, 'ship', 24, $me['ship_skin']),
            !empty($in['shipChosen']) ? 1 : 0,
            str_field($in, 'cannon', 24, $me['cannon_skin']),
            str_field($in, 'theme', 24, $me['theme']),
            $me['id'],
        ]);
        respond(['ok' => true]);
    }

    // -------------------------------------------------------------- poll
    //
    // The friends screen's heartbeat. One request returns everything that
    // screen shows — friends with live presence and stats, incoming and
    // outgoing requests, and any invitation waiting — so presence costs
    // no extra traffic beyond what the UI already needs.
    //
    // `wait: true` (sent only by the matchmaking screen's fast heartbeat,
    // see `OnlineService.startHeartbeat`) turns this into a long poll,
    // the same idea `relay_poll` uses for the match itself: if nothing
    // matchmaking-relevant has changed since the caller's `sinceHash`,
    // hold the connection and recheck for up to `lobby_poll_hold_seconds`
    // instead of answering "nothing new" immediately. That is what makes
    // "they accepted!" land in a blink rather than on the next fixed
    // interval — without it, this action was a plain read fired every
    // 1.2s by a client-side timer regardless of whether anything had
    // actually happened, which is both slower to notice a real change
    // (up to a full tick late) and busier than it needed to be (a request
    // every 1.2s for as long as the screen is open, change or not).
    case 'poll': {
        $me = require_player($pdo, $in);

        $wait = !empty($in['wait']);
        $sinceHash = str_field($in, 'sinceHash', 32);

        $state = poll_state($pdo, $me, $window);
        $hash = poll_fingerprint($state);

        if ($wait && $sinceHash !== '' && $hash === $sinceHash) {
            ignore_user_abort(false);
            @set_time_limit((int) $config['lobby_poll_hold_seconds'] + 10);
            $deadline = microtime(true) + (float) $config['lobby_poll_hold_seconds'];
            while (microtime(true) < $deadline) {
                usleep((int) $config['lobby_poll_interval_us']);
                $state = poll_state($pdo, $me, $window);
                $hash = poll_fingerprint($state);
                if ($hash !== $sinceHash) {
                    break;
                }
            }
        }

        respond([
            'ok'        => true,
            'me'        => public_player(
                $me + ['seconds_since_seen' => 0],
                $window
            ),
            'friends'   => $state['friends'],
            'incoming'  => $state['incoming'],
            'outgoing'  => $state['outgoing'],
            'match'     => $state['match'],
            'searching' => $state['searching'],
            'stateHash' => $hash,
        ]);
    }

    // -------------------------------------------------------------- find
    //
    // Search for captains to add as friends. A query matches a player's
    // NAME — prefix match, so "ken" finds Kent — or, for anyone who still
    // has an old code handy, their exact friend code. Names are how
    // players find each other now; codes remain as a fallback.
    case 'find': {
        require_player($pdo, $in);
        $q = str_field($in, 'q', 32);
        if ($q === '') {
            fail('Type a captain\'s name.');
        }
        // LIKE wildcards in a searched name must stay literal. Exact
        // matches first, then whoever was seen most recently — an active
        // captain beats a dormant lookalike from months ago.
        $prefix = addcslashes($q, '\\%_');
        $stmt = $pdo->prepare(
            'SELECT *, TIMESTAMPDIFF(SECOND, last_seen, NOW()) AS seconds_since_seen
             FROM players
             WHERE name LIKE ? OR tag = ?
             ORDER BY (name = ?) DESC, seconds_since_seen ASC, name ASC, id ASC
             LIMIT 12'
        );
        $stmt->execute(["{$prefix}%", strtoupper($q), $q]);
        $out = [];
        foreach ($stmt->fetchAll() as $row) {
            $out[] = public_player($row, $window);
        }
        respond(['ok' => true, 'players' => $out]);
    }

    // ----------------------------------------------------------- request
    //
    // The target may be given by id (straight off a search result) or,
    // for older clients, by friend code.
    case 'request': {
        $me = require_player($pdo, $in);
        $otherId = int_field($in, 'playerId');
        if ($otherId === 0) {
            $tag = strtoupper(str_field($in, 'tag', 8));
            $stmt = $pdo->prepare('SELECT id FROM players WHERE tag = ?');
            $stmt->execute([$tag]);
            $otherId = (int) ($stmt->fetchColumn() ?: 0);
        }
        if ($otherId === 0) {
            fail('No captain found.', 404);
        }
        if ($otherId === (int) $me['id']) {
            fail('That would be adding yourself.');
        }

        // If they already asked us, accept instead of creating a mirrored
        // pending row — otherwise two people adding each other at the same
        // time would sit forever, each waiting on the other.
        $stmt = $pdo->prepare(
            'SELECT id, status, requester_id FROM friendships
             WHERE (requester_id = ? AND addressee_id = ?)
                OR (requester_id = ? AND addressee_id = ?)'
        );
        $stmt->execute([$me['id'], $otherId, $otherId, $me['id']]);
        $existing = $stmt->fetch();

        if ($existing) {
            if ($existing['status'] === 'accepted') {
                respond(['ok' => true, 'status' => 'accepted']);
            }
            if ((int) $existing['requester_id'] === $otherId) {
                $pdo->prepare("UPDATE friendships SET status = 'accepted' WHERE id = ?")
                    ->execute([$existing['id']]);
                respond(['ok' => true, 'status' => 'accepted']);
            }
            respond(['ok' => true, 'status' => 'pending']);
        }

        $pdo->prepare(
            'INSERT INTO friendships (requester_id, addressee_id, status, created_at)
             VALUES (?, ?, ?, NOW())'
        )->execute([$me['id'], $otherId, 'pending']);
        respond(['ok' => true, 'status' => 'pending']);
    }

    // ----------------------------------------------------------- respond
    case 'respond': {
        $me = require_player($pdo, $in);
        $otherId = int_field($in, 'playerId');
        $accept = !empty($in['accept']);
        // Only the ADDRESSEE may accept: answering your own request would
        // let anyone friend anybody unilaterally.
        $stmt = $pdo->prepare(
            "SELECT id FROM friendships
             WHERE requester_id = ? AND addressee_id = ? AND status = 'pending'"
        );
        $stmt->execute([$otherId, $me['id']]);
        $id = (int) ($stmt->fetchColumn() ?: 0);
        if ($id === 0) {
            fail('That request is no longer waiting.', 404);
        }
        if ($accept) {
            $pdo->prepare("UPDATE friendships SET status = 'accepted' WHERE id = ?")
                ->execute([$id]);
        } else {
            $pdo->prepare('DELETE FROM friendships WHERE id = ?')->execute([$id]);
        }
        respond(['ok' => true]);
    }

    // ---------------------------------------------------------- unfriend
    case 'unfriend': {
        $me = require_player($pdo, $in);
        $otherId = int_field($in, 'playerId');
        $pdo->prepare(
            'DELETE FROM friendships
             WHERE (requester_id = ? AND addressee_id = ?)
                OR (requester_id = ? AND addressee_id = ?)'
        )->execute([$me['id'], $otherId, $otherId, $me['id']]);
        respond(['ok' => true]);
    }

    // ------------------------------------------------------------ invite
    //
    // The inviter becomes the match HOST, which is what makes them the red
    // fleet and gives them the opening shot — the same thing hosting a
    // hotspot room does.
    case 'invite': {
        $me = require_player($pdo, $in);
        $friendId = int_field($in, 'playerId');

        $stmt = $pdo->prepare(
            "SELECT 1 FROM friendships
             WHERE status = 'accepted'
               AND ((requester_id = ? AND addressee_id = ?)
                 OR (requester_id = ? AND addressee_id = ?))"
        );
        $stmt->execute([$me['id'], $friendId, $friendId, $me['id']]);
        if (!$stmt->fetchColumn()) {
            fail('You can only invite friends.', 403);
        }

        // One live match per player. Clearing ours first means a stale
        // invitation nobody ever answered can't wedge the button forever.
        $pdo->prepare(
            "UPDATE matches SET status = 'done', updated_at = NOW()
             WHERE (host_id = ? OR guest_id = ?) AND status <> 'done'"
        )->execute([$me['id'], $me['id']]);

        $stmt = $pdo->prepare(
            "SELECT 1 FROM matches
             WHERE (host_id = ? OR guest_id = ?)
               AND status IN ('active', 'found')"
        );
        $stmt->execute([$friendId, $friendId]);
        if ($stmt->fetchColumn()) {
            fail('That captain is already heading into a battle.', 409);
        }

        $pdo->prepare(
            "INSERT INTO matches (host_id, guest_id, status, created_at, updated_at)
             VALUES (?, ?, 'inviting', NOW(), NOW())"
        )->execute([$me['id'], $friendId]);
        respond(['ok' => true, 'matchId' => (int) $pdo->lastInsertId()]);
    }

    // ---------------------------------------------------- invite_respond
    case 'invite_respond': {
        $me = require_player($pdo, $in);
        $matchId = int_field($in, 'matchId');
        $accept = !empty($in['accept']);
        $stmt = $pdo->prepare(
            "SELECT * FROM matches WHERE id = ? AND guest_id = ? AND status = 'inviting'"
        );
        $stmt->execute([$matchId, $me['id']]);
        if (!$stmt->fetch()) {
            fail('That invitation has expired.', 404);
        }
        $pdo->prepare('UPDATE matches SET status = ?, updated_at = NOW() WHERE id = ?')
            ->execute([$accept ? 'active' : 'done', $matchId]);
        respond(['ok' => true]);
    }

    // -------------------------------------------------------- queue_join
    //
    // "Find a match". Puts this captain in the search queue; if somebody
    // is already waiting, pairs them on the spot. A pairing is a match in
    // status 'found' — NEITHER side has agreed yet, and both must accept
    // (see `accept_match`) before it turns 'active' and the relay opens.
    //
    // Pairing runs under a server-wide named lock so two joiners tapping
    // at the same moment can never both grab the same waiting opponent.
    case 'queue_join': {
        $me = require_player($pdo, $in);

        $stmt = $pdo->prepare(
            "SELECT 1 FROM matches
             WHERE (host_id = ? OR guest_id = ?) AND status = 'active'"
        );
        $stmt->execute([$me['id'], $me['id']]);
        if ($stmt->fetchColumn()) {
            fail('You are already in a battle.', 409);
        }

        // A forgotten invitation or an old pairing nobody answered would
        // otherwise shadow every poll with stale news.
        $pdo->prepare(
            "UPDATE matches SET status = 'done', updated_at = NOW()
             WHERE (host_id = ? OR guest_id = ?)
               AND status IN ('inviting', 'found')"
        )->execute([$me['id'], $me['id']]);

        $gotLock = $pdo->query("SELECT GET_LOCK('bbz_matchmaking', 5)")
            ->fetchColumn();
        if (!$gotLock) {
            fail('Matchmaking is busy — try again.', 503);
        }

        $matched = null;
        try {
            sweep_matchmaking(
                $pdo,
                $window + 10,
                (int) $config['pair_hold_seconds'],
                (int) $config['avoid_rematch_seconds']
            );

            // The captain who has been searching longest and is still
            // online — and not already sitting in some other live match.
            //
            // A recently-declined pairing (either direction: I declined
            // them, or they declined me) is only PREFERRED against, not
            // excluded outright — the ORDER BY pushes them to the back of
            // the line rather than dropping them from it. That's what
            // gives a decline "find someone else if you can" behaviour
            // without leaving two players who are the only ones online
            // unable to ever match at all: if the avoided captain is the
            // sole candidate, they're still the row this query returns.
            $stmt = $pdo->prepare(
                'SELECT q.player_id FROM matchmaking q
                 JOIN players p ON p.id = q.player_id
                 LEFT JOIN matches m
                   ON (m.host_id = q.player_id OR m.guest_id = q.player_id)
                  AND m.status <> \'done\'
                 LEFT JOIN matchmaking_avoid av
                   ON (av.player_id = ? AND av.avoid_id = q.player_id)
                   OR (av.player_id = q.player_id AND av.avoid_id = ?)
                 WHERE q.player_id <> ?
                   AND TIMESTAMPDIFF(SECOND, p.last_seen, NOW()) <= ?
                 GROUP BY q.player_id
                 HAVING COUNT(m.id) = 0
                 ORDER BY (MAX(av.player_id) IS NOT NULL) ASC, q.joined_at ASC
                 LIMIT 1'
            );
            $stmt->execute([$me['id'], $me['id'], $me['id'], $window]);
            $opponentId = (int) ($stmt->fetchColumn() ?: 0);

            if ($opponentId !== 0) {
                // Whoever waited first hosts — they asked for a battle
                // before we did, so they take the red fleet and the
                // opening shot, exactly as an inviter would.
                $pdo->beginTransaction();
                $pdo->prepare('DELETE FROM matchmaking WHERE player_id IN (?, ?)')
                    ->execute([$opponentId, $me['id']]);
                $pdo->prepare(
                    "INSERT INTO matches (host_id, guest_id, status,
                                          host_ready, guest_ready,
                                          created_at, updated_at)
                     VALUES (?, ?, 'found', 0, 0, NOW(), NOW())"
                )->execute([$opponentId, $me['id']]);
                $matchId = (int) $pdo->lastInsertId();
                $pdo->commit();

                $stmt = $pdo->prepare(
                    'SELECT m.*, h.name AS host_name, g.name AS guest_name
                     FROM matches m
                     JOIN players h ON h.id = m.host_id
                     JOIN players g ON g.id = m.guest_id
                     WHERE m.id = ?'
                );
                $stmt->execute([$matchId]);
                $matched = match_payload((array) $stmt->fetch(), (int) $me['id']);
            } else {
                // Nobody waiting: stand in line. Re-joining keeps your
                // original place rather than letting refreshes jump it.
                $pdo->prepare(
                    'INSERT IGNORE INTO matchmaking (player_id, joined_at)
                     VALUES (?, NOW())'
                )->execute([$me['id']]);
            }
        } finally {
            $pdo->query("SELECT RELEASE_LOCK('bbz_matchmaking')");
        }

        respond([
            'ok'        => true,
            'searching' => $matched === null,
            'match'     => $matched,
        ]);
    }

    // ------------------------------------------------------- queue_leave
    //
    // Stop searching — and, if a pairing was already found, decline it:
    // backing out of "MATCH FOUND" is how you say no thanks.
    case 'queue_leave': {
        $me = require_player($pdo, $in);
        $pdo->prepare('DELETE FROM matchmaking WHERE player_id = ?')
            ->execute([$me['id']]);

        // If we were mid-pairing, leaving IS declining it: remember who,
        // so our next queue_join prefers a different opponent instead of
        // immediately landing back on the one we just said no to (see the
        // ORDER BY in queue_join). Only a live 'found' pairing counts —
        // just backing out of the search queue with nobody offered yet
        // has no one to remember.
        $stmt = $pdo->prepare(
            "SELECT * FROM matches
             WHERE (host_id = ? OR guest_id = ?) AND status = 'found'"
        );
        $stmt->execute([$me['id'], $me['id']]);
        $declined = $stmt->fetch();
        if ($declined) {
            $peerId = ((int) $declined['host_id']) === ((int) $me['id'])
                ? (int) $declined['guest_id']
                : (int) $declined['host_id'];
            $pdo->prepare(
                'INSERT INTO matchmaking_avoid (player_id, avoid_id, created_at)
                 VALUES (?, ?, NOW())
                 ON DUPLICATE KEY UPDATE created_at = NOW()'
            )->execute([$me['id'], $peerId]);
        }

        $pdo->prepare(
            "UPDATE matches SET status = 'done', updated_at = NOW()
             WHERE (host_id = ? OR guest_id = ?) AND status = 'found'"
        )->execute([$me['id'], $me['id']]);
        respond(['ok' => true]);
    }

    // ------------------------------------------------------ accept_match
    //
    // One captain's yes to a found pairing. The second yes flips the
    // match to 'active' for BOTH players, which is what sends them into
    // the ordinary match flow together.
    case 'accept_match': {
        $me = require_player($pdo, $in);
        $matchId = int_field($in, 'matchId');

        $stmt = $pdo->prepare(
            'SELECT * FROM matches
             WHERE id = ? AND (host_id = ? OR guest_id = ?)
               AND status = \'found\''
        );
        $stmt->execute([$matchId, $me['id'], $me['id']]);
        $m = $stmt->fetch();
        if (!$m) {
            fail('That match is no longer being offered.', 404);
        }

        $mine = ((int) $m['host_id']) === ((int) $me['id'])
            ? 'host_ready'
            : 'guest_ready';
        $theirs = $mine === 'host_ready' ? 'guest_ready' : 'host_ready';

        // Accepting also refreshes updated_at, which is what the expiry
        // sweep measures: each acceptance buys fresh time for the other
        // captain to answer.
        $newStatus = ((int) $m[$theirs]) === 1 ? 'active' : 'found';
        $stmt = $pdo->prepare(
            "UPDATE matches SET {$mine} = 1, status = ?, updated_at = NOW()
             WHERE id = ?"
        );
        $stmt->execute([$newStatus, $matchId]);

        respond(['ok' => true, 'status' => $newStatus]);
    }

    // --------------------------------------------------------- match_end
    case 'match_end': {
        $me = require_player($pdo, $in);
        $matchId = int_field($in, 'matchId');
        $pdo->prepare(
            "UPDATE matches SET status = 'done', updated_at = NOW()
             WHERE id = ? AND (host_id = ? OR guest_id = ?)"
        )->execute([$matchId, $me['id'], $me['id']]);
        respond(['ok' => true]);
    }

    // -------------------------------------------------------- relay_send
    //
    // Posts one or more protocol lines into the match. Batched because the
    // game happily sends two or three in the same frame (a vote plus a
    // tick, a fleet plus a hello) and one round trip is plenty.
    case 'relay_send': {
        $me = require_player($pdo, $in);
        $matchId = int_field($in, 'matchId');
        $lines = isset($in['lines']) && is_array($in['lines']) ? $in['lines'] : [];

        $stmt = $pdo->prepare(
            'SELECT * FROM matches WHERE id = ? AND (host_id = ? OR guest_id = ?)'
        );
        $stmt->execute([$matchId, $me['id'], $me['id']]);
        if (!$stmt->fetch()) {
            fail('Not in that match.', 403);
        }

        $insert = $pdo->prepare(
            'INSERT INTO match_msgs (match_id, sender_id, body, created_at)
             VALUES (?, ?, ?, NOW())'
        );
        foreach ($lines as $line) {
            if (!is_string($line) || $line === '') {
                continue;
            }
            // A protocol line is a single JSON object; anything larger is
            // not something this game sends.
            $insert->execute([$matchId, $me['id'], mb_substr($line, 0, 65535)]);
        }
        $pdo->prepare('UPDATE matches SET updated_at = NOW() WHERE id = ?')
            ->execute([$matchId]);
        respond(['ok' => true]);
    }

    // -------------------------------------------------------- relay_poll
    //
    // Long poll: returns immediately if the opponent has said anything
    // since `since`, otherwise holds the connection open for up to
    // `poll_hold_seconds` waiting for them to. That keeps a turn-based
    // match feeling close to instant without the client hammering the
    // server several times a second.
    case 'relay_poll': {
        $me = require_player($pdo, $in);
        $matchId = int_field($in, 'matchId');
        $since = int_field($in, 'since');

        $stmt = $pdo->prepare(
            'SELECT * FROM matches WHERE id = ? AND (host_id = ? OR guest_id = ?)'
        );
        $stmt->execute([$matchId, $me['id'], $me['id']]);
        $match = $stmt->fetch();
        if (!$match) {
            fail('Not in that match.', 403);
        }
        $peerId = ((int) $match['host_id']) === ((int) $me['id'])
            ? (int) $match['guest_id']
            : (int) $match['host_id'];

        // Don't keep working on a poll whose client has already hung up.
        ignore_user_abort(false);
        @set_time_limit((int) $config['poll_hold_seconds'] + 10);

        $fetch = $pdo->prepare(
            'SELECT seq, body FROM match_msgs
             WHERE match_id = ? AND sender_id = ? AND seq > ?
             ORDER BY seq ASC LIMIT 200'
        );
        $peerSeen = $pdo->prepare(
            'SELECT TIMESTAMPDIFF(SECOND, last_seen, NOW()) FROM players WHERE id = ?'
        );
        $matchState = $pdo->prepare('SELECT status FROM matches WHERE id = ?');

        $deadline = microtime(true) + (float) $config['poll_hold_seconds'];
        // See `poll_fast_window_seconds` in config.php: check tightly for
        // the first stretch of the wait, since that is when a live
        // opponent's move almost always lands, then back off once it is
        // clear this poll is just holding on an idle match.
        $fastUntil = microtime(true) + (float) $config['poll_fast_window_seconds'];
        $rows = [];
        while (true) {
            $fetch->execute([$matchId, $peerId, $since]);
            $rows = $fetch->fetchAll();
            if ($rows || microtime(true) >= $deadline) {
                break;
            }
            usleep(microtime(true) < $fastUntil
                ? (int) $config['poll_fast_interval_us']
                : (int) $config['poll_slow_interval_us']);
        }

        $peerSeen->execute([$peerId]);
        $peerAgo = $peerSeen->fetchColumn();
        $matchState->execute([$matchId]);
        $status = (string) $matchState->fetchColumn();

        $maxSeq = $since;
        $out = [];
        foreach ($rows as $row) {
            $out[] = $row['body'];
            $maxSeq = max($maxSeq, (int) $row['seq']);
        }

        respond([
            'ok'         => true,
            'seq'        => $maxSeq,
            'lines'      => $out,
            'status'     => $status,
            // "Have they touched the server recently" doubles as the
            // opponent-dropped signal the reconnect grace window needs.
            // The raw age goes along with it because a match wants a
            // tighter, faster threshold than a friends list does: both
            // players poll continuously while playing, so a few seconds
            // of silence already means something is wrong.
            'peerOnline' => $peerAgo !== false && ((int) $peerAgo) <= $window,
            'peerAgo'    => $peerAgo === false ? null : (int) $peerAgo,
        ]);
    }

    default:
        fail('Unknown action.', 404);
}
