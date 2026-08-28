import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_controller.dart';
import 'network_service.dart';

/// Persists enough of an in-progress hotspot/online match to disk that it
/// can be picked back up after the app was fully closed — not just a
/// dropped connection (see `NetworkService`'s own reconnect grace window
/// for that), but the process actually ending, with nothing left in
/// memory at all.
///
/// One JSON blob under one key, modelled on `ProfileStore`. Holds:
///  * which transport the match ran over, and this device's role in it
///  * enough identity to find the match again — room code for hotspot;
///    match id + poll cursor for online (see `RelayLink.since`, without
///    which a fresh `RelayLink` always starts its poll at 0 and replays
///    the match's ENTIRE message history, duplicating every chat line)
///  * the peer's name/loadout, so a resumed screen doesn't have to wait
///    on a fresh `hello` to render correctly
///  * [GameController.buildResumeSnapshot]'s own output — the wire
///    format and the disk format are the identical shape by
///    construction, and `restoreFromOwnSnapshot` already knows how to
///    rehydrate a snapshot a device wrote about itself
///  * `savedAt`, so a save from yesterday reads as stale rather than
///    being offered as a live match to walk back into
///
/// Only ever watches [GameController.hasRemotePeer] matches — there is
/// nothing to persist for a solo vsAiLan session; if the app closes, the
/// hidden AI opponent goes with it.
class MatchStore extends ChangeNotifier {
  static const _kKey = 'match.saved';

  /// Online: the server keeps an `active` match row indefinitely (see
  /// `sweep_matchmaking`'s own doc — it only ever TTLs `found` pairings),
  /// so this is a UX ceiling, not a server constraint: a save from
  /// yesterday is more likely to confuse than help.
  static const Duration kOnlineStaleAfter = Duration(hours: 24);

