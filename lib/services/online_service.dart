import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_api.dart';
import 'server_discovery.dart';
import 'storage_service.dart';

/// Another captain, as the online server knows them.
class OnlinePlayer {
  final int id;
  final String tag;
  final String name;
  final int rp;
  final int wins;
  final int losses;
  final int bestStreak;
  final String shipSkinId;
  final bool shipChosen;
  final String cannonSkinId;
  final String themeId;
  final bool online;

  /// Seconds since they last touched the server, or null if unknown.
  /// Drives the "LAST SEEN 4M AGO" line for offline friends.
  final int? lastSeenAgo;

  const OnlinePlayer({
    required this.id,
    required this.tag,
    required this.name,
    required this.rp,
    required this.wins,
    required this.losses,
    required this.bestStreak,
    required this.shipSkinId,
    required this.shipChosen,
    required this.cannonSkinId,
    required this.themeId,
    required this.online,
    required this.lastSeenAgo,
  });

  factory OnlinePlayer.fromJson(Map<String, dynamic> j) => OnlinePlayer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        tag: (j['tag'] as String?) ?? '------',
        name: (j['name'] as String?) ?? 'Captain',
        rp: (j['rp'] as num?)?.toInt() ?? 0,
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        losses: (j['losses'] as num?)?.toInt() ?? 0,
        bestStreak: (j['bestStreak'] as num?)?.toInt() ?? 0,
        shipSkinId: (j['ship'] as String?) ?? 'steel',
        shipChosen: j['shipChosen'] == true,
        cannonSkinId: (j['cannon'] as String?) ?? 'mk1',
        themeId: (j['theme'] as String?) ?? 'classic',
        online: j['online'] == true,
        lastSeenAgo: (j['lastSeenAgo'] as num?)?.toInt(),
      );

  String get rankTitle => rankTitleForRp(rp);

  int get played => wins + losses;

  /// Win rate as a whole percentage, or null before they've played.
  int? get winRate => played == 0 ? null : ((wins * 100) / played).round();

  /// "ONLINE NOW" / "LAST SEEN 4M AGO" / "OFFLINE".
  String get presenceLabel {
    if (online) return 'ONLINE NOW';
    final ago = lastSeenAgo;
    if (ago == null) return 'OFFLINE';
    if (ago < 3600) return 'LAST SEEN ${(ago / 60).floor()}M AGO';
    if (ago < 86400) return 'LAST SEEN ${(ago / 3600).floor()}H AGO';
    return 'LAST SEEN ${(ago / 86400).floor()}D AGO';
  }
}

/// A match this player is part of, as far as the server is concerned.
class OnlineMatch {
  final int id;

  /// `inviting` — a friend has been invited and hasn't answered yet.
  /// `found`    — matchmaking paired two searchers; BOTH must accept.
  /// `active`   — both sides are in; the relay is carrying the game.
  final String status;
  final bool youAreHost;
  final int peerId;
  final String peerName;

  /// For a matchmaking pairing (`found`): whether each captain has tapped
  /// accept. The match only goes live on the second yes.
  final bool youAccepted;
  final bool peerAccepted;

  const OnlineMatch({
    required this.id,
    required this.status,
    required this.youAreHost,
    required this.peerId,
    required this.peerName,
    this.youAccepted = false,
    this.peerAccepted = false,
  });

