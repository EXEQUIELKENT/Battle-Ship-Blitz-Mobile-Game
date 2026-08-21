import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import 'online_api.dart';
import 'relay_link.dart';

/// Network modes supported by the game.
enum NetMode { none, hotspot, online }

/// TCP port used for hotspot (LAN) matches.
const int kGamePort = 45678;

/// Hotspot game room advertised to other players.
class RoomInfo {
  final String code;
  final String host;
  final String playerName;

  /// True when this beacon is a match ALREADY IN PROGRESS holding a seat
  /// open for the player who dropped out of it. Joining it resumes that
  /// match where it left off rather than starting a new one.
  final bool resumable;

  const RoomInfo({
    required this.code,
    required this.host,
    required this.playerName,
    this.resumable = false,
  });
}

/// A duplex channel carrying the game's JSON messages to the opponent.
///
/// The whole match protocol — the mode vote, the fleet exchange, firing,
/// MANOEUVRE moves, the mid-match resume snapshot, the rematch handshake
/// — is just objects going back and forth over one of these. Keeping that
/// behind an interface is what let internet play be added without
/// touching any of it: [SocketLink] carries it over a direct TCP socket
/// on a shared hotspot, [RelayLink] carries the identical messages over
/// HTTP through the online server, and nothing above this line can tell
/// which one it is talking to.
abstract class GameLink {
  Stream<Map<String, dynamic>> get messages;
  void send(Map<String, dynamic> msg);
  Future<void> close();
}

/// Line-based JSON protocol over a TCP socket — hotspot / same-network
/// play, where the two devices can reach each other directly.
class SocketLink implements GameLink {
  final Socket socket;
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;
  String _buffer = '';
  bool _closed = false;

  /// Fired exactly once when this connection goes away for ANY reason —
  /// the peer closing it, the app being killed, or the network dropping.
  /// This is what lets a match tell "my opponent walked off" apart from
  /// "my opponent is thinking", and so what the reconnect grace window
  /// hangs off (see [NetworkService._onPeerDisconnected]).
  final void Function()? onClosed;

  SocketLink(this.socket, {this.onClosed}) {
    _sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(_onData, onDone: close, onError: (_) => close());
  }

  void _onData(String chunk) {
    _buffer += chunk;
    int idx;
    while ((idx = _buffer.indexOf('\n')) >= 0) {
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      if (line.isEmpty) continue;
      try {
        _in.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
      } catch (_) {/* ignore malformed */}
    }
  }

  @override
  void send(Map<String, dynamic> msg) {
    try {
      socket.write('${jsonEncode(msg)}\n');
    } catch (_) {/* socket closed */}
  }

  @override
  Stream<Map<String, dynamic>> get messages => _in.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sub?.cancel();
      await socket.close();
    } catch (_) {}
    if (!_in.isClosed) await _in.close();
    onClosed?.call();
  }
}

/// Handles hotspot (LAN) and online (relay) multiplayer.
class NetworkService extends ChangeNotifier {
  NetMode mode = NetMode.none;
  bool get isHost => _isHost;
  bool _isHost = false;
  bool connected = false;
  bool isSearching = false;
  String statusMessage = '';
  String roomCode = '';
  String localIp = '';
  String peerName = 'Opponent';
  List<RoomInfo> foundRooms = [];

  /// The opponent's equipped loadout, exchanged in the handshake so each
  /// player's own purchased ship skin, cannon and battlefield theme render
  /// on BOTH devices. Ids only — the catalog is compiled into the app, so
  /// there is nothing else to send.
  String peerShipSkinId = 'steel';
  String peerCannonSkinId = 'mk1';
  String peerThemeId = 'classic';

  /// Whether the opponent actually picked their hull or is still on the
  /// starter one — the difference between showing their skin and showing
  /// their side's plain red/blue. Sent because the id alone can't say:
  /// Steel Fleet is both the default and a real, choosable skin. See
  /// `ProfileStore.shipSkinChosen`.
  bool peerShipSkinChosen = false;

  // ------------------------------------------- MATCH LIFECYCLE / DROPS ---

  /// How long a dropped player has to get back into the match before the
  /// seat is given up for good.
  static const int kReconnectGraceSeconds = 60;

