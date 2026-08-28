import 'package:flutter_test/flutter_test.dart';

import 'package:battleship_blitz/services/loopback_link.dart';

/// Coverage for the four properties `LoopbackLink`'s doc comment claims:
/// async delivery, deep-copy isolation, pre-listen buffering and a
/// single-cascade close. Everything the vs-AI feature builds on top of
/// this link — turn passing, power-up resolution, the whole match
/// protocol — depends on every one of these actually holding.
void main() {
  group('LoopbackLink', () {
    test('delivery is asynchronous — nothing arrives inside send()', () {
      final (a, b) = LoopbackLink.pair();
      var received = false;
      b.messages.listen((_) => received = true);

      a.send({'type': 'hello'});
      // If delivery were synchronous this would already be true — the
      // whole point is that it is NOT, so the sender's call stack can
      // never re-enter game state still being mutated by that same send.
      expect(received, isFalse);
    });

    test('the sent message does arrive, on the next microtask', () async {
      final (a, b) = LoopbackLink.pair();
      final got = <Map<String, dynamic>>[];
      b.messages.listen(got.add);

      a.send({'type': 'fire', 'r': 3, 'c': 4});
      await Future<void>.delayed(Duration.zero);

      expect(got, hasLength(1));
      expect(got.single, {'type': 'fire', 'r': 3, 'c': 4});
    });

    test('is bidirectional', () async {
      final (a, b) = LoopbackLink.pair();
      final aGot = <Map<String, dynamic>>[];
      final bGot = <Map<String, dynamic>>[];
      a.messages.listen(aGot.add);
      b.messages.listen(bGot.add);

      a.send({'type': 'hello', 'name': 'A'});
      b.send({'type': 'hello', 'name': 'B'});
      await Future<void>.delayed(Duration.zero);

      expect(aGot.single['name'], 'B');
      expect(bGot.single['name'], 'A');
    });

    test('deep-copies — mutating the sent map after send() does not '
        'affect what the peer receives', () async {
      final (a, b) = LoopbackLink.pair();
      final got = <Map<String, dynamic>>[];
      b.messages.listen(got.add);

      final ships = <Map<String, dynamic>>[
        {'r': 0, 'c': 0}
      ];
      final msg = <String, dynamic>{
        'type': 'board',
        'b': {'ships': ships},
      };
      a.send(msg);
      // Mutate the ORIGINAL list after sending — a shared reference would
      // leak this into what the peer sees.
      ships.clear();
      await Future<void>.delayed(Duration.zero);

      expect((got.single['b'] as Map)['ships'], hasLength(1),
          reason: 'the peer must have its own copy, not a live reference');
    });

    test('buffers a message sent before anyone is listening, and delivers '
        'it once someone does', () async {
      final (a, b) = LoopbackLink.pair();
      a.send({'type': 'board', 'b': 'placeholder'}); // sent before b listens

      final got = <Map<String, dynamic>>[];
      b.messages.listen(got.add);
      await Future<void>.delayed(Duration.zero);

      expect(got, hasLength(1));
      expect(got.single['type'], 'board');
    });

    test('preserves order between buffered and post-listen messages',
        () async {
      final (a, b) = LoopbackLink.pair();
      a.send({'type': 'hello'});
      a.send({'type': 'board'});

      final got = <String>[];
      b.messages.listen((m) => got.add(m['type'] as String));
      a.send({'type': 'fire'});
      await Future<void>.delayed(Duration.zero);

      expect(got, ['hello', 'board', 'fire']);
    });

    test('close() cascades to the peer exactly once (no infinite '
        'recursion)', () async {
      final (a, b) = LoopbackLink.pair();
      var aClosedEvents = 0;
      var bClosedEvents = 0;
      a.messages.listen((_) {}, onDone: () => aClosedEvents++);
      b.messages.listen((_) {}, onDone: () => bClosedEvents++);

      await a.close();

      expect(aClosedEvents, 1);
      expect(bClosedEvents, 1);
    });

    test('a message sent after close() is silently dropped', () async {
      final (a, b) = LoopbackLink.pair();
      final got = <Map<String, dynamic>>[];
      b.messages.listen(got.add);

      await a.close();
      a.send({'type': 'fire'}); // must not throw
      await Future<void>.delayed(Duration.zero);

      expect(got, isEmpty);
    });

    test('closing the SECOND end after the first is already closed is a '
        'safe no-op', () async {
      final (a, b) = LoopbackLink.pair();
      await a.close();
      await b.close(); // must not throw
    });
  });
}
