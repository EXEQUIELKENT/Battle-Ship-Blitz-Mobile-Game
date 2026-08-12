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
    _messageCtrl.add(msg);
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
    _beaconTimer = null;
    _scanTimer = null;
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
    mode = NetMode.none;
    notifyListeners();
  }
}
