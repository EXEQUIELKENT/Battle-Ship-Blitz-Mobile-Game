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

  const RoomInfo({required this.code, required this.host, required this.playerName});
}

/// Low-level line-based JSON protocol over a socket.
class _Protocol {
  final Socket socket;
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;
  String _buffer = '';

  _Protocol(this.socket) {
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
    try {
      await _sub?.cancel();
      await socket.close();
    } catch (_) {}
    if (!_in.isClosed) await _in.close();
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
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, kGamePort);
      localIp = await _localIp();
      roomCode = _newCode();

      // UDP beacon so joiners can auto-discover us.
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
      _udp!.broadcastEnabled = true;
      _beaconTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final payload = jsonEncode({
          'magic': _magic,
          'code': roomCode,
          'host': localIp,
          'name': playerName,
        });
        _udp?.send(utf8.encode(payload), InternetAddress('255.255.255.255'), 45679);
      });

      statusMessage = 'Waiting for opponent…';
      notifyListeners();

      _server!.listen((socket) async {
        // First client wins the seat.
        if (_proto != null) {
          socket.destroy();
          return;
        }
        try {
          socket.setOption(SocketOption.tcpNoDelay, true);
        } catch (_) {}
        _proto = _Protocol(socket);
        _beaconTimer?.cancel();
        _proto!.messages.listen(_handleIncoming);
        // Wait for hello
        statusMessage = 'Opponent connecting…';
        notifyListeners();
      });
      return roomCode;
    } catch (e) {
      statusMessage = 'Could not host: $e';
      notifyListeners();
      await stop();
      return null;
    }
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

  /// Joins a hotspot room by host IP.
  Future<bool> joinHotspot(String host, {required String playerName}) async {
    if (!_networkAvailable) return false;
    await stop();
    mode = NetMode.hotspot;
    _isHost = false;
    statusMessage = 'Connecting to $host…';
    notifyListeners();
    try {
      final socket = await Socket.connect(host, kGamePort,
          timeout: const Duration(seconds: 5));
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      _proto = _Protocol(socket);
      _proto!.messages.listen(_handleIncoming);
      _proto!.send({'type': 'hello', 'name': playerName});
      return true;
    } catch (e) {
      statusMessage = 'Connection failed: ${_friendlyError(e)}';
      notifyListeners();
      return false;
    }
  }

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
      connected = true;
      statusMessage = 'Connected to $peerName!';
      if (_isHost) {
        _proto?.send({'type': 'hello', 'name': _selfName});
      }
      notifyListeners();
    }
    // Retain the fleet regardless of whether anyone is listening yet.
    if (msg['type'] == 'board') {
      _peerBoardMsg = msg;
    }
    _handleVoteMessage(msg);
    _messageCtrl.add(msg);
  }

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

  /// Starts the lock-in countdown once both players have picked — host
  /// only, and only once per vote (a later vote CHANGE deliberately does
  /// not restart it, so the countdown can't be held open indefinitely by
  /// one player flip-flopping).
  void _maybeStartVoteCountdown() {
    if (!_isHost || lockedMode != null || _voteTimer != null) return;
    if (myVote == null || peerVote == null) return;

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
      final winner = _votedMode;
      lockedMode = winner;
      _proto?.send({'type': 'mode_locked', 'm': winner.index});
      notifyListeners();
    });
  }

  /// Resolves the vote to the mode with the most picks.
  ///
  /// With exactly two voters the tally is only ever 2–0 (that mode wins
  /// outright) or 1–1 (a tie, broken in the host's favor) — and both of
  /// those come out as the host's own pick. Only the host ever calls this,
  /// and it broadcasts the answer rather than letting each device decide
  /// for itself: resolving on one device is what guarantees the two ends
  /// can never end up in different game modes.
  LanBattleMode get _votedMode => myVote ?? LanBattleMode.turns;

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
  void setSelfName(String name) => _selfName = name;

  void sendFire(int r, int c) => _proto?.send({'type': 'fire', 'r': r, 'c': c});

  void sendBoard(Board board) => _proto?.send({'type': 'board', 'b': board.toJson()});

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
    _beaconTimer?.cancel();
    _scanTimer?.cancel();
    _voteTimer?.cancel();
    _beaconTimer = null;
    _scanTimer = null;
    _voteTimer = null;
    myVote = null;
    peerVote = null;
    voteCountdown = null;
    lockedMode = null;
    try {
      await _proto?.close();
    } catch (_) {}
    _proto = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    connected = false;
    isSearching = false;
    foundRooms = [];
    _peerBoardMsg = null; // never carry a fleet into the next match
    mode = NetMode.none;
    notifyListeners();
  }
}