  /// Hotspot: much shorter — a room code and host address from two hours
  /// ago are essentially guaranteed to be wrong by then (the host's
  /// address can change, and the other device may not even still be on
  /// the same network).
  static const Duration kHotspotStaleAfter = Duration(hours: 2);

  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    notifyListeners();
  }

  /// The saved match, if there is one AND it isn't stale — null
  /// otherwise. Deliberately does not clear a stale entry on its own
  /// (see [clear]) so a caller checking "is there anything at all" and a
  /// caller checking "is there anything USABLE" can't disagree about
  /// what they just read.
  Map<String, dynamic>? get saved {
    final raw = _readRaw();
    if (raw == null) return null;
    final savedAt =
        DateTime.fromMillisecondsSinceEpoch(raw['savedAt'] as int? ?? 0);
    final isOnline = raw['transport'] == NetMode.online.index;
    final staleAfter = isOnline ? kOnlineStaleAfter : kHotspotStaleAfter;
    if (DateTime.now().difference(savedAt) > staleAfter) return null;
    return raw;
  }

  Map<String, dynamic>? _readRaw() {
    final raw = _prefs?.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return Map<String, dynamic>.from(m);
    } catch (_) {
      // A future version wrote a shape this one doesn't understand, or
      // the value is simply corrupt — no saved match beats crashing on
      // startup over what is, worst case, a missed resume.
      return null;
    }
  }

  /// Wipes the saved match. Every place a match genuinely ends — win,
  /// loss, surrender, abandon, a rematch starting fresh — should call
  /// this, or a stale save keeps being offered long after there is
  /// nothing left to resume.
  Future<void> clear() async {
    await _prefs?.remove(_kKey);
    notifyListeners();
  }

  // ---------------------------------------------------- LIVE WIRING ---

  GameController? _controller;
  NetworkService? _network;
  Timer? _debounce;
  int _lastWrittenStateSeq = -1;
  bool _lastWrittenPeerHasTurn = false;

  /// Last phase seen — the proxy this uses to detect "a battle just
  /// began" (covers both `beginBattle` and `restoreFromSnapshot`, which
  /// both set `phase = battling`) without needing either of them to know
  /// `MatchStore` exists. Both deserve an IMMEDIATE write rather than
  /// waiting out the debounce: if the app were killed in the first
  /// second of a match, there would otherwise be nothing on disk for it
  /// at all yet.
  BattlePhase? _lastPhase;

  static const Duration _debounceDelay = Duration(milliseconds: 1500);

  /// Starts watching [controller]/[network] for a live hotspot/online
  /// match and saving it on the cadence described in the class doc — a
  /// write whenever `stateSeq`/`peerHasTurn` actually changed, debounced
  /// so a burst of shots (a SALVO, say) writes once, not once per shot.
  /// Idempotent: call again (e.g. every `beginBattle`) to simply retarget
  /// which controller/network pair is being watched — a rematch gets a
  /// fresh debounce state rather than inheriting the last match's.
  void attach(GameController controller, NetworkService network) {
    detach();
    _controller = controller;
    _network = network;
    controller.addListener(_onControllerChanged);
    _lastWrittenStateSeq = -1;
    _lastWrittenPeerHasTurn = false;
    _lastPhase = null;
  }

  void detach() {
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
    _network = null;
    _debounce?.cancel();
    _debounce = null;
  }

  void _onControllerChanged() {
    final c = _controller;
    if (c == null) return;
    final enteredBattle =
        c.phase == BattlePhase.battling && _lastPhase != BattlePhase.battling;
    final justFinished =
        c.phase == BattlePhase.finished && _lastPhase != BattlePhase.finished;
    _lastPhase = c.phase;

    // One rule covers win, loss, surrender and abandon alike: whichever
    // path got here, `_finish`/`abandonMatch` already flipped `phase` to
    // `finished`, so there is nothing left worth resuming. A rematch
    // starting fresh overwrites this on its own next `beginBattle` flush
    // regardless, but clearing it here too closes the gap where the
    // player might close the app from the RESULT screen itself, before
    // ever deciding to rematch.
    if (justFinished && c.hasRemotePeer) {
      unawaited(clear());
      return;
    }
    if (!c.battling || !c.hasRemotePeer) return;

    if (enteredBattle) {
      unawaited(flushNow());
      return;
    }
    if (c.stateSeq == _lastWrittenStateSeq &&
        c.peerHasTurn == _lastWrittenPeerHasTurn) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _flush);
  }

  /// Forces an immediate write, bypassing the debounce — for the moments
  /// a save genuinely cannot wait 1.5s out: `beginBattle`,
  /// `restoreFromSnapshot`, and the app going into the background (see
  /// `main.dart`'s lifecycle observer — `paused` is the real save point;
  /// `detached` on Android often has no time left to finish a
  /// platform-channel write).
  Future<void> flushNow() async {
    _debounce?.cancel();
    _debounce = null;
    await _flush();
  }

  Future<void> _flush() async {
    _debounce = null;
    final c = _controller;
    final n = _network;
    final p = _prefs;
    if (c == null || n == null || p == null) return;
    if (!c.battling || !c.hasRemotePeer) return;

    _lastWrittenStateSeq = c.stateSeq;
    _lastWrittenPeerHasTurn = c.peerHasTurn;

    final data = <String, dynamic>{
      'transport': n.mode.index,
      'iAmHost': n.isHost,
      'roomCode': n.roomCode,
      'relayMatchId': n.relayMatchId,
      'relaySince': n.relaySince,
      'peerName': n.peerName,
      'peerShipSkinId': n.peerShipSkinId,
      'peerShipSkinChosen': n.peerShipSkinChosen,
      'peerCannonSkinId': n.peerCannonSkinId,
      'peerThemeId': n.peerThemeId,
      'snapshot': c.buildResumeSnapshot(),
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      await p.setString(_kKey, jsonEncode(data));
    } catch (_) {
      // Best-effort — a failed write just means the NEXT one (or the
      // still-live in-memory match, if the app never actually closes)
      // is what the player falls back to.
    }
  }
}