  factory OnlineMatch.fromJson(Map<String, dynamic> j) => OnlineMatch(
        id: (j['id'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? 'done',
        youAreHost: j['youAreHost'] == true,
        peerId: (j['peerId'] as num?)?.toInt() ?? 0,
        peerName: (j['peerName'] as String?) ?? 'Opponent',
        youAccepted: j['youAccepted'] == true,
        peerAccepted: j['peerAccepted'] == true,
      );

  bool get isInvitation => status == 'inviting';
  bool get isActive => status == 'active';
  bool get isFound => status == 'found';

  /// An invitation waiting for THIS player to answer.
  bool get isIncomingInvite => isInvitation && !youAreHost;

  /// An invitation this player sent that hasn't been answered.
  bool get isOutgoingInvite => isInvitation && youAreHost;
}

/// Accounts, friends, presence and invitations for internet play.
///
/// Deliberately separate from `NetworkService`, which owns the match
/// itself. This class gets two players as far as "we have agreed to
/// play"; from there `NetworkService` takes over with a `RelayLink` and
/// runs the identical match protocol hotspot play uses.
///
/// There are no usernames or passwords: the app registers itself once and
/// keeps the token it is given. That means a player's account lives on
/// the install — which suits a game whose profile, RP and purchases are
/// already local-only — and their friend code is how anyone else finds
/// them.
class OnlineService extends ChangeNotifier {
  static const _kBaseUrl = 'online.baseUrl';
  static const _kToken = 'online.token';
  static const _kTag = 'online.tag';
  static const _kId = 'online.id';

  final OnlineApi api = OnlineApi();

  SharedPreferences? _prefs;

  int myId = 0;
  String myTag = '';

  /// This player's captain name as the server knows it — the thing other
  /// people search for to add them.
  String myName = '';

  List<OnlinePlayer> friends = const [];
  List<OnlinePlayer> incomingRequests = const [];
  List<OnlinePlayer> outgoingRequests = const [];
  OnlineMatch? match;

  /// True while this player is standing in the find-a-match queue. The
  /// matchmaking screen reads it to tell "still searching" apart from
  /// "paired, waiting on accepts" and from "released, re-searching".
  bool searching = false;

  /// Last thing that went wrong, ready to show. Cleared by the next
  /// successful call.
  String? lastError;

  /// True once a call has actually succeeded, so the UI can tell "not set
  /// up yet" apart from "set up but unreachable".
  bool reachable = false;
  bool busy = false;

  Timer? _heartbeat;

  bool get configured => api.configured;
  bool get signedIn => configured && (api.token ?? '').isNotEmpty;
  String get baseUrl => api.baseUrl;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    api.baseUrl = p.getString(_kBaseUrl) ?? '';
    api.token = p.getString(_kToken);
    myTag = p.getString(_kTag) ?? '';
    myId = p.getInt(_kId) ?? 0;
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kBaseUrl, api.baseUrl);
    await p.setString(_kToken, api.token ?? '');
    await p.setString(_kTag, myTag);
    await p.setInt(_kId, myId);
  }

  /// Points the app at a server. Changing the address invalidates the
  /// account with it: the token was issued by the OLD server and means
  /// nothing to the new one, so keeping it would just produce confusing
  /// "not signed in" errors on every call.
  Future<void> setBaseUrl(String url) async {
    final next = url.trim();
    if (next == api.baseUrl) return;
    api.baseUrl = next;
    api.token = null;
    myTag = '';
    myId = 0;
    reachable = false;
    friends = const [];
    incomingRequests = const [];
    outgoingRequests = const [];
    match = null;
    searching = false;
    await _persist();
    notifyListeners();
  }

  /// The message shown when the device is simply offline — distinct from
  /// "server unreachable", because the fix (turn on data) is different.
  static const _offlineMessage = 'You need an internet connection to '
      'play online. Turn on Wi-Fi or mobile data and try again.';

  /// Finds the game server on its own — nobody types an address — and
  /// signs in against whatever it finds.
  ///
  /// Order: the address remembered from last time (fast path: an
  /// unchanged network answers in one ping), then localhost and the
  /// Android-emulator host, then a sweep of this device's Wi-Fi subnet.
  /// Only a machine speaking this game's exact protocol is accepted, so
  /// random web servers on the LAN are ignored.
  ///
  /// A release build carries its server's address inside the binary, so
  /// it needs real internet: with none, it fails here in one DNS check
  /// instead of sweeping, and the player is told exactly that.
  Future<bool> connectAuto(ProfileStore profile) async {
    busy = true;
    notifyListeners();
    final discovery = ServerDiscovery();

    // Release builds point at one far-away machine; without a route to
    // it there is nothing to find. Dev builds may still legitimately
    // reach a LAN-only XAMPP box with the router's internet down, so
    // they fall through and let discovery try.
    if (ServerDiscovery.bakedUrl.trim().isNotEmpty &&
        !await discovery.hasInternet()) {
      busy = false;
      reachable = false;
      lastError = _offlineMessage;
      notifyListeners();
      return false;
    }

    String? found;
    try {
      found = await discovery.discover(
        known: configured ? api.baseUrl : null,
      );
    } catch (_) {}
    if (found == null) {
      busy = false;
      reachable = false;
      lastError = await discovery.hasInternet()
          ? 'No game server found on this Wi-Fi. Ask whoever is hosting '
              'for its address and enter it below, or start '
              'server/api.php yourself and rejoin the same network.'
          : _offlineMessage;
      notifyListeners();
      return false;
    }
    if (found != api.baseUrl.trim()) {
      // A different machine than last time. The old token means nothing
      // to the new server, so setBaseUrl drops it along with everything
      // that came from the old session.
      await setBaseUrl(found);
    }
    return ensureAccount(profile);
  }