  /// True once the fleets are exchanged and a battle is actually running.
  /// Until then a dropped connection is just a failed lobby attempt; after
  /// it, a drop opens the reconnect window below.
  bool inMatch = false;

  /// The peer's connection has gone away mid-match and we are holding the
  /// match open for them.
  bool peerLost = false;
  int graceSecondsLeft = 0;
  Timer? _graceTimer;

  /// The peer is not coming back: either the grace window expired, or they
  /// explicitly left from the result screen.
  bool peerGone = false;

  /// The peer tapped REMATCH / left after the match ended.
  bool myRematch = false;
  bool peerRematch = false;
  bool peerLeftMatch = false;
  bool get bothRematch => myRematch && peerRematch;

  /// A mid-match state snapshot sent by the surviving player, retained the
  /// moment it arrives for the same reason the fleet exchange is (see
  /// [_peerBoardMsg]) — the screen that consumes it is usually not built
  /// yet when it lands.
  Map<String, dynamic>? _resumeMsg;
  Map<String, dynamic>? takeResume() {
    final m = _resumeMsg;
    _resumeMsg = null;
    return m;
  }

  /// True when this device joined a room that was holding a seat open for
  /// it, so the lobby should wait for a resume snapshot instead of walking
  /// through mode-vote and placement again.
  bool joiningResumable = false;

  ServerSocket? _server;
  RawDatagramSocket? _udp;
  GameLink? _link;
  Timer? _beaconTimer;
  Timer? _scanTimer;
  Timer? _voteTimer;

  final _messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageCtrl.stream;

  static const _magic = 'BBLZ1';

  bool get _networkAvailable => !kIsWeb;

  Future<String> _localIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ---------------------------------------------------------------- HOST ---

  /// Hosts a hotspot match. Returns the room code or null on failure.
  Future<String?> hostHotspot({required String playerName}) async {
    if (!_networkAvailable) {
      statusMessage = 'Hotspot play needs an Android device.';
      notifyListeners();
      return null;
    }
    await stop();
    mode = NetMode.hotspot;
    _isHost = true;
    _selfName = playerName;
    try {
      await _ensureServer();
      localIp = await _localIp();
      roomCode = _newCode();
      await _startBeacon(resumable: false);

      statusMessage = 'Waiting for opponent…';
      notifyListeners();
      return roomCode;
    } catch (e) {
      statusMessage = 'Could not host: $e';
      notifyListeners();
      await stop();
      return null;
    }
  }

