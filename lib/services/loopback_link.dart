import 'dart:async';
import 'dart:convert';

import 'network_service.dart';

/// An in-process [GameLink] pair — what lets a vs-AI match run over the
/// EXACT same match protocol a hotspot or online match does, instead of
/// rewiring firing/turn/power-up rule code that already works for two
/// real players. The AI opponent gets its own hidden [GameController] +
/// [NetworkService], joined to the player's by one of these pairs, and
/// from either side's point of view it is indistinguishable from a real
/// opponent on the other end of a socket.
///
/// Two things this deliberately gets right, both learned from bugs
/// elsewhere in this file's siblings:
///
///  * **Delivery is asynchronous.** [StreamController.broadcast] already
///    defaults to `sync: false`, so `add` here returns before any
///    listener runs — do not "fix" that with `sync: true`. A synchronous
///    delivery would let the AI's shot resolve INSIDE the player's own
///    `fireAt` call stack, re-entering game state while it's still being
///    mutated.
///  * **A message sent before the recipient is listening is not lost.**
///    Both real [GameLink]s have exactly this failure mode — see the doc
///    on `NetworkService._peerBoardMsg`, which exists because a broadcast
///    stream drops anything emitted with nobody subscribed. Rather than
///    relying on both `startLoopbackMatch` calls attaching their listener
///    in the right order, this buffers anything sent before the first
///    listener attaches and flushes it the moment one does.
class LoopbackLink implements GameLink {
  LoopbackLink._() {
    _controller.onListen = () {
      for (final msg in _pending) {
        _controller.add(msg);
      }
      _pending.clear();
    };
  }

  /// Builds a connected pair — whatever `a` sends arrives on `b.messages`
  /// and vice versa.
  static (LoopbackLink a, LoopbackLink b) pair() {
    final a = LoopbackLink._();
    final b = LoopbackLink._();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  late final LoopbackLink _peer;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> _pending = [];
  bool _closed = false;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  void send(Map<String, dynamic> msg) {
    if (_closed) return;
    // Deep-copy via a JSON round-trip: both real links round-trip JSON
    // too (one over a socket, one over HTTP), so sharing a mutable object
    // graph directly here — e.g. `Board.toJson()`'s nested lists — would
    // let a mutation on one controller's copy corrupt the other's.
    final copy =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(msg)) as Map);
    _peer._deliver(copy);
  }

  void _deliver(Map<String, dynamic> msg) {
    if (_closed) return;
    if (_controller.hasListener) {
      _controller.add(msg);
    } else {
      _pending.add(msg);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    if (!_controller.isClosed) await _controller.close();
    // Cascades to the peer so closing either end tears down both — guarded
    // against recursion by the `_closed` check at the top of this method,
    // which the peer's own re-entrant call to `close()` will hit.
    await _peer.close();
  }
}