  /// Registers this installation if it has no account yet, then pushes
  /// the current local profile up. Safe to call every time the online
  /// screen opens.
  Future<bool> ensureAccount(ProfileStore profile) async {
    if (!configured) {
      lastError = 'Enter the game server address first.';
      notifyListeners();
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      if ((api.token ?? '').isEmpty) await _register(profile);

      // The saved token can be stale in ways that are nobody's fault: the
      // server's database was reset, the account was removed, or this
      // address is a different server than the one that issued it. All of
      // those come back as "not signed in", and all of them are fixed by
      // registering again rather than by showing the player an error
      // about a token they never knew they had.
      try {
        await api.call('poll');
      } on OnlineError catch (e) {
        if (!e.needsSignIn) rethrow;
        api.token = null;
        await _register(profile);
      }

      await syncProfile(profile);
      await refresh();
      reachable = true;
      lastError = null;
      return true;
    } on OnlineError catch (e) {
      lastError = e.offline ? _offlineMessage : e.message;
      reachable = false;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _register(ProfileStore profile) async {
    final res = await api.call(
      'register',
      args: {'name': profile.playerName},
      authed: false,
    );
    api.token = res['token'] as String?;
    myTag = (res['tag'] as String?) ?? '';
    myId = (res['id'] as num?)?.toInt() ?? 0;
    await _persist();
  }

  /// Mirrors the local profile up so friends see current stats and the
  /// right loadout. The device stays the authority — this is a copy for
  /// other people to read, not a score being submitted.
  ///
  /// Called from every online entry point AND right after a rename on the
  /// main menu, so the server never keeps showing a name the player
  /// already changed. On success the local display name updates too —
  /// instant feedback, no waiting for the next poll to echo it back.
  Future<void> syncProfile(ProfileStore profile) async {
    if (!signedIn) return;
    try {
      await api.call('sync', args: {
        'name': profile.playerName,
        'rp': profile.rp,
        'wins': profile.wins,
        'losses': profile.losses,
        'bestStreak': profile.bestStreak,
        'ship': profile.shipSkinId,
        'shipChosen': profile.shipSkinChosen,
        'cannon': profile.cannonSkinId,
        'theme': profile.gameplayThemeId,
      });
      if (myName != profile.playerName) {
        myName = profile.playerName;
        notifyListeners();
      }
    } on OnlineError catch (e) {
      if (kDebugMode) debugPrint('OnlineService: sync failed ($e)');
    }
  }

  /// One request that returns everything the friends screen shows AND
  /// keeps this player marked online — presence costs no extra traffic
  /// because any request at all counts as "I am here".
  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      final res = await api.call('poll');
      friends = _players(res['friends']);
      incomingRequests = _players(res['incoming']);
      outgoingRequests = _players(res['outgoing']);
      searching = res['searching'] == true;
      final m = res['match'];
      match = m is Map
          ? OnlineMatch.fromJson(Map<String, dynamic>.from(m))
          : null;
      final me = res['me'];
      if (me is Map) {
        myTag = (me['tag'] as String?) ?? myTag;
        myName = (me['name'] as String?) ?? myName;
        myId = (me['id'] as num?)?.toInt() ?? myId;
      }
      reachable = true;
      lastError = null;
    } on OnlineError catch (e) {
      // Offline moments say it in the player's own words, everywhere:
      // entry, mid-search heartbeats, invites — one message, one fix.
      lastError = e.offline ? _offlineMessage : e.message;
      if (e.offline) reachable = false;
    }
    notifyListeners();
  }

