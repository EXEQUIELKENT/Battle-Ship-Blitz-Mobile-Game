import 'package:flutter_test/flutter_test.dart';

import 'package:battleship_blitz/services/network_service.dart';

/// The mid-match reconnect grace window: how long a dropped opponent's
/// seat is held open, and — the actual bug fixed here — the difference
/// between "the visible countdown ran out" (should still be revocable by
/// a late-but-real rejoin) and "they explicitly left" (final). See the
/// BUGFIX comment on `rejoining` in `NetworkService._handleIncoming`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // A static field — leaking a fast override into an unrelated test
    // would make its own timers fire far quicker than it expects.
    NetworkService.graceTickIntervalForTest = const Duration(seconds: 1);
  });

  group('opening the grace window', () {
    test('marks the peer lost and starts the visible countdown', () {
      final net = NetworkService();
      net.inMatch = true;
      net.openGraceWindowForTest();

      expect(net.peerLost, isTrue);
      expect(net.peerGone, isFalse);
      expect(net.graceSecondsLeft, NetworkService.kReconnectGraceSeconds);
    });

    test('is a no-op outside a running match', () {
      final net = NetworkService();
      net.inMatch = false;
      net.openGraceWindowForTest();
      expect(net.peerLost, isFalse);
    });

    test('is idempotent — a second drop report does not restart the '
        'clock', () {
      final net = NetworkService();
      net.inMatch = true;
      net.openGraceWindowForTest();
      net.graceSecondsLeft = 10; // pretend some time has already passed
      net.openGraceWindowForTest();
      expect(net.graceSecondsLeft, 10,
          reason: 'a second, redundant "they dropped" report must not '
              'reset a countdown already in progress');
    });
  });

  group('the peerGone rule', () {
    // BUGFIX: `rejoining` used to gate on `!peerGone`, but `_endGrace
    // (gone: false)` — called from INSIDE that same `rejoining` branch —
    // is what clears `peerGone` on a successful reconnect. Once the
    // visible countdown expired and set `peerGone`, a genuine rejoin
    // arriving even a moment later could never get past the very flag it
    // exists to clear. See the doc on `rejoining` itself.
    test('a rejoin hello after the grace window has fully expired is '
        'still admitted', () async {
      NetworkService.graceTickIntervalForTest = Duration.zero;
      final net = NetworkService();
      net.inMatch = true;
      net.openGraceWindowForTest();

      // Run the tick loop out past BOTH the visible countdown and the
      // silent hold behind it, at the accelerated rate.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(net.peerGone, isTrue,
          reason: 'the window must have fully expired by now');
      expect(net.peerLeftMatch, isFalse,
          reason: 'nobody actually SENT a leave message in this test');

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await Future<void>.delayed(Duration.zero);

      expect(net.peerLost, isFalse,
          reason: 'a genuine rejoin must close the grace window');
      expect(net.peerGone, isFalse,
          reason: 'arriving late must not leave them stuck "gone"');
    });

    test('a rejoin hello after an explicit leave is refused', () async {
      final net = NetworkService();
      net.inMatch = true;
      net.handleIncomingForTest({'type': 'leave'});
      await Future<void>.delayed(Duration.zero);
      expect(net.peerLeftMatch, isTrue);
      expect(net.peerGone, isTrue);

      net.handleIncomingForTest(
          {'type': 'hello', 'name': 'Returner', 'rejoin': 1});
      await Future<void>.delayed(Duration.zero);

      // `peerLeftMatch` is the one thing an incoming "rejoin" claim can
      // never talk its way past.
      expect(net.peerGone, isTrue,
          reason: 'an explicit leave must not be un-said by a later '
              'hello claiming rejoin');
    });
  });

  group('the silent seat hold', () {
    test('reaching zero on the visible countdown does not itself mark '
        'the peer gone', () {
      final net = NetworkService();
      net.inMatch = true;
      net.openGraceWindowForTest();
      net.graceSecondsLeft = 0; // as if the visible countdown just ended
      expect(net.peerGone, isFalse);
      expect(net.peerLost, isTrue,
          reason: 'still silently holding the seat open past zero');
    });

    test('the seat is eventually given up for real once the silent hold '
        'itself runs out', () async {
      NetworkService.graceTickIntervalForTest = Duration.zero;
      final net = NetworkService();
      net.inMatch = true;
      net.openGraceWindowForTest();

      await Future<void>.delayed(const Duration(seconds: 3));

      expect(net.peerGone, isTrue);
      expect(net.peerLost, isFalse);
    });
  });
}
