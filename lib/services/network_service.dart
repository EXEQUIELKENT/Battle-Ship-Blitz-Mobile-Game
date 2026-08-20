import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';

/// Network modes supported by the game.
enum NetMode { none, hotspot, online }

/// TCP port used for hotspot (LAN) matches.
const int kGamePort = 45678;

/// Public rendezvous relay. When reachable, "online" matches work
/// between any two devices connected to the internet; otherwise the
/// game gracefully falls back to LAN play.
const String kRelayHost = 'tcp.ngrok.io';
const int kRelayPort = 0; // 0 = relay unavailable (LAN fallback)

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

/// Low-level line-based JSON protocol over a socket.
class _Protocol {
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

  _Protocol(this.socket, {this.onClosed}) {
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

  void send(Map<String, dynamic> msg) {
    try {
      socket.write('${jsonEncode(msg)}\n');
    } catch (_) {/* socket closed */}
  }

  Stream<Map<String, dynamic>> get messages => _in.stream;

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
  _Protocol? _proto;
  Timer? _beaconTimer;
  Timer? _scanTimer;
  Timer? _voteTimer;

  final _messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageCtrl.stream;

  static const _magic = 'BBLZ1';

  bool get _networkAvailable => !kIsWeb;

  /// Whether true online (internet) play can be attempted right now.
  Future<bool> onlineAvailable() async {
    if (!_networkAvailable) return false;
    if (kRelayPort == 0) return false;
    try {
      final s = await Socket.connect(kRelayHost, kRelayPort,
          timeout: const Duration(seconds: 3));
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

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
    if (_proto != null) {
      socket.destroy();
      return;
    }
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _proto = _Protocol(socket, onClosed: _onPeerDisconnected);
    _stopBeacon();
    _proto!.messages.listen(_handleIncoming);
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
      _proto = _Protocol(socket, onClosed: _onPeerDisconnected);
      _proto!.messages.listen(_handleIncoming);
      _proto!.send(_helloPayload(rejoin: resuming));
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

  /// Joins an online match via the relay (falls back message when offline).
  Future<bool> joinOnline(String code, {required String playerName}) async {
    if (!_networkAvailable || kRelayPort == 0) {
      statusMessage =
          'Online relay unreachable — use Hotspot mode on the same network.';
      notifyListeners();
      return false;
    }
    await stop();
    mode = NetMode.online;
    _isHost = false;
    try {
      final socket = await Socket.connect(kRelayHost, kRelayPort,
          timeout: const Duration(seconds: 5));
      _proto = _Protocol(socket);
      _proto!.messages.listen(_handleIncoming);
      _proto!.send({'type': 'join_room', 'code': code, 'name': playerName});
      return true;
    } catch (e) {
      statusMessage = 'Online connection failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Hosts an online match via the relay.
  Future<String?> hostOnline({required String playerName}) async {
    if (!_networkAvailable || kRelayPort == 0) {
      statusMessage =
          'Online relay unreachable — use Hotspot mode on the same network.';
      notifyListeners();
      return null;
    }
    await stop();
    mode = NetMode.online;
    _isHost = true;
    try {
      final socket = await Socket.connect(kRelayHost, kRelayPort,
          timeout: const Duration(seconds: 5));
      _proto = _Protocol(socket);
      _proto!.messages.listen(_handleIncoming);
      roomCode = _newCode();
      _proto!.send({'type': 'host_room', 'code': roomCode, 'name': playerName});
      return roomCode;
    } catch (e) {
      statusMessage = 'Online connection failed: $e';
      notifyListeners();
      return null;
    }
  }

  // ------------------------------------------------------------- SHARED ---

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

  void _handleIncoming(Map<String, dynamic> msg) {
    if (msg['type'] == 'hello') {
      peerName = (msg['name'] as String?) ?? 'Opponent';
      peerShipSkinId = (msg['ship'] as String?) ?? 'steel';
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
      if (_server != null) _proto?.send(_helloPayload());

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
  void _onPeerDisconnected() {
    _proto = null;
    connected = false;
    if (!inMatch || peerGone) {
      notifyListeners();
      return;
    }
    peerLost = true;
    graceSecondsLeft = kReconnectGraceSeconds;
    // Hold the seat open: re-listen and re-advertise. The survivor does
    // this whichever side they were, so a dropped host can rejoin too.
    unawaited(_reopenForReturn());
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
      _proto?.send({'type': 'resume', ...snapshot});

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
    _proto?.send({'type': 'vote', 'm': mode.index});
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
        _proto?.send({'type': 'vote_tick', 'n': null});
      }
      return;
    }

    if (_voteTimer != null) return; // already counting on an agreed pick

    voteCountdown = kVoteCountdownSeconds;
    _proto?.send({'type': 'vote_tick', 'n': voteCountdown});
    notifyListeners();

    _voteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = (voteCountdown ?? 1) - 1;
      voteCountdown = next;
      if (next > 0) {
        _proto?.send({'type': 'vote_tick', 'n': next});
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
      _proto?.send({'type': 'mode_locked', 'm': winner.index});
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
  }) {
    _selfShipSkinId = shipSkinId;
    _selfCannonSkinId = cannonSkinId;
    _selfThemeId = themeId;
  }

  void sendFire(int r, int c) => _proto?.send({'type': 'fire', 'r': r, 'c': c});

  void sendBoard(Board board) => _proto?.send({'type': 'board', 'b': board.toJson()});

  /// MANOEUVRE mode: tells the opponent one of our ships has moved, so
  /// their copy of our fleet stays in step with ours.
  void sendMove(ShipKind kind, int r, int c, bool horizontal) => _proto?.send({
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
    _proto?.send({'type': 'rematch'});
    notifyListeners();
  }

  /// Leaving for the main menu after a match. Tells the opponent not to
  /// keep waiting on a rematch that is never coming.
  void sendLeaveMatch() {
    _proto?.send({'type': 'leave'});
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
    _proto?.send({
      'type': 'result',
      'r': r,
      'c': c,
      'res': result.index,
      'sunk': sunkShip,
    });
  }

  void sendSurrender() => _proto?.send({'type': 'surrender'});

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
      await _proto?.close();
    } catch (_) {}
    _proto = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    connected = false;
    isSearching = false;
    foundRooms = [];
    peerShipSkinId = 'steel';
    peerCannonSkinId = 'mk1';
    peerThemeId = 'classic';
    _peerBoardMsg = null; // never carry a fleet into the next match
    mode = NetMode.none;
    notifyListeners();
  }
}