  List<OnlinePlayer> _players(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => OnlinePlayer.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Starts the presence heartbeat. Runs only while a screen that needs
  /// it is open — there is no reason to advertise as online from inside a
  /// single-player match against the AI.
  ///
  /// [fast] halves-and-halves-again the interval: while a matchmaking
  /// screen is up, "opponent accepted" should land in a blink, not on the
  /// next five-second tick.
  void startHeartbeat({bool fast = false}) {
    _heartbeat?.cancel();
    if (!signedIn) return;
    _fastPolling = fast;
    unawaited(refresh());
    _heartbeat = Timer.periodic(
      fast ? const Duration(milliseconds: 1200) : const Duration(seconds: 5),
      (_) => unawaited(refresh()),
    );
  }

  /// Switches an already-running heartbeat between the normal friends
  /// pace and the matchmaking pace without dropping it.
  void setFastPolling(bool fast) {
    if (_fastPolling == fast) return;
    startHeartbeat(fast: fast);
  }

  bool _fastPolling = false;

  // ------------------------------------------------------- MATCHMAKING ---

  /// Puts this captain in the find-a-match queue. The server answers
  /// either "searching" or "paired with X — both of you now accept";
  /// [_act]'s refresh pulls whichever it is into [match]/[searching].
  Future<bool> joinQueue() => _act(() => api.call('queue_join'));

  /// Stops searching. If a pairing was already found but not yet fully
  /// accepted by both sides, this doubles as declining it.
  Future<bool> leaveQueue() => _act(
        () => api.call('queue_leave'),
      );

  /// Says yes to a found pairing. The second yes anywhere flips the match
  /// active, which is what sends both captains into the game.
  Future<bool> acceptMatch(int matchId) => _act(
        () => api.call('accept_match', args: {'matchId': matchId}),
      );

  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ------------------------------------------------------------ FRIENDS ---

  /// Searches for captains to add. A query matches a player's NAME —
  /// prefix match, so "ken" finds Kent — or their friend code for anyone
  /// still swapping codes. Names are unique per player, which is what
  /// makes searching them a way to find exactly one person; if two
  /// players picked the same name anyway, both come back and the tag on
  /// each result tells them apart.
  Future<List<OnlinePlayer>> search(String q) async {
    try {
      final res = await api.call('find', args: {'q': q});
      lastError = null;
      return _players(res['players']);
    } on OnlineError catch (e) {
      lastError = e.message;
      notifyListeners();
      return const [];
    }
  }

  Future<bool> requestById(int playerId) => _act(
        () => api.call('request', args: {'playerId': playerId}),
      );

  Future<bool> respondToRequest(int playerId, bool accept) => _act(
        () => api.call(
            'respond', args: {'playerId': playerId, 'accept': accept}),
      );

  Future<bool> unfriend(int playerId) => _act(
        () => api.call('unfriend', args: {'playerId': playerId}),
      );

  // ------------------------------------------------------------ INVITES ---

  Future<bool> invite(int playerId) => _act(
        () => api.call('invite', args: {'playerId': playerId}),
      );

  Future<bool> respondToInvite(int matchId, bool accept) => _act(
        () => api.call(
            'invite_respond', args: {'matchId': matchId, 'accept': accept}),
      );

  /// The match currently being played, remembered independently of
  /// [match].
  ///
  /// [match] only exists as long as something is polling, and polling
  /// stops the moment a battle starts — so by the time the player leaves
  /// that battle the poll result is long stale. Holding the id here is
  /// what lets [endMatch] free the seat from any exit path, including the
  /// ones that unwind straight back to the main menu.
  int? _activeMatchId;

  void noteMatchStarted(int matchId) => _activeMatchId = matchId;

  bool get hasActiveMatch => _activeMatchId != null;

  /// Ends whatever match this player is in, on the server. Called when
  /// leaving a battle, and when cancelling an invitation — otherwise both
  /// players would keep being told they are "already in a battle".
  Future<void> endMatch() async {
    final id = _activeMatchId ?? match?.id;
    _activeMatchId = null;
    if (id == null) return;
    try {
      await api.call('match_end', args: {'matchId': id});
    } on OnlineError catch (e) {
      if (kDebugMode) debugPrint('OnlineService: match_end failed ($e)');
    }
    match = null;
    notifyListeners();
  }

  /// Runs an action, refreshes, and reports whether it worked — the shape
  /// every mutating call above shares.
  Future<bool> _act(Future<Map<String, dynamic>> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      await action();
      lastError = null;
      await refresh();
      return true;
    } on OnlineError catch (e) {
      lastError = e.offline ? _offlineMessage : e.message;
      notifyListeners();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}