  /// Binds the TCP listener if it isn't already up, and wires it to
  /// [_acceptSocket]. Shared by the initial host and by whichever player
  /// is left holding a match open for a dropped opponent — the survivor
  /// takes over listening even if they were originally the joiner, which
  /// is what lets a dropped HOST scan and walk back into their own match.
  Future<void> _ensureServer() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, kGamePort);
    _server!.listen(_acceptSocket);
  }

  void _acceptSocket(Socket socket) {
    // One seat, first come first served.
    if (_link != null) {
      socket.destroy();
      return;
    }
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _link = SocketLink(socket, onClosed: _onPeerDisconnected);
    _stopBeacon();
    _link!.messages.listen(_handleIncoming);
    statusMessage = 'Opponent connecting…';
    notifyListeners();
  }

  /// Broadcasts this room on the LAN once a second so joiners can find it
  /// with SCAN FOR GAMES. [resumable] marks the beacon as a match already
  /// in progress with a seat held open.
  Future<void> _startBeacon({required bool resumable}) async {
    _stopBeacon();
    if (localIp.isEmpty) localIp = await _localIp();
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
    _udp!.broadcastEnabled = true;
    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final payload = jsonEncode({
        'magic': _magic,
        'code': roomCode,
        'host': localIp,
        'name': _selfName,
        if (resumable) 'resume': 1,
      });
      _udp?.send(
          utf8.encode(payload), InternetAddress('255.255.255.255'), 45679);
    });
  }

  void _stopBeacon() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
  }

  // ---------------------------------------------------------------- JOIN ---

  /// Scans for hotspot rooms on the local network for a few seconds.
  Future<void> scanRooms() async {
    if (!_networkAvailable) return;
    foundRooms = [];
    isSearching = true;
    notifyListeners();
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
      _scanTimer?.cancel();
      _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udp!.receive();
        if (dg == null) return;
        try {
          final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (msg['magic'] == _magic) {
            final room = RoomInfo(
              code: msg['code'] as String,
              host: msg['host'] as String,
              playerName: msg['name'] as String? ?? 'Captain',
              resumable: msg['resume'] == 1,
            );
            if (!foundRooms.any((r) => r.host == room.host)) {
              foundRooms = [...foundRooms, room];
              notifyListeners();
            }
          }
        } catch (_) {}
      });
      _scanTimer = Timer(const Duration(seconds: 6), () {
        isSearching = false;
        _udp?.close();
        _udp = null;
        notifyListeners();
      });
    } catch (_) {
      isSearching = false;
      notifyListeners();
    }
  }

  void stopScan() {
    _scanTimer?.cancel();
    isSearching = false;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    notifyListeners();
  }

  /// Joins a hotspot room by host IP. [resuming] should be true when the
  /// beacon advertised a match in progress (see [RoomInfo.resumable]) — the
  /// lobby then waits for a state snapshot instead of starting a new match.
  Future<bool> joinHotspot(String host,
      {required String playerName, bool resuming = false}) async {
    if (!_networkAvailable) return false;
    await stop();
    mode = NetMode.hotspot;
    _isHost = false;
    _selfName = playerName;
    joiningResumable = resuming;
    statusMessage = 'Connecting to $host…';
    notifyListeners();
    try {
      final socket = await Socket.connect(host, kGamePort,
          timeout: const Duration(seconds: 5));
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      _link = SocketLink(socket, onClosed: _onPeerDisconnected);
      _link!.messages.listen(_handleIncoming);
      _link!.send(_helloPayload(rejoin: resuming));
      return true;
    } catch (e) {
      statusMessage = 'Connection failed: ${_friendlyError(e)}';
      joiningResumable = false;
      notifyListeners();
      return false;
    }
  }

  /// This device's introduction: who we are and what we have equipped. The
  /// loadout rides along with the greeting so the opponent can render our
  /// ships, cannon and battlefield exactly as we chose them.
  Map<String, dynamic> _helloPayload({bool rejoin = false}) => {
        'type': 'hello',
        'name': _selfName,
        'ship': _selfShipSkinId,
        'shipPicked': _selfShipChosen ? 1 : 0,
        'cannon': _selfCannonSkinId,
        'theme': _selfThemeId,
        'room': roomCode,
        if (rejoin) 'rejoin': 1,
      };

  /// Convert a raw socket error into a friendly hint.
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('Permission denied') || s.contains('errno = 13')) {
      return 'Network permission denied. Reinstall the app or allow '
          'local-network access, then try again.';
    }
    if (s.contains('Connection refused') || s.contains('errno = 111')) {
      return 'No game at that address — is the host still hosting?';
    }
    if (s.contains('timed out') || s.contains('errno = 110')) {
      return 'Timed out — are both devices on the same Wi-Fi / hotspot?';
    }
    if (s.contains('unreachable') || s.contains('errno = 101') || s.contains('errno = 113')) {
      return 'Network unreachable — connect both devices to the same Wi-Fi / hotspot.';
    }
    return s;
  }

  // ---------------------------------------------------------- ONLINE ---

  /// Starts (or rejoins) an internet match that the online lobby has
  /// already set up — two friends have agreed to play and the server has
  /// given the match an id.
  ///
  /// From here on this is an ordinary match. The only difference from a
  /// hotspot game is the [GameLink] underneath: a [RelayLink] posting the
  /// same JSON through the server instead of a socket on the same Wi-Fi.
  /// Everything downstream — the mode vote, deployment, firing,
  /// manoeuvres, the reconnect window, rematch — is the identical code
  /// path, which is why online play arrived without the game rules
  /// gaining a single "if online" branch.
  ///
  /// [asHost] comes from who sent the invitation, which makes them the
  /// red fleet with the opening shot exactly as hosting a room does.
  Future<bool> startRelayMatch({
    required OnlineApi api,
    required int matchId,
    required bool asHost,
    required String playerName,
    bool rejoin = false,
  }) async {
    if (!_networkAvailable) {
      statusMessage = 'Online play needs a phone or desktop build.';
      notifyListeners();
      return false;
    }
    await stop();
    mode = NetMode.online;
    _isHost = asHost;
    _selfName = playerName;
    joiningResumable = rejoin;
    _link = RelayLink(
      api: api,
      matchId: matchId,
      onClosed: _onLinkClosed,
      onPeerPresence: _onRelayPeerPresence,
    );
    _link!.messages.listen(_handleIncoming);
    // Both ends greet unprompted. On a socket the joiner greets and the
    // accepting side answers, because only one of them knows the other is
    // there; over the relay both know from the moment the match exists.
    _link!.send(_helloPayload(rejoin: rejoin));
    statusMessage = 'Waiting for ${rejoin ? 'the match' : 'your opponent'}…';
    notifyListeners();
    return true;
  }

  /// The peer's fleet, retained from the moment it arrives.
  ///
  /// BUGFIX (hotspot: whoever pressed SAVE second hung on "WAITING FOR
  /// OPPONENT…" forever while the other player was already in battle).
  /// [messages] is a BROADCAST stream, so anything emitted while nobody is
  /// listening is dropped permanently — and the placement screen only
  /// subscribes once THAT device saves its own fleet (see
  /// `_waitForPeerBoard`). Two players essentially never hit SAVE at the
  /// same instant, so the player who saved first sent their board into a
  /// stream with no listener on the other end, and it was gone. The board
  /// is now held here until the placement screen actually collects it, so
  /// the exchange no longer depends on who saved first.
  Map<String, dynamic>? _peerBoardMsg;

  /// Returns the peer's stored board message (if it already arrived) and
  /// clears it, so a board can never leak into a subsequent match.
  Map<String, dynamic>? takePeerBoard() {
    final b = _peerBoardMsg;
    _peerBoardMsg = null;
    return b;
  }

  /// Feeds a message in as if it had arrived from the opponent.
  ///
  /// Exists so the rules applied to INCOMING data — which is the one
  /// thing here that comes from another device and so cannot be trusted —
  /// can be tested without standing up a socket.
  @visibleForTesting
  void handleIncomingForTest(Map<String, dynamic> msg) => _handleIncoming(msg);

  void _handleIncoming(Map<String, dynamic> msg) {
    if (msg['type'] == 'hello') {
      peerName = (msg['name'] as String?) ?? 'Opponent';
      peerShipSkinId = (msg['ship'] as String?) ?? 'steel';
      peerShipSkinChosen = msg['shipPicked'] == 1;
      peerCannonSkinId = (msg['cannon'] as String?) ?? 'mk1';
      peerThemeId = (msg['theme'] as String?) ?? 'classic';
      connected = true;
      statusMessage = 'Connected to $peerName!';
      // Whoever is currently listening answers the greeting. During a
      // reconnect that can be the original JOINER (the survivor takes over
      // the socket), so this deliberately keys off "did we accept this
      // connection", not off the fixed match role.
      // Both sides learn the room code, so whichever of them ends up
      // holding the match open for a dropped opponent re-advertises it
      // under the SAME code the other player already knows.
      final theirRoom = msg['room'] as String?;
      if (roomCode.isEmpty && theirRoom != null && theirRoom.isNotEmpty) {
        roomCode = theirRoom;
      }
      if (_server != null) _link?.send(_helloPayload());

      final rejoining = (msg['rejoin'] == 1 || peerLost) && !peerGone;
      if (rejoining && inMatch) {
        // They made it back inside the window. Close the grace period and
        // ask whoever owns the game state to hand over a snapshot — see
        // `GameController._onNetMessage`.
        _endGrace(gone: false);
        _messageCtrl.add(const {'type': 'resume_request'});
      }
      notifyListeners();
    }
    // Retain the fleet regardless of whether anyone is listening yet.
    if (msg['type'] == 'board') {
      _peerBoardMsg = msg;
    }
    if (msg['type'] == 'resume') {
      _resumeMsg = msg;
      inMatch = true;
      joiningResumable = false;
      notifyListeners();
    }
    if (msg['type'] == 'chat') {
      // Length is enforced again on arrival, not just at the sender: a
      // peer is not something to take on trust about how long a line is.
      final raw = (msg['m'] as String?)?.trim() ?? '';
      if (raw.isNotEmpty) {
        _appendChat(ChatLine(
          mine: false,
          text: raw.length > kChatMaxChars
              ? raw.substring(0, kChatMaxChars)
              : raw,
        ));
      }
    }
    if (msg['type'] == 'rematch') {
      peerRematch = true;
      notifyListeners();
    }
    if (msg['type'] == 'leave') {
      peerLeftMatch = true;
      peerGone = true;
      notifyListeners();
    }
    _handleVoteMessage(msg);
    _messageCtrl.add(msg);
  }

  // ------------------------------------------ DROP / RECONNECT WINDOW ---

  /// The socket went away. Outside a match that is just a failed lobby
  /// attempt; inside one it opens a [kReconnectGraceSeconds] window during
  /// which the match is held open and re-advertised on the LAN, so the
  /// player who dropped can find it again under SCAN FOR GAMES and walk
  /// back into exactly the position they left.
  void _onPeerDisconnected() => _onLinkClosed();

  /// The transport itself died — a socket closed, or the relay gave up on
  /// our own connection after repeated failures. Either way there is no
  /// channel left, so a returning opponent has to arrive over a NEW one.
  void _onLinkClosed() {
    _link = null;
    connected = false;
    // Only a hotspot match can hold its own door open: re-listening and
    // re-advertising over UDP means nothing on the internet, where the
    // server is the rendezvous point and the match id is already known
    // to both players.
    _openGraceWindow(reopenLan: mode == NetMode.hotspot);
  }

  /// Relay transport: the opponent has stopped talking to the server.
  ///
  /// Unlike a socket close this leaves OUR link intact and polling, which
  /// is what lets the same channel notice them coming back — their fresh
  /// `hello` arrives on the connection we already have, and the ordinary
  /// rejoin path in [_handleIncoming] takes it from there.
  void _onRelayPeerPresence(bool present) {
    if (present) {
      // Their return is confirmed by the `hello` they send on arriving,
      // not merely by them touching the server, so there is nothing to do
      // here — see the `rejoining` branch in [_handleIncoming].
      return;
    }
    connected = false;
    _openGraceWindow(reopenLan: false);
  }

  /// Opens the reconnect window, if a running match is what just lost its
  /// opponent. Idempotent: a relay match can report the peer missing on
  /// several consecutive polls, and that must not restart the clock.
  void _openGraceWindow({required bool reopenLan}) {
    if (!inMatch || peerGone || peerLost) {
      notifyListeners();
      return;
    }
    peerLost = true;
    graceSecondsLeft = kReconnectGraceSeconds;
    // Hold the seat open: re-listen and re-advertise. The survivor does
    // this whichever side they were, so a dropped host can rejoin too.
    if (reopenLan) unawaited(_reopenForReturn());
    _graceTimer?.cancel();
    _graceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      graceSecondsLeft--;
      if (graceSecondsLeft <= 0) {
        _endGrace(gone: true);
      }
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _reopenForReturn() async {
    try {
      if (roomCode.isEmpty) roomCode = _newCode();
      await _ensureServer();
      await _startBeacon(resumable: true);
    } catch (_) {
      // Port already in use by something else — the window simply can't
      // be held open. The grace timer still runs so the UI stays honest.
    }
  }

  void _endGrace({required bool gone}) {
    _graceTimer?.cancel();
    _graceTimer = null;
    graceSecondsLeft = 0;
    peerLost = false;
    // BUGFIX: this used to only ever SET `peerGone`, never clear it, so a
    // player who did come back left the survivor still staring at "they
    // did not return" over a match that had quietly resumed underneath.
    peerGone = gone;
    if (gone) {
      // The seat is given up. Stop advertising AND stop listening: with
      // the socket still open a late arrival could connect and be handed
      // a snapshot for a match the survivor has already been told is
      // over — which is exactly how the two ends ended up disagreeing.
      // Refusing the connection outright gives them the ordinary "no game
      // at that address" message instead.
      _stopBeacon();
      try {
        _server?.close();
      } catch (_) {}
      _server = null;
    }
    notifyListeners();
  }

  /// Marks the point where a real battle begins, after which a dropped
  /// connection is worth holding a seat open for.
  void beginMatch() {
    inMatch = true;
    peerGone = false;
    peerLeftMatch = false;
    notifyListeners();
  }

  /// Sends the full mid-match state to a player who just rejoined.
  void sendResume(Map<String, dynamic> snapshot) =>
      _link?.send({'type': 'resume', ...snapshot});

  // ------------------------------------------- LAN GAME-MODE VOTE ---

  /// How long both players get to change their minds once BOTH have
  /// picked a mode, before the vote locks in.
  static const int kVoteCountdownSeconds = 5;

  /// This device's pick, the peer's pick, and the final answer. Held as
  /// plain notifier fields (rather than pushed through [messages]) on
  /// purpose: [messages] is a BROADCAST stream and drops anything emitted
  /// while nobody is listening, which is exactly the bug that used to
  /// strand a player on "WAITING FOR OPPONENT…" during the fleet exchange
  /// (see [_peerBoardMsg]). Votes have the same shape of race — the peer
  /// can vote before this device's mode screen has even been built — so
  /// they're kept as state the screen can simply read on its first frame.
  LanBattleMode? myVote;
  LanBattleMode? peerVote;

  /// Seconds left before the vote locks, or null while it isn't running.
  /// Owned by the HOST and mirrored to the joiner over the wire, so both
  /// devices count down together instead of drifting apart on two
  /// independently-started timers.
  int? voteCountdown;

  /// The mode the match will actually be played in — set once, by the
  /// host, when the countdown expires.
  LanBattleMode? lockedMode;

  bool get bothVoted => myVote != null && peerVote != null;

  /// The match can only start once BOTH captains have picked the SAME
  /// mode. A split vote is not resolved in anybody's favour — it simply
  /// doesn't start, and the countdown will not run until the two picks
  /// agree.
  bool get votesAgree => bothVoted && myVote == peerVote;

  /// Casts (or changes) this device's vote. Safe to call repeatedly; a
  /// vote can be changed freely right up until [lockedMode] is set, which
  /// is what makes changing your pick mid-countdown work.
  void castVote(LanBattleMode mode) {
    if (lockedMode != null) return;
    if (myVote == mode) return;
    myVote = mode;
    _link?.send({'type': 'vote', 'm': mode.index});
    _maybeStartVoteCountdown();
    notifyListeners();
  }

  void _handleVoteMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'vote':
        final i = msg['m'] as int?;
        if (i == null || i < 0 || i >= LanBattleMode.values.length) return;
        peerVote = LanBattleMode.values[i];
        _maybeStartVoteCountdown();
        notifyListeners();
        break;

      case 'vote_tick':
        // Joiner side: the host owns the clock, we just display it.
        voteCountdown = msg['n'] as int?;
        notifyListeners();
        break;

      case 'mode_locked':
        final i = msg['m'] as int?;
        if (i == null || i < 0 || i >= LanBattleMode.values.length) return;
        _voteTimer?.cancel();
        _voteTimer = null;
        voteCountdown = 0;
        lockedMode = LanBattleMode.values[i];
        notifyListeners();
        break;
    }
  }

  /// Runs the lock-in countdown while — and only while — the two picks
  /// AGREE. Host only, since one device has to own the clock.
  ///
  /// A split vote never starts a match: the countdown does not begin, and
  /// if either player changes their pick mid-countdown so the two no
  /// longer match, the countdown is cancelled outright and picks up again
  /// from the top once they agree. That is what makes "both players must
  /// vote the same mode" true rather than advisory — there is no tie to
  /// break because a tie simply never resolves.
  void _maybeStartVoteCountdown() {
    if (!_isHost || lockedMode != null) return;

    if (!votesAgree) {
      // Disagreement (or somebody hasn't picked yet) — stand the clock
      // down and wait.
      if (_voteTimer != null || voteCountdown != null) {
        _voteTimer?.cancel();
        _voteTimer = null;
        voteCountdown = null;
        _link?.send({'type': 'vote_tick', 'n': null});
      }
      return;
    }

    if (_voteTimer != null) return; // already counting on an agreed pick

    voteCountdown = kVoteCountdownSeconds;
    _link?.send({'type': 'vote_tick', 'n': voteCountdown});
    notifyListeners();

    _voteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = (voteCountdown ?? 1) - 1;
      voteCountdown = next;
      if (next > 0) {
        _link?.send({'type': 'vote_tick', 'n': next});
        notifyListeners();
        return;
      }
      _voteTimer?.cancel();
      _voteTimer = null;
      // Both picks are identical by construction here, so there is
      // nothing to resolve — but the host still broadcasts the answer so
      // the two ends can never disagree about what was agreed.
      final winner = myVote ?? LanBattleMode.turns;
      lockedMode = winner;
      _link?.send({'type': 'mode_locked', 'm': winner.index});
      notifyListeners();
    });
  }

  /// Clears all vote state. Called when a match ends/disconnects and
  /// whenever the mode screen is entered fresh, so a previous match's
  /// picks can never leak into the next one.
  void resetLanVote() {
    _voteTimer?.cancel();
    _voteTimer = null;
    myVote = null;
    peerVote = null;
    voteCountdown = null;
    lockedMode = null;
    notifyListeners();
  }

  String _selfName = 'Captain';
  String _selfShipSkinId = 'steel';
  bool _selfShipChosen = false;
  String _selfCannonSkinId = 'mk1';
  String _selfThemeId = 'classic';

  void setSelfName(String name) => _selfName = name;

  /// Restores the fixed match role after a reconnect. Which side you are
  /// — red host or blue challenger, and therefore who shoots first — is
  /// decided once for the whole match, but a returning player always
  /// arrives through [joinHotspot] and so would otherwise come back as
  /// the joiner regardless of who they actually were. The survivor tells
  /// them in the resume snapshot; this applies it.
  void setMatchHost(bool value) {
    _isHost = value;
    notifyListeners();
  }

  /// Records what this player has equipped so it can be sent in the
  /// handshake. Called from the lobby before hosting or joining.
  void setSelfLoadout({
    required String shipSkinId,
    required String cannonSkinId,
    required String themeId,
    bool shipChosen = false,
  }) {
    _selfShipSkinId = shipSkinId;
    _selfShipChosen = shipChosen;
    _selfCannonSkinId = cannonSkinId;
    _selfThemeId = themeId;
  }

  /// Re-announces this device's gear to an already-connected opponent.
  ///
  /// The loadout normally rides along with the greeting, which is fine
  /// while it is fixed before the match. It stopped being fixed when the
  /// deployment screen grew a GEAR button: change your hull there and the
  /// opponent would still be drawing the fleet you arrived in. Reusing
  /// the `hello` shape rather than inventing a second message means the
  /// receiving side already knows how to apply it — this is the same
  /// announcement, made again.
  void announceLoadout({
    required String shipSkinId,
    required String cannonSkinId,
    required String themeId,
    bool shipChosen = false,
  }) {
    setSelfLoadout(
      shipSkinId: shipSkinId,
      cannonSkinId: cannonSkinId,
      themeId: themeId,
      shipChosen: shipChosen,
    );
    _link?.send(_helloPayload());
  }

  // -------------------------------------------------- MATCH CHAT ---

  /// Longest message accepted, in characters. Trimmed at the sender so a
  /// peer can never push an unbounded string into our list.
  static const int kChatMaxChars = 160;

  /// How many lines are kept. A match generates a handful; the cap is
  /// only here so a very long session can't grow this without limit.
  static const int kChatMaxLines = 120;

  /// The whole match's conversation, oldest first.
  ///
  /// ONE list for the entire match, deliberately: the vote screen, the
  /// deployment screen, the battle and the result screen are four routes,
  /// but they are one conversation. Anything scoped to a screen would
  /// throw away what was said the moment the match moved on — and a
  /// message sent while your opponent is still deploying would arrive to
  /// nobody.
  ///
  /// Held as a plain field rather than pushed through [messages] for the
  /// same reason the votes are: that stream is a broadcast, so a line
  /// sent while the other end is mid-route-change would be dropped
  /// permanently. A list the next screen can simply read on its first
  /// frame has no such window.
  final List<ChatLine> chat = [];

  /// Lines that have arrived since the player last had the chat open —
  /// what the badge on the closed chat button counts.
  int unreadChat = 0;

  void sendChat(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final capped = clean.length > kChatMaxChars
        ? clean.substring(0, kChatMaxChars)
        : clean;
    _appendChat(ChatLine(mine: true, text: capped));
    _link?.send({'type': 'chat', 'm': capped});
  }

  void markChatRead() {
    if (unreadChat == 0) return;
    unreadChat = 0;
    notifyListeners();
  }

  void _appendChat(ChatLine line) {
    chat.add(line);
    if (chat.length > kChatMaxLines) {
      chat.removeRange(0, chat.length - kChatMaxLines);
    }
    if (!line.mine) unreadChat++;
    notifyListeners();
  }

  void sendFire(int r, int c) => _link?.send({'type': 'fire', 'r': r, 'c': c});

  void sendBoard(Board board) => _link?.send({'type': 'board', 'b': board.toJson()});

  /// MANOEUVRE mode: tells the opponent one of our ships has moved, so
  /// their copy of our fleet stays in step with ours.
  void sendMove(ShipKind kind, int r, int c, bool horizontal) => _link?.send({
        'type': 'move',
        'k': kind.index,
        'r': r,
        'c': c,
        'h': horizontal,
      });

  /// Post-match rematch handshake — the match only restarts when BOTH
  /// sides have asked for it.
  void sendRematch() {
    myRematch = true;
    _link?.send({'type': 'rematch'});
    notifyListeners();
  }

  /// Leaving for the main menu after a match. Tells the opponent not to
  /// keep waiting on a rematch that is never coming.
  void sendLeaveMatch() {
    _link?.send({'type': 'leave'});
    peerGone = true;
    notifyListeners();
  }

  void resetRematch() {
    myRematch = false;
    peerRematch = false;
    peerLeftMatch = false;
    notifyListeners();
  }

  void sendResult(int r, int c, ShotResult result, {String? sunkShip}) {
    _link?.send({
      'type': 'result',
      'r': r,
      'c': c,
      'res': result.index,
      'sunk': sunkShip,
    });
  }

  void sendSurrender() => _link?.send({'type': 'surrender'});

  Future<void> stop() async {
    _scanTimer?.cancel();
    _voteTimer?.cancel();
    _graceTimer?.cancel();
    _scanTimer = null;
    _voteTimer = null;
    _graceTimer = null;
    myVote = null;
    peerVote = null;
    voteCountdown = null;
    lockedMode = null;
    // Tearing down deliberately: a socket closing here must NOT be
    // mistaken for the opponent walking out mid-match, so shut the match
    // window down first.
    inMatch = false;
    peerLost = false;
    peerGone = false;
    graceSecondsLeft = 0;
    myRematch = false;
    peerRematch = false;
    peerLeftMatch = false;
    joiningResumable = false;
    _resumeMsg = null;
    _stopBeacon();
    try {
      await _link?.close();
    } catch (_) {}
    _link = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    connected = false;
    isSearching = false;
    foundRooms = [];
    peerShipSkinId = 'steel';
    peerShipSkinChosen = false;
    peerCannonSkinId = 'mk1';
    peerThemeId = 'classic';
    _peerBoardMsg = null; // never carry a fleet into the next match
    chat.clear(); // nor a conversation with someone you are no longer playing
    unreadChat = 0;
    mode = NetMode.none;
    notifyListeners();
  }
}

/// One line of match chat.
class ChatLine {
  /// True when this device sent it. The peer's display name is read live
  /// from `NetworkService.peerName` rather than stamped on each line, so
  /// a name that arrives late (or changes on a reconnect) doesn't leave
  /// half the conversation labelled wrongly.
  final bool mine;
  final String text;
  final DateTime at;

  ChatLine({required this.mine, required this.text, DateTime? at})
      : at = at ?? DateTime.now();
}
