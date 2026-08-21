import 'package:battleship_blitz/models/game_models.dart';
import 'package:battleship_blitz/screens/placement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where a dragged ship actually lands on Player 2's upside-down board.
///
/// The reported bug: on Player 2's turn to deploy, the green/red drop
/// highlight and the ghost ship under the finger disagreed, and the
/// longer the ship the further apart they were. Two facts are in tension
/// there, and both are true:
///
///  * Player 2's board is inside a 180° `RotatedBox`, and
///    `RenderBox.globalToLocal` unwinds that transform correctly;
///  * the drag ghost is NOT inside it — `Draggable` renders `feedback`
///    into the root `Overlay` — so the finger marks the ghost's top-left
///    in SCREEN space, which under a half turn is the ship's far end in
///    BOARD space.
///
/// So the first group pins the rotation identity the fix relies on, and
/// the second pins the correction built on it.
void main() {
  group('a 180° rotation maps a box to its opposite corner', () {
    testWidgets('screen top-left of a rect is its local bottom-right',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RotatedBox(
              quarterTurns: 2,
              child: SizedBox(key: key, width: 200, height: 100),
            ),
          ),
        ),
      );

      final box = key.currentContext!.findRenderObject() as RenderBox;
      final screenTopLeft = box.localToGlobal(const Offset(200, 100));

      // Whatever the box's own local origin is, the point that appears at
      // its screen top-left is its local BOTTOM-RIGHT — which is exactly
      // why the pointer cannot be treated as a ship's origin here.
      expect(box.globalToLocal(screenTopLeft), const Offset(200, 100));

      // And the identity the correction uses: because the turn is exactly
      // 180°, moving by +d on screen moves by -d in local space, so the
      // correction is a subtraction rather than an approximation.
      const d = Offset(37, 11);
      expect(
        box.globalToLocal(screenTopLeft + d),
        const Offset(200, 100) - d,
      );
    });
  });

  group('dropOrigin', () {
    const cell = 30.0;

    test('Player 1 drops exactly where the finger is', () {
      // Not flipped: the ghost's top-left and the finger are the same
      // point in the same space, so nothing is corrected.
      for (final spec in kFleet) {
        expect(
          dropOrigin(
            pointerLocal: const Offset(90, 60),
            flipped: false,
            shipCells: spec.size,
            horizontal: true,
            cell: cell,
          ),
          const Offset(90, 60),
        );
      }
    });

    test('Player 2 recovers the origin from the ship\'s far corner', () {
      // Carrier, five cells, laid horizontally: the finger sits on the
      // far corner, so the origin is five cells left and one cell up.
      expect(
        dropOrigin(
          pointerLocal: const Offset(300, 120),
          flipped: true,
          shipCells: 5,
          horizontal: true,
          cell: cell,
        ),
        const Offset(300 - 150, 120 - 30),
      );
    });

    test('a vertical ship is corrected along the other axis', () {
      expect(
        dropOrigin(
          pointerLocal: const Offset(300, 120),
          flipped: true,
          shipCells: 4,
          horizontal: false,
          cell: cell,
        ),
        const Offset(300 - 30, 120 - 120),
      );
    });

    test('the error it fixes scales with the ship, which is the symptom',
        () {
      // The user-visible shape of the bug: a two-cell destroyer looked
      // very nearly right and a five-cell carrier looked completely
      // broken. That is the uncorrected offset growing with ship length.
      int cellsWrong(int shipCells) {
        const pointer = Offset(300, 120);
        final fixed = dropOrigin(
          pointerLocal: pointer,
          flipped: true,
          shipCells: shipCells,
          horizontal: true,
          cell: cell,
        );
        return ((pointer.dx - fixed.dx) / cell).round();
      }

      expect(cellsWrong(2), 2);
      expect(cellsWrong(5), 5);
    });

    test('the corrected origin puts the ship back over the finger', () {
      // The real acceptance test: place the ship at the corrected origin
      // and its far corner must land back on the pointer. If that holds,
      // the highlight and the ghost cover the same cells.
      for (final spec in kFleet) {
        for (final horizontal in [true, false]) {
          const pointer = Offset(270, 210);
          final origin = dropOrigin(
            pointerLocal: pointer,
            flipped: true,
            shipCells: spec.size,
            horizontal: horizontal,
            cell: cell,
          );
          final extent = horizontal
              ? Offset(cell * spec.size, cell)
              : Offset(cell, cell * spec.size);
          expect(origin + extent, pointer,
              reason: '${spec.name} ${horizontal ? 'across' : 'down'}');
        }
      }
    });
  });
}
