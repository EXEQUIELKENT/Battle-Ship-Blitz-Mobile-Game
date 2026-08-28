import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_models.dart';
import '../models/power_up.dart';
import 'loopback_link.dart';
import 'multicast_lock.dart';
import 'online_api.dart';
import 'relay_link.dart';

/// Network modes supported by the game.
///
/// `loopback` carries a vsAiLan match over a `LoopbackLink` instead of a
/// socket or the relay — no port is bound, no UDP beacon goes out, and
/// nothing here switches on it exhaustively, so it silently behaves like
/// "no real transport" everywhere that isn't specifically about the
/// match protocol (see `GameController.usesMatchProtocol` /
/// `hasRemotePeer`). In particular `_onLinkClosed`'s
/// `reopenLan: mode == NetMode.hotspot` is already false for it — an
/// offline vs-AI game has no LAN seat to hold open.
enum NetMode { none, hotspot, online, loopback }

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

  /// The relay match id and poll cursor, when running over a
  /// [RelayLink] — null for hotspot/loopback, which have neither. See
  /// `MatchStore`, the one thing that reads these: it persists both so a
  /// rejoining `RelayLink` can be built with [startRelayMatch]'s `since`
  /// pointed at wherever this device last actually got to, rather than
  /// replaying the match's entire message history from the start.
  int? get relayMatchId => _link is RelayLink ? (_link as RelayLink).matchId : null;
  int? get relaySince => _link is RelayLink ? (_link as RelayLink).since : null;

  /// Every address this device answers to across all its active network
  /// interfaces — not just the one [localIp] happens to be. See
  /// [_localIps]/[_startBeacon] for why the beacon needs all of them, not
  /// a single guess.
  List<String> localIps = const [];
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
  /// ON-SCREEN countdown ends. Not the actual deadline — see
  /// [kSilentSeatHoldSeconds].
  static const int kReconnectGraceSeconds = 60;

  /// How much LONGER, past [kReconnectGraceSeconds], the seat stays held
  /// open silently — beacon and socket both still live, just no visible
  /// countdown — before [_endGrace] finally gives it up for real. Long
  /// enough to outlast a phone locking or a genuine app restart on the
  /// dropped player's end, which the 60s on-screen number was never
  /// meant to represent a hard cutoff for.
  static const int kSilentSeatHoldSeconds = 600;

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
  // A socket of its own, separate from [_udp] — the beacon and the scanner
  // used to share one field, so `scanRooms` (called by a device that is
  // ALSO hosting, e.g. to walk back into its own room) would silently kill
  // its own beacon out from under it: `scanRooms` overwrote `_udp` without
  // stopping the beacon timer, and the scan's own 6s cleanup then closed
  // and nulled it, so `_beaconTimer` kept firing sends on a closed socket
  // forever after.
  RawDatagramSocket? _scanUdp;
  GameLink? _link;
  Timer? _beaconTimer;
  Timer? _scanTimer;
  Timer? _voteTimer;

  /// Every message this device has ever sent, in order — nothing reads
  /// this at runtime. It exists purely so a unit test can assert on the
  /// OUTGOING half of a protocol exchange (e.g. what a `pw_ask` handler
  /// actually computed and sent back) without standing up a real
  /// [GameLink] on both ends, the way [handleIncomingForTest] already
  /// lets a test drive the incoming half.
  @visibleForTesting
  final List<Map<String, dynamic>> sentForTest = [];

  /// Every outgoing message funnels through here rather than calling
  /// `_link?.send` directly, so [sentForTest] can see all of them — see
  /// its doc for why.
  void _send(Map<String, dynamic> msg) {
    sentForTest.add(msg);
    _link?.send(msg);
  }

  final _messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageCtrl.stream;

  static const _magic = 'BBLZ1';

  bool get _networkAvailable => !kIsWeb;

  /// Every non-loopback IPv4 address this device currently has, one per
  /// active network interface.
  ///
  /// A phone that is hosting its own Wi-Fi hotspot while ALSO still
  /// signed on to mobile data has (at least) two of these at once — the
  /// hotspot's own address (something like `192.168.43.1`) and the
  /// cellular interface's — and `NetworkInterface.list` gives no
  /// guarantee about which comes back first. [_startBeacon] broadcasts
  /// on every one of them for exactly that reason: picking just one and
  /// hoping is how a room can end up advertised on an interface the
  /// joining phone has no route to at all, which shows up to a player as
  /// "my hotspot match doesn't show up in the scan" even though both
  /// phones are on the same hotspot.
  Future<List<String>> _localIps() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final out = <String>[];
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || out.contains(addr.address)) continue;
          out.add(addr.address);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<String> _localIp() async {
    final all = await _localIps();
    return all.isNotEmpty ? all.first : '127.0.0.1';
  }

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ---------------------------------------------------------------- HOST ---

  /// Hosts a hotspot match. Returns the room code or null on failure.
  ///
  /// [resumeRoomCode] reopens a match `MatchStore` persisted across a
  /// full app close, under the SAME code it was originally hosted under
  /// — without it, the code the joiner remembers (or the beacon
  /// advertised before) would no longer resolve to anything. Marks the
  /// beacon `resumable`, the same as [_reopenForReturn] does for a
  /// same-session drop, so a scanning joiner can tell this room apart
  /// from a fresh one.
  Future<String?> hostHotspot({
    required String playerName,
    String? resumeRoomCode,
  }) async {
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
      localIps = await _localIps();
      localIp = localIps.isNotEmpty ? localIps.first : await _localIp();
      final resuming = resumeRoomCode != null && resumeRoomCode.isNotEmpty;
      roomCode = resuming ? resumeRoomCode : _newCode();
      await _startBeacon(resumable: resuming);

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
  ///
  /// Sent once per address in [localIps], each aimed at THAT address's own
  /// subnet-directed broadcast (e.g. `192.168.43.255` for a host at
  /// `192.168.43.1`) rather than the single global `255.255.255.255`.
  /// That distinction matters specifically on a phone hosting a hotspot:
  /// the global broadcast address has no subnet of its own, so the OS
  /// resolves it through the ordinary routing table — commonly the same
  /// interface used for the phone's own default/mobile-data route, NOT
  /// the hotspot's AP interface, since the AP interface serves clients
  /// rather than being where this device goes to reach the internet. A
  /// directed broadcast, by contrast, targets an address that is only
  /// reachable via the one interface actually attached to that subnet, so
  /// the kernel's more-specific connected route wins and the packet goes
  /// out the right radio regardless of what the default route is. The
  /// plain global broadcast is still sent too, as a harmless extra that
  /// costs nothing and still helps on networks where it works fine.
  Future<void> _startBeacon({required bool resumable}) async {
    _stopBeacon();
    if (localIps.isEmpty) localIps = await _localIps();
    if (localIp.isEmpty && localIps.isNotEmpty) localIp = localIps.first;
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
    _udp!.broadcastEnabled = true;
    await MulticastLock.acquire();
    // Send one immediately rather than waiting out `Timer.periodic`'s
    // first tick — a joiner whose 6s scan window started just before this
    // beacon began would otherwise wait a full extra second (or, worse,
    // spend the last second of a short scan with nothing sent at all).
    _sendBeaconOnce(resumable);
    _beaconTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _sendBeaconOnce(resumable));
  }

  void _sendBeaconOnce(bool resumable) {
    // A phone hosting a hotspot while ALSO on mobile data has (at least)
    // two interfaces; one of them commonly has no route for its own
    // subnet-directed broadcast (`ENETUNREACH`) at any given moment. That
    // used to throw out of the whole `for` loop — including the interfaces
    // AFTER the bad one, and the global-broadcast send below — so one
    // flaky interface could silently blank the beacon out entirely for a
    // whole second. Each send is now independent.
    for (final ip in localIps) {
      final directed = _subnetBroadcastOf(ip);
      if (directed == null) continue;
      final bytes = utf8.encode(jsonEncode({
        'magic': _magic,
        'code': roomCode,
        'host': ip,
        'name': _selfName,
        if (resumable) 'resume': 1,
      }));
      try {
        _udp?.send(bytes, InternetAddress(directed), 45679);
      } catch (_) {}
    }
    if (localIps.isNotEmpty) {
      final bytes = utf8.encode(jsonEncode({
        'magic': _magic,
        'code': roomCode,
        'host': localIps.first,
        'name': _selfName,
        if (resumable) 'resume': 1,
      }));
      try {
        _udp?.send(bytes, InternetAddress('255.255.255.255'), 45679);
      } catch (_) {}
    }
  }

  /// The subnet-directed broadcast address for [ip], assuming a /24 —
  /// the same assumption `ServerDiscovery`'s own LAN sweep already makes
  /// elsewhere in this project, and true of every common phone hotspot
  /// and home router. Null for anything not shaped like a plain IPv4
  /// dotted quad.
  ///
  /// KNOWN LIMITATION: a /16 or /22 network (uncommon for a phone hotspot,
  /// possible on a home/office router) computes the wrong directed
  /// broadcast address here and gets no beacon delivery through it — only
  /// the plain `255.255.255.255` send in [_sendBeaconOnce] still reaches
  /// it, and plenty of routers/APs drop that. Not fixed: doing this
  /// properly needs the actual subnet mask, which Dart's `dart:io` has no
  /// portable way to read.
  String? _subnetBroadcastOf(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }

  void _stopBeacon() {
    final wasActive = _udp != null;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    try {
      _udp?.close();
    } catch (_) {}
    _udp = null;
    if (wasActive) unawaited(MulticastLock.release());
  }

  // ---------------------------------------------------------------- JOIN ---

  /// Scans for hotspot rooms on the local network for a few seconds.
  Future<void> scanRooms() async {
    if (!_networkAvailable) return;
    foundRooms = [];
    isSearching = true;
    notifyListeners();
    if (localIps.isEmpty) localIps = await _localIps();
    try {
      // A socket of its own — see the doc on [_scanUdp] for why sharing
      // [_udp] with the beacon was the actual root cause of "the room I'm
      // hosting stops showing up in MY OWN scan of it".
      _scanUdp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
      // Matches [_udp] above. Not needed to RECEIVE the beacon's directed
      // sends, but some Android builds have been seen to silently drop
      // inbound broadcast on a socket that never opted into it — cheap to
      // set regardless of platform.
      _scanUdp!.broadcastEnabled = true;
      await MulticastLock.acquire();
      _scanTimer?.cancel();
      _scanUdp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _scanUdp!.receive();
        if (dg == null) return;
        try {
          final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (msg['magic'] == _magic) {
            _ingestRoom(RoomInfo(
              code: msg['code'] as String,
              host: msg['host'] as String,
              playerName: msg['name'] as String? ?? 'Captain',
              resumable: msg['resume'] == 1,
            ));
          }
        } catch (_) {}
      });
      _scanTimer = Timer(const Duration(seconds: 6), stopScan);
    } catch (_) {
      isSearching = false;
      notifyListeners();
    }
  }

  /// Folds one freshly-parsed beacon into [foundRooms].
  ///
  /// Keyed on CODE, not host: a host with two live interfaces (hotspot +
  /// mobile data, say) beacons the same room under the same code from
  /// each address — see `_startBeacon` — and deduping on host let both
  /// through as if they were two different rooms, which showed up in the
  /// SCAN FOR GAMES list as the same room listed twice. One entry per
  /// code, upgraded to a newly-seen address only when that address is
  /// reachable from OUR subnet and the one already held is not.
  ///
  /// Split out of [scanRooms]'s socket listener (rather than a closure
  /// entirely inside `RawDatagramSocket.listen`) so this decision can be
  /// exercised by a test directly, the same way [handleIncomingForTest]
  /// lets a test drive the incoming-message half of the protocol without
  /// standing up a real socket.
  @visibleForTesting
  void ingestRoomForTest(RoomInfo room) => _ingestRoom(room);

  void _ingestRoom(RoomInfo room) {
    final idx = foundRooms
        .indexWhere((r) => r.code.toUpperCase() == room.code.toUpperCase());
    if (idx == -1) {
      foundRooms = [...foundRooms, room];
      notifyListeners();
    } else if (foundRooms[idx].host != room.host &&
        _onOwnSubnet(room.host) &&
        !_onOwnSubnet(foundRooms[idx].host)) {
      final updated = [...foundRooms];
      updated[idx] = room;
      foundRooms = updated;
      notifyListeners();
    }
  }

  /// Whether [host] sits on the same /24 as one of this device's own
  /// addresses — see the KNOWN LIMITATION note on [_subnetBroadcastOf].
  bool _onOwnSubnet(String host) {
    final subnet = _subnetBroadcastOf(host);
    if (subnet == null) return false;
    return localIps.map(_subnetBroadcastOf).contains(subnet);
  }

  void stopScan() {
    final wasActive = _scanUdp != null;
    _scanTimer?.cancel();
    _scanTimer = null;
    isSearching = false;
    try {
      _scanUdp?.close();
    } catch (_) {}
    _scanUdp = null;
    if (wasActive) unawaited(MulticastLock.release());
    notifyListeners();
  }

  /// Resolves a room CODE (as typed by a joiner) to the room it names, out
  /// of whatever `scanRooms` has found so far. Case-insensitive, since the
  /// code is meant to be read off another screen and retyped by hand.
  ///
  /// A host with more than one active network interface (hotspot + mobile
  /// data, say) beacons the SAME code from each of its addresses — see
  /// `_startBeacon` — so more than one [RoomInfo] can legitimately share a
  /// code. When that happens, prefer whichever one is actually reachable:
  /// the host address on the same /24 as one of THIS device's own
  /// addresses. Falls back to the first match if none line up (still
  /// usually right, and better than refusing to join at all).
  RoomInfo? roomByCode(String code, {List<String> myIps = const []}) {
    final wanted = code.trim().toUpperCase();
    if (wanted.isEmpty) return null;
    final matches =
        foundRooms.where((r) => r.code.toUpperCase() == wanted).toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;
    final mySubnets = myIps.map(_subnetBroadcastOf).whereType<String>().toSet();
    for (final room in matches) {
      if (mySubnets.contains(_subnetBroadcastOf(room.host))) return room;
    }
    return matches.first;
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
      _send(_helloPayload(rejoin: resuming));
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
    // Resumes polling from a previously persisted cursor — see
    // `RelayLink.since`'s doc — instead of always starting over at 0.
    int since = 0,
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
      since: since,
    );
    _link!.messages.listen(_handleIncoming);
    // Both ends greet unprompted. On a socket the joiner greets and the
    // accepting side answers, because only one of them knows the other is
    // there; over the relay both know from the moment the match exists.
    _send(_helloPayload(rejoin: rejoin));
    statusMessage = 'Waiting for ${rejoin ? 'the match' : 'your opponent'}…';
    notifyListeners();
    return true;
  }

  /// Joins this device's end of a vsAiLan match to [link] — one half of a
  /// `LoopbackLink.pair()`, the other half handed to the AI's own hidden
  /// `NetworkService`. No socket, no relay call, no beacon: everything
  /// downstream (mode rules, firing, power-ups) runs off the same
  /// `_handleIncoming` every other transport already uses, so it needs
  /// no code of its own to understand this one.
  ///
  /// [asHost] decides who fires first in a turn-based mode, exactly as it
  /// does for a real hotspot/online match — the caller sets up the
  /// player's own `NetworkService` with `asHost: true` and the AI's with
  /// `asHost: false` (or vice versa), same as any other match.
  Future<void> startLoopbackMatch({
    required LoopbackLink link,
    required bool asHost,
    required String playerName,
  }) async {
    await stop();
    mode = NetMode.loopback;
    _isHost = asHost;
    _selfName = playerName;
    _link = link;
    _link!.messages.listen(_handleIncoming);
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
      if (_server != null) _send(_helloPayload());

      // BUGFIX (a late reconnect could permanently lock itself out):
      // this used to gate on `!peerGone`, but `peerGone` means two
      // different things — "the 60s grace window ran out" (should still
      // be revocable; that's the whole point of `_endGrace(gone: false)`
      // right below, clearing it the instant a returner is recognized)
      // and "they explicitly left" (`peerLeftMatch`, set by an incoming
      // `'leave'` — genuinely final). Gating on the FIRST one was
      // circular: once the timer expired and set `peerGone`, THIS check
      // is what was supposed to clear it again on a real rejoin — but a
      // rejoin arriving even one tick after the timer could never get
      // past the very flag it exists to clear. `peerLeftMatch` only ever
      // means the second, unambiguous case, so it's the only one worth
      // gating on here.
      final rejoining = (msg['rejoin'] == 1 || peerLost) && !peerLeftMatch;
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
    // The opponent went back to editing after sending — drop whatever we
    // were holding so a stale fleet can never be picked up by
    // `takePeerBoard`. The placement screen's own listener (forwarded via
    // `_messageCtrl` below) reacts to the live message to un-stick the
    // waiting dialog; this clears the retained copy for anyone who asks later.
    if (msg['type'] == 'board_cancel') {
      _peerBoardMsg = null;
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
  ///
  /// Two phases, both covered by [graceSecondsLeft] alone (positive = the
  /// visible countdown; zero or negative = the silent hold below it —
  /// see [kSilentSeatHoldSeconds]), so nothing extra has to stay in sync
  /// with it. A phone screen-locking, or the app being killed and
  /// relaunched, both easily outlast [kReconnectGraceSeconds] without the
  /// player having actually given up — the visible countdown is there so
  /// the survivor isn't left staring at nothing, not because 60s is
  /// really the deadline. Only the much longer silent hold is.
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
    _graceTimer = Timer.periodic(graceTickIntervalForTest, (_) {
      graceSecondsLeft--;
      if (graceSecondsLeft <= -kSilentSeatHoldSeconds) {
        _endGrace(gone: true);
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Puts up the SAME "waiting for them to reconnect" state
  /// [_ReconnectOverlay] shows after a live drop — but for a match just
  /// restored from `MatchStore` after a full app close, where nothing
  /// "just disconnected" on THIS device to trigger it automatically.
  /// Functionally it's the identical situation (this side is back;
  /// whether the peer is remains unknown), so it gets the identical UI:
  /// the countdown, then the silent hold, then genuinely giving up.
  /// Whoever calls this owns re-listening/re-advertising themselves (a
  /// resuming HOST already reopened its own server/beacon under the
  /// saved room code before this runs) — never [reopenLan], which would
  /// only redo that.
  void beginHoldingSeatForReturn() {
    inMatch = true;
    peerGone = false;
    peerLeftMatch = false;
    _openGraceWindow(reopenLan: false);
  }

  /// Real ticks are once a real second — [kSilentSeatHoldSeconds] alone
  /// means a real test would have to wait over ten actual minutes to
  /// exercise the far end of the silent hold. Overridable ONLY for
  /// tests, the same way `ProfileStore.debugUnlockAllOverride` lets a
  /// test bypass a different real-world constant.
  @visibleForTesting
  static Duration graceTickIntervalForTest = const Duration(seconds: 1);

  /// Lets a test simulate "the peer's connection just dropped mid-match"
  /// without standing up a real socket — the same level
  /// [handleIncomingForTest] and [ingestRoomForTest] already operate at.
  @visibleForTesting
  void openGraceWindowForTest({bool reopenLan = false}) =>
      _openGraceWindow(reopenLan: reopenLan);

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
      _send({'type': 'resume', ...snapshot});

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
    _send({'type': 'vote', 'm': mode.index});
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
        _send({'type': 'vote_tick', 'n': null});
      }
      return;
    }

    if (_voteTimer != null) return; // already counting on an agreed pick

    voteCountdown = kVoteCountdownSeconds;
    _send({'type': 'vote_tick', 'n': voteCountdown});
    notifyListeners();

    _voteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = (voteCountdown ?? 1) - 1;
      voteCountdown = next;
      if (next > 0) {
        _send({'type': 'vote_tick', 'n': next});
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
      _send({'type': 'mode_locked', 'm': winner.index});
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
    _send(_helloPayload());
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
    _send({'type': 'chat', 'm': capped});
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

  /// [seq] is only meaningful in GHOST FLEET, where firing an
  /// already-fired cell is allowed on purpose — see the doc on
  /// `GameController._lastPeerFireSeq` for why that mode needs its own
  /// per-shot identifier to still catch a genuine network-level replay
  /// of this exact message.
  ///
  /// [hold] is POWER PLAY only: this shot is one of several in a single
  /// power-up action (or a DOUBLE TAP / COUNTER BATTERY bonus), and must
  /// never itself hand the turn over — see `GameController`'s power-up
  /// block and `BattleScreen._maybePassTurn`. Echoed back unchanged on
  /// the matching `result` so both ends agree.
  void sendFire(int r, int c, {int? seq, bool hold = false}) => _send({
        'type': 'fire',
        'r': r,
        'c': c,
        if (seq != null) 'seq': seq,
        if (hold) 'hold': true,
      });

  void sendBoard(Board board) => _send({'type': 'board', 'b': board.toJson()});

  /// Retracts a fleet sent by [sendBoard] — the CANCEL button on the
  /// "waiting for opponent" dialog. If the peer already collected the
  /// board via [takePeerBoard] and moved on to battle, this arrives too
  /// late to matter; it only helps while they are still waiting.
  void sendBoardCancel() => _send({'type': 'board_cancel'});

  /// MANOEUVRE mode: tells the opponent one of our ships has moved, so
  /// their copy of our fleet stays in step with ours.
  void sendMove(ShipKind kind, int r, int c, bool horizontal) => _send({
        'type': 'move',
        'k': kind.index,
        'r': r,
        'c': c,
        'h': horizontal,
      });

  /// GHOST FLEET: tells the opponent one of our destroyed hulls has sunk
  /// and faded away, so the watermark it used is free again on both sides
  /// (their shots there are now clean misses, our survivors may move back
  /// onto it). See `GameController.clearSunkShip`.
  void sendShipCleared(ShipKind kind) => _send({
        'type': 'ship_cleared',
        'k': kind.index,
      });

  /// Post-match rematch handshake — the match only restarts when BOTH
  /// sides have asked for it.
  void sendRematch() {
    myRematch = true;
    _send({'type': 'rematch'});
    notifyListeners();
  }

  /// Leaving for the main menu after a match. Tells the opponent not to
  /// keep waiting on a rematch that is never coming.
  void sendLeaveMatch() {
    _send({'type': 'leave'});
    peerGone = true;
    notifyListeners();
  }

  void resetRematch() {
    myRematch = false;
    peerRematch = false;
    peerLeftMatch = false;
    notifyListeners();
  }

  /// [hold] echoes the incoming `fire`'s own hold flag back so the shooter
  /// learns their own request. [forcePass] is POWER PLAY's MINEFIELD /
  /// TRAP LINE: this shot hands the turn to the shooter's OPPONENT (i.e.
  /// the defender who just answered it) regardless of hit or miss. [hotR]
  /// / [hotC] are HOT SHOT's bonus cell — a second, non-turn-affecting
  /// hit this same result also carries.
  void sendResult(
    int r,
    int c,
    ShotResult result, {
    String? sunkShip,
    bool hold = false,
    bool forcePass = false,
    int? hotR,
    int? hotC,
  }) {
    _send({
      'type': 'result',
      'r': r,
      'c': c,
      'res': result.index,
      'sunk': sunkShip,
      if (hold) 'hold': true,
      if (forcePass) 'fp': true,
      if (hotR != null) 'hotR': hotR,
      if (hotC != null) 'hotC': hotC,
    });
  }

  /// POWER PLAY — SONAR / SPOTTER / RECON SWEEP: a request the PEER's
  /// device evaluates against their own board, because only they have it.
  /// [r] / [c] carry the target cell (SONAR's 3×3 anchor, RECON SWEEP's
  /// row); SPOTTER needs neither, since it picks its own reveal.
  void sendPowerUpAsk(PowerUpCard card, {int? r, int? c}) => _send({
        'type': 'pw_ask',
        'card': card.index,
        if (r != null) 'r': r,
        if (c != null) 'c': c,
      });

  /// The answer to a [sendPowerUpAsk] — shape depends on the card: SONAR
  /// sends [n] (a ship count), SPOTTER sends [r]/[c] (the cell it found),
  /// RECON SWEEP sends [r] back with [has].
  void sendPowerUpAnswer(PowerUpCard card, {int? n, int? r, int? c, bool? has}) =>
      _send({
        'type': 'pw_answer',
        'card': card.index,
        if (n != null) 'n': n,
        if (r != null) 'r': r,
        if (c != null) 'c': c,
        if (has != null) 'has': has,
      });

  /// POWER PLAY — JAM / HOT SHOT: a condition armed on the PEER's device,
  /// consulted the next time it matters on their end (their next draw for
  /// JAM, their next resolved incoming hit for HOT SHOT).
  void sendPowerUpFlag(PowerUpCard card) =>
      _send({'type': 'pw_flag', 'card': card.index});

  /// POWER PLAY — announces that a card was used, purely for the
  /// opponent's "X used CARDNAME" banner. Never the mechanism a card's
  /// actual effect relies on.
  void sendPowerUpUsed(PowerUpCard card) =>
      _send({'type': 'pw_used', 'card': card.index});

  /// POWER PLAY — REPAIR/PATCH CREW: tells the peer which of THEIR
  /// confirmed hits on us were just undone, so their own `myShots` can
  /// stop treating that cell as resolved — see the doc on
  /// `GameController._healOne` for why skipping this permanently strands
  /// a hull. Reveals nothing new: the peer already knows a hull sits at
  /// each of these cells, since they are the one who hit it.
  void sendPowerUpHeal(List<(int, int)> cells) => _send({
        'type': 'pw_heal',
        'cells': [
          for (final (r, c) in cells) [r, c],
        ],
      });

  void sendSurrender() => _send({'type': 'surrender'});

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
    final scanWasActive = _scanUdp != null;
    try {
      _scanUdp?.close();
    } catch (_) {}
    _scanUdp = null;
    if (scanWasActive) unawaited(MulticastLock.release());
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
