import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../art/family_shell_art.dart';
import '../art/fleet_family.dart';
import '../art/legacy_shell_art.dart';
import '../core/theme.dart';
import '../models/game_models.dart';
import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_notification.dart';
import '../widgets/battle_grid.dart';
import '../widgets/cannon_widget.dart';
import '../widgets/match_chat.dart';
import '../widgets/neon_widgets.dart';
import '../widgets/reconnect_overlay.dart';
import '../widgets/ship_painter.dart';
import 'battle_screen.dart';

/// Which cell a dragged ship's ORIGIN lands on, given where the finger
/// is in the grid's own coordinates.
///
/// Pure, and separated out from the screen, because it is the whole of a
/// bug that took a while to see: the correction depends on facts about
/// two different coordinate systems and nothing about widgets.
///
/// For Player 1, the pointer IS the origin — `pointerDragAnchorStrategy`
/// pins the drag ghost's top-left to the finger, and the ghost is drawn
/// the same way up as the board. For Player 2 the board is inside a 180°
/// `RotatedBox` but the ghost is not: `Draggable` renders `feedback` into
/// the root `Overlay`, outside that rotation. So the finger still marks
/// the ghost's top-left ON SCREEN, and under a half turn a screen
/// top-left is a board BOTTOM-RIGHT — the ship's far end, not its start.
///
/// Because the rotation is exactly 180°, the fix is exact rather than
/// approximate: subtracting the ship's own extent recovers the origin.
Offset dropOrigin({
  required Offset pointerLocal,
  required bool flipped,
  required int shipCells,
  required bool horizontal,
  required double cell,
}) {
  if (!flipped) return pointerLocal;
  final extent = horizontal
      ? Offset(cell * shipCells, cell)
      : Offset(cell, cell * shipCells);
  return pointerLocal - extent;
}

/// "Deploy your ships" — reference-style placement:
/// drag ships from the top dock onto the grid (or tap an empty cell with
/// a dock ship selected), tap a placed ship to rotate it, RANDOM + green
/// SAVE buttons. Tapping an empty cell with NOTHING selected fires a
/// cosmetic cannon preview instead (see `_firePreviewShot`).
class PlacementScreen extends StatefulWidget {
  final bool isPlayer2;

  const PlacementScreen({super.key, this.isPlayer2 = false});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

// `TickerProviderStateMixin`, not the Single- variant: the cannon preview
// runs the shell's flight clock and the gun's reload clock at once (see
// `_previewShotCtrl` / `_previewReloadCtrl`), and the Single- mixin
// asserts on the second ticker.
class _PlacementScreenState extends State<PlacementScreen>
    with TickerProviderStateMixin {
  /// Which seat this screen belongs to in local pass-and-play — the index
  /// into `GameController.localLoadouts`.
  int get _seat => widget.isPlayer2 ? 1 : 0;

  late Board _board;
  ShipKind? _selected; // currently chosen dock ship
  bool _showHandoff = false;
  static const double _dockH = 64;

  // Former fixed cannon bay height (92) — now the cannon overhangs the
  // grid instead of stealing height from it, so this is kept only for
  // reference.
  // ignore: unused_field
  static const double _cannonBayH = 92;

  // Dock icon keys so RANDOM can pull ships directly from their preview
  // slots instead of from a generic point underneath.
  final Map<ShipKind, GlobalKey> _dockKeys = {
    for (final s in kFleet) s.kind: GlobalKey(),
  };
  final GlobalKey _stackKey = GlobalKey();

  /// Per-ship starting scale for the RANDOM button's dock "pull" (see
  /// `BattleGrid.pullInScales`), computed fresh each time a ship leaves
  /// the dock in `_runRandomize` from that ship's own dock icon size vs.
  /// its full on-board size — the same ratio the old ghost overlay used,
  /// so a Cruiser doesn't shrink by the same amount a Carrier does. Left
  /// in place (not cleared) once a ship lands; `BattleGrid` only ever
  /// consults an entry once per ship kind, so a stale one afterward is
  /// harmless.
  final Map<ShipKind, double> _pullInScales = {};

  /// Per-ship PRECISE starting center (see `BattleGrid.pullInFrom`) for
  /// the RANDOM button's dock "pull" — the dock icon's true on-screen
  /// center, converted into the grid's own local coordinate space, kept
  /// at full pixel precision rather than rounded to a cell. Computed
  /// alongside `_pullInScales`; same "stale entries are harmless" note
  /// applies.
  final Map<ShipKind, Offset> _pullInFrom = {};

  /// True while a RANDOM-triggered reshuffle is staggering ships into
  /// their new spots (see [_randomize]) — disables the RANDOM/SAVE
  /// buttons and drag/tap interaction so the player can't yank a ship or
  /// fire off a second shuffle mid-animation.
  bool _randomizing = false;

  /// True while a LAN/online SAVE is blocked on the opponent's fleet —
  /// see [_waitForPeerBoard]. Drives the "WAITING FOR OPPONENT…" dialog's
  /// own lifecycle rather than the dialog's mere presence, so system BACK
  /// (which pops the dialog route without this screen ever finding out)
  /// can be routed through the same cancel logic as the CANCEL button.
  bool _waitingForPeer = false;

  /// The subscription `_waitForPeerBoard` is listening on. A LOCAL
  /// variable here used to leak: never cancelled on `dispose()`, and
  /// still live if the player backed out of the dialog, so the peer's
  /// board — arriving after that — popped whatever route happened to be
  /// on top (see the BUGFIX note in `_waitForPeerBoard`).
  StreamSubscription? _peerBoardSub;

  /// Listens to `NetworkService` for the OPPONENT's pre-battle drop and
  /// return — see [_onNetForPeer]. Separate from [_peerBoardSub] (which
  /// is the per-wait `board`/`board_cancel` message feed); this one lives
  /// for the whole screen so a drop is noticed whether or not we happen
  /// to be mid-`_waitForPeerBoard`. `ChangeNotifier.addListener` returns
  /// void, so the pair is kept for `removeListener` in [dispose].
  NetworkService? _netPeer;
  VoidCallback? _netPeerCb;

  /// True once this device's fleet has been sent to the opponent (see
  /// `_save`). The peer's rejoin needs us to send it again — their socket
  /// was gone the first time — so the drop handler below can know whether
  /// a re-send is owed. Cleared when the player manually cancels the
  /// wait (their board is no longer on the wire).
  bool _sentBoard = false;

  /// The previous value of `NetworkService.peerLost`, so [_onNetForPeer]
  /// can tell a drop START from a RETURN (edge, not level).
  bool _lastPeerLost = false;

  /// True once the RANDOM button has dealt a first layout onto a board
  /// that started completely empty. That first deal is the one case where
  /// `BattleGrid`'s `AnimatedPositioned` has no previous ship position to
  /// ease FROM (see `_ShipEntrance`), so every ship would otherwise just
  /// blink onto the grid at once instead of dropping in like every later
  /// reshuffle already does. Sticky rather than reset after use: once the
  /// board has any ship on it, `_board.ships` is never empty again for the
  /// rest of this placement session (RANDOM replaces ships one kind at a
  /// time, it never clears the board), so there is no later "first mount"
  /// left for this to affect either way.
  bool _entranceDeal = false;

  /// Live "where will this land" highlight — driven by whichever drag is
  /// currently active: a fresh ship being dragged in from the dock tray,
  /// or an already-placed ship being repositioned on the grid.
  PlacedShip? _previewShip;
  bool _previewValid = true;

  // ---------------------------------------------------- CANNON PREVIEW ---
  // Tapping an EMPTY cell with nothing selected from the dock isn't a
  // placement action at all (see `_onGridTap`), so rather than doing
  // nothing it lets the player test-fire their cannon at that cell —
  // recoil, smoke, sound, a shell in flight and the same targeting
  // reticle a real battle shot gets — purely as a taste of "what does
  // firing look like" while the fleet is still being laid out. Nothing
  // here is tracked or resolved: there's no opponent board to hit yet,
  // so none of this ever touches `Board` or `GameController`.

  /// Feeds `CannonWidget.fireTrigger` so the deploy cannon plays its
  /// normal recoil + muzzle-smoke show on a preview shot, same as it
  /// would for a real one in battle.
  final StreamController<void> _previewFireCtrl =
      StreamController<void>.broadcast();

  /// Feeds `CannonWidget.readyTrigger` so the deploy cannon gives its
  /// "loaded — fire!" flash the moment a preview reload finishes, exactly
  /// as it does when a battle turn comes around.
  final StreamController<void> _previewReadyCtrl =
      StreamController<void>.broadcast();

  /// The deploy cannon's reload clock: 0 the instant a preview shot goes
  /// off, running back up to 1 (ready) over the same
  /// `kCooldownSeconds * cannonSkin.cooldownFactor` a real shot costs in
  /// battle. Feeds `CannonWidget.cooldownFraction` — so the gun draws its
  /// actual reload ring here rather than sitting permanently ready — and
  /// gates [_firePreviewShot].
  ///
  /// BUGFIX (the deploy cannon was a machine gun): the preview used to
  /// pass a hardcoded `cooldownFraction: 1` and gate nothing at all, so
  /// every tap restarted the shell mid-flight. Firing as fast as you
  /// could tap is not what the cannon you are previewing actually does,
  /// and each new shot cut the last one's recoil and smoke short — which
  /// is why the gun looked like it never animated at all.
  late final AnimationController _previewReloadCtrl;

  /// Cell a preview shell is currently arcing toward — drives
  /// `BattleGrid.aimCell` (and so its built-in targeting reticle) for
  /// exactly as long as the shell is airborne, then clears.
  List<int>? _previewAimCell;

  /// Recent preview combat events (e.g. miss water splashes when test firing).
  final List<CombatEventLike> _previewEvents = [];

  /// The lone preview shell's flight clock. An empty-cell tap is purely
  /// cosmetic and can't overlap a real placement action, so — unlike
  /// battle's per-shooter cannonball pair — there is only ever one shot
  /// in flight here at a time.
  late final AnimationController _previewShotCtrl;
  Offset _previewShotFrom = Offset.zero;
  Offset _previewShotTo = Offset.zero;
  double _previewShotCell = 32;
  double _previewShotArc = 64;

  // Grid/cannon geometry, cached each build from the same `LayoutBuilder`
  // math that positions the real grid and cannon widgets below, so a tap
  // can be converted straight into this `Stack`'s own local coordinate
  // space without a second, redundant measurement of a layout that very
  // builder just computed.
  double _gridLeftPx = 0;
  double _gridTopPx = 0;
  double _gridSidePx = 1; // never 0 — guards the pre-layout divide below
  double _cannonCenterXPx = 0;
  double _cannonCenterYPx = 0;
  double _cannonRenderSizePx = 0;
  double _cannonMuzzleFrac = CannonWidget.muzzleFraction;

  /// This loadout's reload time, cached from the same build that reads the
  /// geometry above — the equipped cannon can be swapped from the GEAR
  /// dialog without leaving this screen, and two of the skins reload
  /// noticeably faster (see `CannonSkin.cooldownFactor`).
  Duration _cannonReload = const Duration(seconds: kCooldownSeconds);

  @override
  void initState() {
    super.initState();
    _previewShotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    // Starts at 1 — the gun is loaded and ready the moment you arrive.
    _previewReloadCtrl = AnimationController(
      vsync: this,
      duration: _cannonReload,
      value: 1,
    );
    SoundService.instance.stopMenuMusic();
    final controller = context.read<GameController>();
    _board = widget.isPlayer2 ? controller.boards[1] : controller.boards[0];
    // This screen IS the pre-battle match for REMOTE-PEER modes — a
    // dropped opponent here opens the reconnect window (see
    // `NetworkService.beginPreMatch`). Crucially this also runs when a
    // REJOINING player is routed straight here (deploy-stage rejoin), so
    // the flag is set on both sides of the drop. Gated on `hasRemotePeer`
    // rather than `usesMatchProtocol` on purpose: a vsAiLan loopback
    // opponent lives in this process and can never "reconnect", so it
    // must not open a reconnect window either.
    if (controller.hasRemotePeer) {
      // BUGFIX: `beginPreMatch()` calls `notifyListeners()`, which cannot
      // run synchronously from inside `initState()` — see the identical
      // fix and its full explanation on `LanModeScreen.initState`, the
      // other call site. The listener registration and `peerLost` read
      // right below stay synchronous; only the notifying call itself
      // needs the one-frame delay.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.network.beginPreMatch();
      });
      _netPeer = controller.network;
      _netPeerCb = _onNetForPeer;
      _netPeer!.addListener(_netPeerCb!);
      _lastPeerLost = controller.network.peerLost;
    }
    // Warm this seat's themed sound pools before the first tap can ask
    // for one — the cannon-preview fire/miss/reload and every place/move
    // sound below are all themed variants (see
    // `SoundService.warmLoadout` for why the pre-warm exists).
    final seatLoadout = widget.isPlayer2
        ? controller.localLoadouts[1]
        : Loadout.of(context.read<ProfileStore>());
    SoundService.instance.warmLoadout(
      cannonSkinId: seatLoadout.cannonSkinId,
      shipSkinId: seatLoadout.shipSkinId,
      themeId: seatLoadout.themeId,
    );
    // `_cellSize()` below falls back to a rough MediaQuery-based estimate
    // until the grid has actually been laid out at least once (its
    // RenderBox isn't available on the very first build). That first,
    // slightly-off estimate is what gets baked into the dock ships' drag
    // "feedback" size — and since the carrier (5 cells, first in the
    // dock) is usually the very first ship a player drags, a small
    // per-cell error is magnified 5x, producing an oversized/misaligned
    // ghost exactly on that first placement (subsequent drags are fine,
    // since by then a rebuild has already happened and picked up the
    // real size). Scheduling one harmless extra rebuild right after the
    // first frame guarantees the real, precise cell size is in place
    // before the player can interact with anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _peerBoardSub?.cancel();
    if (_netPeerCb != null) _netPeer?.removeListener(_netPeerCb!);
    _netPeer = null;
    _netPeerCb = null;
    _previewFireCtrl.close();
    _previewReadyCtrl.close();
    _previewShotCtrl.dispose();
    _previewReloadCtrl.dispose();
    super.dispose();
  }

  /// The opponent dropped / returned while we're deploying. On a drop:
  /// tear down any "waiting for their fleet" dialog so the reconnect
  /// overlay can be seen, and remember our board is still owed. On their
  /// return: re-send our fleet (the one we sent before the drop is gone
  /// — their socket was down) and resume the wait for theirs.
  void _onNetForPeer() {
    if (!mounted) return;
    final controller = context.read<GameController>();
    if (!controller.hasRemotePeer) return;
    final net = controller.network;
    final lost = net.peerLost;
    if (lost && !_lastPeerLost) {
      // Started a drop.
      _lastPeerLost = true;
      // The fleet they sent before dying is from a placement that no
      // longer exists — see `NetworkService.clearPeerBoard`.
      net.clearPeerBoard();
      if (_waitingForPeer) {
        _cancelWaitingForPeer(controller, popDialog: true, keepBoard: true);
      }
    } else if (!lost && _lastPeerLost) {
      // They're back.
      _lastPeerLost = false;
      if (_sentBoard) {
        controller.network.sendBoard(_board);
        _waitForPeerBoard(controller);
      }
    } else {
      _lastPeerLost = lost;
    }
  }

  ShipSpec? get _selectedSpec =>
      _selected == null ? null : kFleet.firstWhere((s) => s.kind == _selected);

  bool get _allPlaced => _board.isComplete;

  void _rotateShip(ShipKind kind) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    final spec = ship.spec;
    final origRow = ship.row;
    final origCol = ship.col;
    final origHorizontal = ship.horizontal;
    final newHorizontal = !origHorizontal;
    // BUGFIX (rotated ship visibly nudges/pops on its next move): this
    // used to call `_board.removeShip(kind)` up front so `canPlace`
    // wouldn't collide with the ship's OWN current cells while probing
    // candidate spots, then `_board.place(...)` the winner back in. But
    // `place` always APPENDS to `Board.ships`, and `ships` paints in list
    // order (see `BattleGrid._shipWidgets`) — so every single rotation
    // silently moved this ship to the END of the paint order, exactly
    // the z-order-reshuffle bug `PlacementScreen._runRandomize` already
    // had to work around for the RANDOM button (see the bugfix note in
    // `_runRandomize`). `_canPlaceIgnoring` gets the same "don't collide
    // with myself" behaviour without ever removing the ship from the
    // list, and `Board.reposition` commits the winning spot AT THE SAME
    // INDEX — so a rotation, like a reshuffle, only ever animates
    // position/rotation, never paint order.
    var r = origRow;
    var c = origCol;
    if (newHorizontal && c + spec.size > kBoardSize) {
      c = kBoardSize - spec.size;
    }
    if (!newHorizontal && r + spec.size > kBoardSize) {
      r = kBoardSize - spec.size;
    }
    // IMPROVEMENT (rotate now finds a way to turn): the direct anchor
    // above is blocked whenever another hull sits where the newly
    // oriented ship would land — the old behaviour just gave up right
    // there and snapped the ship back to how it was. Instead, search the
    // rest of the board for the nearest anchor where the new orientation
    // actually fits, and turn there instead. Only when NOTHING on the
    // whole board can hold this orientation does the rotation actually
    // fail.
    if (!_canPlaceIgnoring(kind, spec, r, c, newHorizontal)) {
      final found = findNearestRotationAnchor(
        size: spec.size,
        horizontal: newHorizontal,
        anchorRow: origRow,
        anchorCol: origCol,
        canPlaceAt: (rr, cc) =>
            _canPlaceIgnoring(kind, spec, rr, cc, newHorizontal),
      );
      if (found != null) {
        r = found.row;
        c = found.col;
      }
    }
    if (_canPlaceIgnoring(kind, spec, r, c, newHorizontal)) {
      _board.reposition(kind, r, c, newHorizontal);
      SoundService.instance.place(shipSkinId: _shipSkinId);
    } else {
      // Truly nowhere on the board can hold this orientation — nothing
      // was ever removed this time, so there's nothing to put back;
      // the ship simply stays exactly as it was.
      SoundService.instance.denied();
    }
    setState(() {});
  }

  void _moveShip(ShipKind kind, int newRow, int newCol) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    var r = newRow;
    var c = newCol;
    if (ship.horizontal && c + ship.spec.size > kBoardSize) {
      c = kBoardSize - ship.spec.size;
    }
    if (!ship.horizontal && r + ship.spec.size > kBoardSize) {
      r = kBoardSize - ship.spec.size;
    }
    if (r == ship.row && c == ship.col) {
      setState(() => _previewShip = null);
      return;
    }
    // Same z-order-preserving fix as `_rotateShip` above: validate with
    // `_canPlaceIgnoring` (ignores this ship's own current cells) and
    // commit with `Board.reposition` (same list index) instead of the
    // old remove-then-append `removeShip` + `place` pair, so dragging an
    // already-placed ship around the board never reorders paint order
    // either.
    if (_canPlaceIgnoring(kind, ship.spec, r, c, ship.horizontal)) {
      _board.reposition(kind, r, c, ship.horizontal);
      SoundService.instance.place(shipSkinId: _shipSkinId);
    } else {
      SoundService.instance.denied();
    }
    setState(() => _previewShip = null);
  }

  /// [Board.canPlace] but treating [ignore]'s own current footprint as
  /// unoccupied — used for the live drag highlight so a ship being
  /// repositioned doesn't flag itself as a collision.
  bool _canPlaceIgnoring(
    ShipKind ignore,
    ShipSpec spec,
    int row,
    int col,
    bool horizontal,
  ) {
    if (horizontal) {
      if (col + spec.size > kBoardSize) return false;
    } else {
      if (row + spec.size > kBoardSize) return false;
    }
    for (var i = 0; i < spec.size; i++) {
      final r = horizontal ? row : row + i;
      final c = horizontal ? col + i : col;
      final occupant = _board.shipAt(r, c);
      if (occupant != null && occupant.spec.kind != ignore) return false;
    }
    return true;
  }

  /// Live highlight while an already-placed ship is being dragged around
  /// the grid — called continuously as the finger moves, before the drag
  /// actually ends (see [_moveShip]).
  void _onShipDragPreview(ShipKind kind, int row, int col) {
    final ship = _board.shipOfKind(kind);
    if (ship == null) return;
    final spec = ship.spec;
    final horizontal = ship.horizontal;
    var r = row;
    var c = col;
    if (horizontal && c + spec.size > kBoardSize) {
      c = kBoardSize - spec.size;
    }
    if (!horizontal && r + spec.size > kBoardSize) {
      r = kBoardSize - spec.size;
    }
    setState(() {
      _previewShip = PlacedShip(
        spec: spec,
        row: r,
        col: c,
        horizontal: horizontal,
      );
      _previewValid = _canPlaceIgnoring(kind, spec, r, c, horizontal);
    });
  }

  void _onGridTap(int r, int c) {
    final spec = _selectedSpec;
    if (spec == null) {
      // Nothing selected from the dock, so this can't be a placement
      // tap — and `BattleGrid` only ever forwards a tap through to here
      // when the cell is genuinely empty; one already holding a ship is
      // intercepted upstream and rotates it instead (see `onShipTap`).
      // Give the player something to do with it: test-fire the cannon
      // and preview the shot they'll be lining up all through battle.
      _firePreviewShot(r, c);
      return;
    }
    // Try horizontal first, then vertical.
    if (_board.canPlace(spec, r, c, true)) {
      _board.place(spec, r, c, true);
      SoundService.instance.place(shipSkinId: _shipSkinId);
      setState(() => _selected = null);
    } else if (_board.canPlace(spec, r, c, false)) {
      _board.place(spec, r, c, false);
      SoundService.instance.place(shipSkinId: _shipSkinId);
      setState(() => _selected = null);
    } else {
      SoundService.instance.denied();
    }
  }

  /// The ship skin this seat is deploying with — the same gear rule
  /// `_firePreviewShot` applies. Every place/move sound below is keyed by
  /// it so each fleet slides and settles to its own audio (see
  /// `SoundService.place` / `SoundService.shipMove`).
  String get _shipSkinId {
    final controller = context.read<GameController>();
    final isLocal = controller.mode == GameMode.local;
    final profile = context.read<ProfileStore>();
    return isLocal
        ? controller.localLoadouts[_seat].shipSkinId
        : profile.shipSkinId;
  }

  /// Cosmetic-only preview shot at an empty deploy-grid cell — see the
  /// `CANNON PREVIEW` fields above for the full contract. Reads the
  /// geometry `LayoutBuilder` cached this build (`_gridLeftPx` etc.) to
  /// place a shell arcing from the cannon's actual muzzle to the tapped
  /// cell's center, and drives `_previewAimCell` for exactly as long as
  /// it's in flight.
  void _firePreviewShot(int r, int c) {
    // One shot per reload, same as battle — see `_previewReloadCtrl`. A
    // tap on a still-reloading gun gets the same refusal blip the battle
    // grid gives, rather than silently restarting the shell in mid-air.
    if (_previewReloadCtrl.value < 1) {
      SoundService.instance.denied();
      return;
    }
    final cellSize = _gridSidePx / kBoardSize;
    final to = Offset(
      _gridLeftPx + (c + 0.5) * cellSize,
      _gridTopPx + (r + 0.5) * cellSize,
    );
    final muzzle = Offset(
      _cannonCenterXPx,
      _cannonCenterYPx - _cannonRenderSizePx * _cannonMuzzleFrac,
    );
    final controller = context.read<GameController>();
    final isLocal = controller.mode == GameMode.local;
    final profile = context.read<ProfileStore>();
    final loadout = isLocal
        ? controller.localLoadouts[_seat]
        : Loadout.of(profile);

    SoundService.instance.cannonFire(cannonSkinId: loadout.cannonSkinId);
    _previewFireCtrl.add(null);
    // BUGFIX (pointy shells "spinning weird" on a close-range tap): see
    // the matching note on `battle_screen.dart`'s `_launchBall`. This used
    // to be a FIXED `cellSize * 2.4` regardless of how close the tapped
    // cell actually was, so tapping a cell right next to the cannon — a
    // very common thing to do on this single-board deploy screen — gave
    // the shell the same tall arc as a shot clear across the grid. That
    // dwarfs a close tap's real horizontal travel with a disproportionate
    // vertical one, and right at the arc's apex (where the directional
    // shell's heading, `angleAt` below, is derived from both) the shell is
    // barely moving in either direction — so its nose whips through a
    // huge angle in a single frame instead of easing through the turn.
    // Scaling the peak to the tap's actual distance keeps it proportionate
    // — a close tap gets a small hop, a far one still gets the old 2.4-cell
    // loop.
    final dx = to.dx - muzzle.dx;
    final dy = to.dy - muzzle.dy;
    final dist = math.sqrt(dx * dx + dy * dy) / cellSize; // in cells
    setState(() {
      _previewAimCell = [r, c];
      _previewShotFrom = muzzle;
      _previewShotTo = to;
      _previewShotCell = cellSize;
      _previewShotArc = cellSize * dist.clamp(1.0, 2.4);
    });
    _previewShotCtrl.forward(from: 0).whenComplete(() {
      if (mounted) {
        SoundService.instance.miss(
          themeId: loadout.themeId,
          cannonSkinId: loadout.cannonSkinId,
        );
        setState(() {
          _previewAimCell = null;
          _previewEvents.add(CombatEventLike(r, c, ShotResult.miss));
        });
      }
    });
    // The gun is empty from the muzzle flash onward and reloads on its
    // own clock, which outlasts the shell's flight — so the reload ring
    // keeps running after the shell has landed, exactly as in battle.
    _previewReloadCtrl.duration = _cannonReload;
    _previewReloadCtrl.forward(from: 0).whenComplete(() {
      if (mounted && !_previewReadyCtrl.isClosed) {
        SoundService.instance.cannonReady(cannonSkinId: loadout.cannonSkinId);
        _previewReadyCtrl.add(null);
      }
    });
  }

  /// The preview shell's in-flight layer: arcing from the cannon's muzzle to
  /// the tapped cell's center, matching the equipped cannon's bespoke shell
  /// artwork and directional trajectory.
  Widget _previewShotLayer(CannonSkin cannonSkin) {
    final shellFamily = FleetFamilies.byKey(cannonSkin.familyKey);
    final legacyShellId = shellFamily == null ? cannonSkin.id : null;
    final isDirectional = shellFamily != null
        ? familyShellIsDirectional(shellFamily.id)
        : legacyShellIsDirectional(legacyShellId!);

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _previewShotCtrl,
          builder: (context, _) {
            final t = _previewShotCtrl.value;

            Offset posAt(double tt) {
              final cl = tt.clamp(0.0, 1.0);
              final base = Offset.lerp(_previewShotFrom, _previewShotTo, cl)!;
              final arc = math.sin(cl * math.pi) * _previewShotArc;
              return base - Offset(0, arc);
            }

            double angleAt(double tt) {
              final cl = tt.clamp(0.0, 1.0);
              final vx = _previewShotTo.dx - _previewShotFrom.dx;
              final arcRate =
                  math.pi * _previewShotArc * math.cos(cl * math.pi);
              final vy = (_previewShotTo.dy - _previewShotFrom.dy) - arcRate;
              if (vx == 0 && vy == 0) return 0;
              return math.atan2(vx, -vy);
            }

            double diamAt(double tt) =>
                _previewShotCell * (2.6 - 1.6 * tt.clamp(0.0, 1.0));

            double impactFadeAt(double tt) {
              const fadeStart = 0.92;
              if (tt <= fadeStart) return 1.0;
              return (1 - (tt - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
            }

            final pos = posAt(t);
            final d = diamAt(t);
            final fade = impactFadeAt(t);
            final angle = isDirectional ? angleAt(t) : t * math.pi * 6;

            Widget ghost(double dt, double opacity, double scale) {
              final tt = t - dt;
              if (tt <= 0) return const SizedBox.shrink();
              final gp = posAt(tt);
              final gd = diamAt(tt) * scale;
              return Positioned(
                left: gp.dx - gd / 2,
                top: gp.dy - gd / 2,
                child: Opacity(
                  opacity: opacity * impactFadeAt(tt),
                  child: Transform.rotate(
                    angle: isDirectional ? angleAt(tt) : 0.0,
                    child: _previewCannonball(
                      gd,
                      family: shellFamily,
                      legacyId: legacyShellId,
                    ),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Faint motion-trail ghosts behind the projectile.
                ghost(0.11, 0.14, 0.72),
                ghost(0.055, 0.26, 0.84),
                Positioned(
                  left: pos.dx - d / 2,
                  top: pos.dy - d / 2,
                  child: Opacity(
                    // KEY (test hook): the one in-flight shell — every
                    // branch of `_previewCannonball` lays out to exactly
                    // this box, whatever art it draws inside it, so the
                    // widget test can measure the ball's on-screen size
                    // without reaching into the painter classes.
                    key: const ValueKey('previewShell'),
                    opacity: fade,
                    child: Transform.rotate(
                      angle: angle,
                      child: _previewCannonball(
                        d,
                        family: shellFamily,
                        legacyId: legacyShellId,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The projectile in flight — draws family artwork, legacy shell artwork,
  /// or fallback styled iron ball.
  Widget _previewCannonball(double d, {FleetFamily? family, String? legacyId}) {
    if (family != null) {
      final h = d / kShellBoxAspect;
      return SizedBox(
        width: d,
        height: d,
        child: OverflowBox(
          maxWidth: d,
          maxHeight: h,
          child: CustomPaint(
            size: Size(d, h),
            painter: _FamilyShellPainter(family),
          ),
        ),
      );
    }
    if (legacyId != null) {
      final h = d / kShellBoxAspect;
      return SizedBox(
        width: d,
        height: d,
        child: OverflowBox(
          maxWidth: d,
          maxHeight: h,
          child: CustomPaint(
            size: Size(d, h),
            painter: _LegacyCannonballPainter(legacyId),
          ),
        ),
      );
    }
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          stops: [0.0, 0.45, 1.0],
          colors: [Color(0xFFC3CBD3), Color(0xFF6E7883), Color(0xFF1D232A)],
        ),
        border: Border.all(
          color: const Color(0xFF12161B),
          width: math.max(1.0, d * 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: d * 0.18,
            offset: Offset(0, d * 0.1),
          ),
        ],
      ),
    );
  }

  /// Deals out a fresh random layout. Rather than swapping the whole
  /// fleet in one instant `setState` (the old behavior — every ship just
  /// cut to its new spot), this staggers the ships in one at a time so
  /// each one visibly SLIDES to its new cell (the actual motion comes for
  /// free from `BattleGrid`'s `AnimatedPositioned`, keyed per ship —
  /// see `_shipWidgets`) with a placement "thunk" timed to its landing,
  /// giving the RANDOM button a satisfying "shuffle and deal" feel
  /// instead of an abrupt pop.
  void _randomize() {
    if (_randomizing) return;
    unawaited(_runRandomize());
  }

  Future<void> _runRandomize() async {
    // BUGFIX (RANDOM did nothing on a full board / left already-placed
    // ships untouched on a partial one): this used to only build a fresh
    // random layout when the board started completely empty. Otherwise it
    // copied every already-placed ship's row/col/orientation STRAIGHT into
    // `target` unchanged and only rolled positions for the still-unplaced
    // ships — so a fully-deployed fleet had nothing left to randomize
    // (`target` was byte-for-byte identical to the current board, so the
    // "did it move" check below skipped every ship) and a partially-placed
    // one only ever reshuffled the ships still sitting in the dock. Always
    // dealing a brand new `Board.random()` layout — regardless of what's
    // already on the board — means every ship, placed or not, gets a new
    // spot; the "did it move" check further down still only animates the
    // ones that actually landed somewhere different.
    //
    // BUGFIX (ships popped in at full size, overlapping the dock tray):
    // `_entranceDeal` is what tells `BattleGrid` (via `animateEntrance`)
    // to play `_ShipEntrance`'s fade + grow-from-nothing pop the moment a
    // ship mounts at its off-grid dock-measured starting spot — see the
    // doc comment on `_entranceDeal`. Nothing ever actually SET it to
    // true, though, so `BattleGrid.animateEntrance` was always false and
    // `_ShipEntrance` always took its `else` branch (`_ctrl.value = 1.0`,
    // "same instant appearance drag-and-drop placement has always had").
    // That meant a freshly-dealt ship was full-size and fully-opaque on
    // the very first frame it appeared — right on top of its tiny dock
    // icon, up under the header — and only THEN started sliding via
    // `AnimatedPositioned`, instead of visibly growing out of its preview
    // slot as it flew to its dealt cell. Captured before `target` is dealt
    // (dealing doesn't touch `_board`, but reads better ahead of the
    // mutation below) and only for a board that started genuinely empty —
    // matching `_entranceDeal`'s own contract — so a reshuffle of an
    // already-deployed fleet still repositions with a plain slide, no pop.
    final startedEmpty = _board.ships.isEmpty;
    final target = Board.random();
    SoundService.instance.whir();
    setState(() {
      _randomizing = true;
      _selected = null;
      _previewShip = null;
      if (startedEmpty) _entranceDeal = true;
    });
    // Ships still sitting in the dock get a starting spot measured from
    // their OWN dock icon's actual on-screen position, so each one
    // visibly enters from right where its preview slot sits — not an
    // approximate evenly-spread guess. This adds the REAL ship straight
    // into `_board.ships` at that off-grid spot; the loop below then
    // eases it down into its dealt cell using `BattleGrid`'s own
    // row/col-driven `AnimatedPositioned` (see `_animatedShipBox`) — the
    // exact same position tween an ordinary reposition already uses.
    //
    // The dock icon's position is still measured with
    // `RenderBox.localToGlobal`/`globalToLocal` (through `_dockKeys` and
    // `_gridKey`), same as the old ghost system — but the result is only
    // ever used ONCE, to pick this ship's *starting row/col*, using the
    // exact same center = col*cell + w/2 relationship `_animatedShipBox`
    // itself uses to place the real widget (solved in reverse here). That
    // means there is only ever the one real, row/col-positioned widget
    // for this ship, from the very first frame it's drawn — no separate
    // pixel-measured ghost overlay computing a second, competing position
    // that could ever drift out of sync with it and need a crossfade to
    // mask the seam.
    final unplaced = target.ships
        .where((s) => _board.shipOfKind(s.spec.kind) == null)
        .toList();
    if (unplaced.isNotEmpty) {
      final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
      final cell = gridBox == null ? null : gridBox.size.width / kBoardSize;
      setState(() {
        for (final ship in unplaced) {
          int startRow = -3;
          int startCol = 0;
          final span = kBoardSize - ship.spec.size;
          if (gridBox != null && cell != null) {
            final dockBox =
                _dockKeys[ship.spec.kind]?.currentContext?.findRenderObject()
                    as RenderBox?;
            if (dockBox != null) {
              final dockCenterGlobal = dockBox.localToGlobal(
                dockBox.size.center(Offset.zero),
              );
              final localCenter = gridBox.globalToLocal(dockCenterGlobal);
              startRow = ((localCenter.dy - cell / 2) / cell).round();
              startCol = ((localCenter.dx - (ship.spec.size * cell) / 2) / cell)
                  .round();
              // The TRUE dock icon center, kept at full pixel precision
              // (unlike `startRow`/`startCol` above, which round it off to
              // the nearest whole cell purely so the board model has
              // somewhere valid to put this ship). `BattleGrid` uses this
              // to render the ship's very first frame exactly on the
              // icon and ease away the small rounding gap — see
              // `pullInFrom` / `_ShipPullIn`.
              _pullInFrom[ship.spec.kind] = localCenter;
              // Same dock-vs-board size ratio the old ghost overlay used
              // to pick its `startScale` — a ship starts at roughly its
              // own dock icon's footprint and grows to full size as it
              // eases onto the board (see `_ShipPullIn`).
              const dockUnit = 11.0;
              final dockW = dockUnit * ship.spec.size + 14;
              final boardW = ship.spec.size * cell - 2;
              _pullInScales[ship.spec.kind] = boardW > 0
                  ? (dockW / boardW).clamp(0.35, 0.75)
                  : 1.0;
            } else {
              // Dock icon not laid out yet (shouldn't normally happen) —
              // fall back to a rough spread by dock order so ships still
              // enter from distinct, plausible-looking columns.
              final slot = kFleet.indexWhere((s) => s.kind == ship.spec.kind);
              startCol = kFleet.length > 1
                  ? ((slot.clamp(0, kFleet.length - 1) * span) /
                            (kFleet.length - 1))
                        .round()
                  : 0;
            }
          }
          if (startCol < 0) startCol = 0;
          if (startCol > span) startCol = span;
          _board.ships.add(
            PlacedShip(
              spec: ship.spec,
              row: startRow,
              col: startCol,
              horizontal: true,
            ),
          );
        }
      });
      // One frame so the off-grid start position actually paints before
      // the loop below starts tweening away from it — otherwise
      // `AnimatedPositioned` has no "from" frame to ease from and the
      // ship would just appear already at its dealt cell instead of
      // visibly sliding in from above the dock.
      await Future.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }
    for (final ship in target.ships) {
      if (!mounted) return;
      final existing = _board.shipOfKind(ship.spec.kind);
      if (existing != null &&
          existing.row == ship.row &&
          existing.col == ship.col &&
          existing.horizontal == ship.horizontal) {
        continue;
      }
      setState(() {
        // BUGFIX (ship visibly nudges right before it settles): this used
        // to `removeWhere` + `add`, which drops the ship out of its
        // current slot in `_board.ships` and re-appends it at the END of
        // the list. `_shipWidgets` renders ships in list order, so that
        // silently reordered this ship's paint position — behind ships
        // it used to be in front of, or vice versa — for the rest of the
        // shuffle. Because each ship's hit-box is a square sized to its
        // OWN long axis (see `_animatedShipBox`), it can briefly overlap
        // a neighbour's box mid-slide even when their hulls don't touch,
        // and a z-order flip during that overlap reads as a little
        // shift/pop right as the ship arrives. Replacing the entry AT ITS
        // EXISTING INDEX (falling back to `add` only if it's genuinely
        // new — shouldn't happen here, since `existing != null` failing
        // is the only other way in) keeps every ship's paint order
        // stable through the whole reshuffle, so only its position
        // actually animates.
        final idx = _board.ships.indexWhere(
          (s) => s.spec.kind == ship.spec.kind,
        );
        if (idx == -1) {
          _board.ships.add(ship);
        } else {
          _board.ships[idx] = ship;
        }
      });
      SoundService.instance.place(shipSkinId: _shipSkinId);
      await Future.delayed(const Duration(milliseconds: 90));
    }
    if (mounted) setState(() => _randomizing = false);
  }

  /// Leaves the placement screen via the back arrow or [_ExitButton].
  ///
  /// BUGFIX: both used to be a bare `Navigator.pop(context)`, which left a
  /// LAN/online socket open and the opponent never told the player backed
  /// out — so the opponent's own screen (waiting on `_waitForPeerBoard`, or
  /// already in the lobby) just hung. `network.stop()` closes the
  /// connection so the peer sees a disconnect immediately.
  void _exitPlacement(bool isLan, GameController controller) {
    if (isLan) controller.network.stop();
    Navigator.pop(context);
  }

  Future<void> _save() async {
    if (!_allPlaced) return;
    final controller = context.read<GameController>();
    SoundService.instance.victory();

    switch (controller.mode) {
      case GameMode.vsAI:
        controller.beginBattle();
        _goBattle();
        break;
      case GameMode.local:
        if (!widget.isPlayer2) {
          setState(() => _showHandoff = true);
        } else {
          controller.beginBattle(enemyBoard: controller.boards[1]);
          _goBattle();
        }
        break;
      case GameMode.hotspot:
      case GameMode.online:
      case GameMode.vsAiLan:
        // Remember our fleet is owed to the opponent before sending it —
        // if they drop between now and battle, a rejoin needs us to send
        // it again (see `_onNetForPeer`).
        _sentBoard = true;
        controller.network.sendBoard(_board);
        _waitForPeerBoard(controller);
        break;
    }
  }

  /// Starts the match from the peer's fleet. Shared by both paths below so
  /// "their board was already here" and "their board arrived while we
  /// waited" behave identically.
  void _beginWithPeerBoard(
    GameController controller,
    Map<String, dynamic> msg,
  ) {
    final enemyBoard = Board.fromJson(
      Map<String, dynamic>.from(msg['b'] as Map),
    );
    controller.attachNetwork();
    controller.beginBattle(enemyBoard: enemyBoard);
    _goBattle();
  }

  void _waitForPeerBoard(GameController controller) {
    // BUGFIX (hotspot desync — the player who saved SECOND hung on
    // "WAITING FOR OPPONENT…" while the other was already in battle):
    // `network.messages` is a broadcast stream, so the peer's board is
    // dropped if it lands before this screen subscribes — which is exactly
    // what happens whenever the peer hits SAVE first. NetworkService now
    // retains it, so check for an already-delivered board BEFORE
    // subscribing (and before putting up a dialog we'd only have to tear
    // straight back down).
    final alreadyHere = controller.network.takePeerBoard();
    if (alreadyHere != null) {
      _beginWithPeerBoard(controller, alreadyHere);
      return;
    }

    setState(() => _waitingForPeer = true);
    _peerBoardSub = controller.network.messages.listen((msg) {
      if (msg['type'] == 'board') {
        _peerBoardSub?.cancel();
        _peerBoardSub = null;
        // Consume the retained copy so it can't be picked up again.
        controller.network.takePeerBoard();
        if (mounted) {
          setState(() => _waitingForPeer = false);
          Navigator.of(context, rootNavigator: true).pop();
        }
        _beginWithPeerBoard(controller, msg);
      } else if (msg['type'] == 'board_cancel') {
        _peerBoardSub?.cancel();
        _peerBoardSub = null;
        if (!mounted) return;
        setState(() => _waitingForPeer = false);
        Navigator.of(context, rootNavigator: true).pop();
        AppNotification.show(
          context,
          'Your opponent went back to editing their fleet.',
          type: AppNoticeType.info,
        );
      }
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          // Only reached via system BACK — an explicit pop from inside
          // this method (peer's board/board_cancel arriving, or the
          // CANCEL button below) already goes through `didPop: true` and
          // is a no-op here. See the BUGFIX note above `_waitForPeerBoard`
          // this replaces: BACK used to fall through to the still-live
          // `sub` and pop the whole PlacementScreen instead.
          if (didPop) return;
          _cancelWaitingForPeer(controller, popDialog: true);
        },
        child: AlertDialog(
          backgroundColor: AppColors.navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.outline, width: 3),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.cream),
              const SizedBox(height: 16),
              Text('WAITING FOR OPPONENT…', style: AppText.label(size: 11)),
              const SizedBox(height: 18),
              NeonButton(
                label: 'CANCEL',
                icon: Icons.close,
                color: AppColors.danger,
                compact: true,
                onPressed: () =>
                    _cancelWaitingForPeer(controller, popDialog: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Backs out of the "waiting for opponent" dialog — CANCEL button or
  /// system BACK — so the player can return to editing their fleet. Tells
  /// the peer via `board_cancel` so THEIR wait (if they saved first) clears
  /// too; if they already moved on to battle this arrives too late to
  /// matter and they simply play on, which is the accepted edge case for
  /// this feature (see the plan's note on `sendBoard` being fire-and-forget).
  ///
  /// [keepBoard] is set when the wait is being torn down because the PEER
  /// DROPPED rather than because the player chose to: our board is still
  /// owed to them (it will be re-sent when they return, see
  /// `_onNetForPeer`), so [_sentBoard] must survive, and `board_cancel` is
  /// a no-op on a dead socket.
  void _cancelWaitingForPeer(
    GameController controller, {
    required bool popDialog,
    bool keepBoard = false,
  }) {
    _peerBoardSub?.cancel();
    _peerBoardSub = null;
    if (!keepBoard) {
      controller.network.sendBoardCancel();
      _sentBoard = false;
    }
    if (popDialog && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (mounted) setState(() => _waitingForPeer = false);
  }

  void _goBattle() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const BattleScreen()));
  }

  /// Page transition used to enter Player 2's (already 180°-rotated —
  /// see `build()`) placement screen: a short perspective "turn" — starting
  /// edge-on and swinging down to face-on with a fade — instead of the
  /// plain slide/fade a default MaterialPageRoute would use. Purely a
  /// paint-time transition (`Transform` around the incoming page), so it
  /// doesn't affect hit-testing at all; the destination screen only
  /// becomes interactive once the transition has settled, same as any
  /// other page transition.
  Route<void> _flipToPlayer2Route() {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 620),
      reverseTransitionDuration: const Duration(milliseconds: 620),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const PlacementScreen(isPlayer2: true),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, child) {
            final t = curved.value;
            final angle = (1 - t) * (math.pi / 2);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateY(angle),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  /// The real, on-screen size of one grid cell — read straight from the
  /// grid's own RenderBox (same technique `onMove`/`onAcceptWithDetails`
  /// already use) so the dock icons and the drag "feedback" ghost can be
  /// sized to match the actual board instead of a guessed constant.
  /// Previously the dock icons and the dragged ship were both fixed
  /// pixel sizes (68 / 110) that had no relationship to the grid's real
  /// cell size or to how many cells a ship actually occupies — that
  /// mismatch is why a ship being dragged looked mis-sized/misaligned
  /// against the green highlight cells underneath it.
  /// Before the grid has been laid out for the first time (very first
  /// build) the RenderBox isn't available yet, so this falls back to an
  /// estimate from the screen width, which is close enough for that one
  /// frame and self-corrects on the next rebuild.
  /// [dropOrigin] against this screen's live grid.
  ///
  /// BUGFIX (Player 2's flipped board: the drop highlight and the drag
  /// ghost landed on different cells, off by the ship's own length — so
  /// the destroyer looked nearly right and the carrier looked broken).
  /// See [dropOrigin] for why; note in particular that `globalToLocal`
  /// handles the rotation correctly and was never the problem, which is
  /// what made this one hard to spot.
  Offset _dropOrigin(
    RenderBox gridBox,
    Offset pointerGlobal,
    ShipSpec spec,
    bool horizontal,
    double cell,
  ) => dropOrigin(
    pointerLocal: gridBox.globalToLocal(pointerGlobal),
    flipped: widget.isPlayer2,
    shipCells: spec.size,
    horizontal: horizontal,
    cell: cell,
  );

  double _cellSize(BuildContext context) {
    final gridBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridBox != null && gridBox.hasSize) {
      return gridBox.size.width / kBoardSize;
    }
    return MediaQuery.of(context).size.width / kBoardSize;
  }

  /// Pass-and-play gear picker for THIS seat.
  ///
  /// Presented as a centred dialog rather than a bottom sheet on purpose:
  /// Player 2's whole placement screen is drawn inside a 180° `RotatedBox`,
  /// but a sheet or dialog lives in the app's overlay, above that rotation
  /// — so it has to be turned right way up for them here, and a centred
  /// panel reads correctly either way up while a sheet would slide in from
  /// what is, from Player 2's seat, the top of the screen.
  Future<void> _openGear(
    GameController controller, {
    required bool isLocal,
    required bool announceToOpponent,
  }) async {
    SoundService.instance.click();
    final profile = context.read<ProfileStore>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => RotatedBox(
        quarterTurns: widget.isPlayer2 ? 2 : 0,
        child: _GearDialog(
          profile: profile,
          seatLabel: isLocal
              ? (widget.isPlayer2 ? 'PLAYER 2' : 'PLAYER 1')
              : 'YOUR',
          current: isLocal
              ? controller.localLoadouts[_seat]
              : Loadout.of(profile),
          onChanged: (lo) => isLocal
              ? controller.setLocalLoadout(_seat, lo)
              : _equipFromGearDialog(
                  controller,
                  lo,
                  announceToOpponent: announceToOpponent,
                ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Applies a gear change made on a vsAI or hotspot/online deployment
  /// screen — anywhere a single device owner (not a pass-and-play seat)
  /// is picking their own gear.
  ///
  /// Always written to the PROFILE, because outside pass-and-play "your
  /// loadout" is simply what you have equipped — there is no second seat
  /// on this device to keep it separate from, and a change made here
  /// should still be equipped next time you play. Only announced to an
  /// opponent when [announceToOpponent] is set (hotspot/online): they are
  /// drawing your fleet from the gear you sent in the handshake, so
  /// without this they would keep rendering the hull you arrived in for
  /// the whole match. There is no opponent device to tell against the AI,
  /// so that step is skipped there.
  void _equipFromGearDialog(
    GameController controller,
    Loadout lo, {
    required bool announceToOpponent,
  }) {
    final profile = context.read<ProfileStore>();
    profile.equipShipSkin(Catalog.shipById(lo.shipSkinId));
    profile.equipCannonSkin(Catalog.cannonById(lo.cannonSkinId));
    profile.equipGameplayTheme(Catalog.gameplayThemeById(lo.themeId));
    if (announceToOpponent) {
      controller.network.announceLoadout(
        shipSkinId: lo.shipSkinId,
        cannonSkinId: lo.cannonSkinId,
        themeId: lo.themeId,
        shipChosen: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // WATCHED, not read: picking a battlefield in the GEAR dialog writes
    // through the controller for pass-and-play, and this screen has to
    // repaint underneath the still-open dialog for the change to look
    // live rather than appearing only once the dialog is dismissed.
    final controller = context.watch<GameController>();
    // Everything below keyed on `isLan` — fleet colour by network role,
    // the GEAR button, exiting via `network.stop()` — applies just the
    // same whether the opponent is a real device or the hidden AI a
    // vsAiLan match runs over a `LoopbackLink`; only the MATCH CHAT
    // button (below) needs an actual human on the other end and checks
    // `controller.hasRemotePeer` directly instead.
    final isLan = controller.usesMatchProtocol;
    final isLocal = controller.mode == GameMode.local;
    final isVsAI = controller.mode == GameMode.vsAI;

    // Which gear this captain is deploying with. In pass-and-play the two
    // seats have separate loadouts (see `GameController.localLoadouts`)
    // that each player sets from the GEAR button below; everywhere else
    // it's simply the device owner's own.
    final profile = context.watch<ProfileStore>();
    final loadout = isLocal
        ? controller.localLoadouts[_seat]
        : Loadout.of(profile);

    final skin = loadout.shipSkin;
    // The battlefield this captain is deploying onto.
    final theme = loadout.theme;
    final boardFamily = FleetFamilies.byKey(theme.familyKey);
    final playerLabel = isLocal
        ? (widget.isPlayer2 ? 'PLAYER 2' : 'PLAYER 1')
        : profile.playerName.toUpperCase();
    final cellSize = _cellSize(context);

    if (_showHandoff) {
      return HandoffScreen(
        title: 'Pass the screen\nto your friend\nand don\'t look :-)',
        subtitle: 'Player 2 — deploy your fleet in secret!',
        buttonLabel: 'OK',
        onReady: () {
          // REDESIGN (Player 2 perspective): once the device is handed
          // over, the incoming Player 2 placement screen (already
          // rendered 180°-rotated via the RotatedBox above) flips into
          // view with a short perspective turn instead of just popping in
          // — "Player 1 placement → handoff screen → rotate/flip
          // animation → Player 2 placement" per the redesign brief.
          Navigator.of(context).pushReplacement(_flipToPlayer2Route());
        },
      );
    }

    return Scaffold(
      // ROOT-CAUSE FIX (deck shrinking/changing size the instant the chat
      // keyboard appears): `MediaQuery.viewInsets` is global to the app,
      // so ANY Scaffold still mounted underneath the chat's overlay
      // dialog — including this one — sees the keyboard's height the
      // moment it opens. Scaffold's default `resizeToAvoidBottomInset:
      // true` then shrinks THIS body to make room for it, even though the
      // keyboard is only needed by the chat panel floating on top, not by
      // anything on this screen. Since the board's cell size is derived
      // from the laid-out grid's own size (see `_cellSize` above), a
      // shrunken body meant a visibly shrunken deck for as long as the
      // keyboard was up. The chat panel already insets itself for the
      // keyboard independently (see `bottomInset` in `_ChatPanel` in
      // match_chat.dart), so this screen has no reason to react to it too.
      resizeToAvoidBottomInset: false,
      // Animated rather than swapped: picking a new battlefield in the
      // GEAR dialog changes this while the dialog is still open, and a
      // hard cut behind a modal reads as a glitch. 320ms matches the
      // grid's own cross-fade below so the deck and the water land
      // together.
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            color: theme.deck,
            child: SafeArea(
              // REDESIGN (Player 2 rotated perspective): rather than rotating
              // individual pieces, the ENTIRE placement interface — header,
              // dock tray, grid, hint — is wrapped in one RotatedBox for
              // Player 2, exactly the same technique battle_screen.dart
              // already uses to flip P2's half of the battle screen 180° so
              // the players can sit across from each other. `RotatedBox` (not
              // a cosmetic `Transform`) is what makes this safe: it applies a
              // REAL layout+paint+hit-test transform, so every existing tap/
              // drag coordinate calculation in this screen and in BattleGrid
              // (which all read raw local/global offsets via
              // `RenderBox.globalToLocal`) keeps working completely unchanged
              // — the rotation is transparently accounted for by the render
              // tree, not something the interaction code needs to know about.
              // `quarterTurns: 0` for Player 1 is a no-op passthrough.
              child: RotatedBox(
                quarterTurns: widget.isPlayer2 ? 2 : 0,
                child: Column(
                  children: [
                    // ---------- Navy header ----------
                    Container(
                      width: double.infinity,
                      color: AppColors.navy,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  SoundService.instance.click();
                                  _exitPlacement(isLan, controller);
                                },
                                child: const Icon(
                                  Icons.arrow_back,
                                  color: AppColors.cream,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Deploy your ships',
                                  style: AppText.title(size: 24),
                                ),
                              ),
                              // Deployment is the last moment before the guns
                              // are live, and it's where you can see your
                              // fleet laid out — so it's the natural place to
                              // change what you're taking in, whoever you're
                              // playing: pass-and-play, vs the AI, or a
                              // hotspot/online match. In pass-and-play it
                              // writes to this seat's own loadout; everywhere
                              // else it re-equips your profile, additionally
                              // telling the opponent when there's a live one
                              // to tell (see `_equipFromGearDialog`).
                              if (isLocal || isVsAI || isLan) ...[
                                _GearButton(
                                  color: loadout.shipSkin.hull,
                                  onTap: () => _openGear(
                                    controller,
                                    isLocal: isLocal,
                                    announceToOpponent: isLan,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (controller.hasRemotePeer) ...[
                                const MatchChatButton(size: 36),
                                const SizedBox(width: 8),
                              ],
                              _ExitButton(
                                onTap: () => _exitPlacement(isLan, controller),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$playerLabel — drag to move and tap to rotate, or try random placement',
                            textAlign: TextAlign.center,
                            style: AppText.body(
                              size: 12,
                              color: AppColors.cream.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              NeonButton(
                                label: 'RANDOM',
                                icon: Icons.shuffle,
                                color: AppColors.blue,
                                compact: true,
                                onPressed: _randomizing ? null : _randomize,
                              ),
                              const SizedBox(width: 12),
                              NeonButton(
                                label: _allPlaced
                                    ? 'SAVE'
                                    : 'SAVE  ${_board.ships.length}/5',
                                icon: Icons.bolt,
                                color: _allPlaced
                                    ? AppColors.seafoam
                                    : AppColors.inkSoft,
                                onPressed:
                                    (_allPlaced &&
                                        !_randomizing &&
                                        !_waitingForPeer)
                                    ? _save
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ---------- Dock tray (draggable ship icons) ----------
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      height: _dockH,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.deckAccent,
                        border: const Border(
                          bottom: BorderSide(
                            color: AppColors.outline,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final spec in kFleet)
                            _DockShip(
                              key: _dockKeys[spec.kind],
                              spec: spec,
                              skin: skin,
                              cell: cellSize,
                              placed: _board.shipOfKind(spec.kind) != null,
                              selected: _selected == spec.kind,
                              rotated: widget.isPlayer2,
                              onTap: () {
                                SoundService.instance.click();
                                setState(
                                  () => _selected = _selected == spec.kind
                                      ? null
                                      : spec.kind,
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                    // ---------- Grid (drop target) + cannon overhang ----------
                    // The grid now fills the whole Expanded region (battle does
                    // the same per-half) instead of the old 16px-padded, 440px-
                    // capped box. The cannon is NOT a separate 92px strip that
                    // steals height from the grid — it is overlaid so only its
                    // pointy muzzle peeks onto the deck, exactly like the battle
                    // screen's parked cannon. That fixes two things at once:
                    // the grid is as large as in battle, and every family's
                    // barrel tip is visible on the deck even when parked at the
                    // back (stubby guns used to hide completely behind the old
                    // bay's deck strip).
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final h = constraints.maxHeight;
                          final gridSide = math.min(w, h);
                          final gridLeft = (w - gridSide) / 2;
                          final gridTop = (h - gridSide) / 2;
                          final gridBottom = gridTop + gridSide;
                          final cannonSize = gridSide * 0.24;
                          final scale = CannonWidget.gameplaySizeScaleOf(
                            loadout.cannonSkin,
                          );
                          final renderSize = cannonSize * scale;
                          final muzzleFrac = CannonWidget.muzzleFractionOf(
                            loadout.cannonSkin,
                          );
                          final cannonCenterY =
                              gridBottom + renderSize * (muzzleFrac - 0.07);
                          // Cache this build's geometry for the cannon
                          // preview (see `_firePreviewShot`) — plain field
                          // writes, not `setState`: nothing needs to repaint
                          // over this, it's just bookkeeping for the NEXT
                          // gesture that reads it.
                          _gridLeftPx = gridLeft;
                          _gridTopPx = gridTop;
                          _gridSidePx = gridSide;
                          _cannonCenterXPx = w / 2;
                          _cannonCenterYPx = cannonCenterY;
                          _cannonRenderSizePx = renderSize;
                          _cannonMuzzleFrac = muzzleFrac;
                          _cannonReload = Duration(
                            milliseconds:
                                (kCooldownSeconds *
                                        1000 *
                                        loadout.cannonSkin.cooldownFactor)
                                    .round(),
                          );
                          return Stack(
                            key: _stackKey,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                left: gridLeft,
                                top: gridTop,
                                width: gridSide,
                                height: gridSide,
                                child: DragTarget<({ShipKind kind, bool horizontal})>(
                                  onWillAcceptWithDetails: (_) => true,
                                  onMove: (details) {
                                    final spec = kFleet.firstWhere(
                                      (s) => s.kind == details.data.kind,
                                    );
                                    final gridBox =
                                        _gridKey.currentContext
                                                ?.findRenderObject()
                                            as RenderBox?;
                                    if (gridBox == null) return;
                                    final cell =
                                        gridBox.size.width / kBoardSize;
                                    final local = _dropOrigin(
                                      gridBox,
                                      details.offset,
                                      spec,
                                      details.data.horizontal,
                                      cell,
                                    );
                                    var c = (local.dx / cell).floor();
                                    var r = (local.dy / cell).floor();
                                    final hh = details.data.horizontal;
                                    if (hh && c + spec.size > kBoardSize) {
                                      c = kBoardSize - spec.size;
                                    }
                                    if (!hh && r + spec.size > kBoardSize) {
                                      r = kBoardSize - spec.size;
                                    }
                                    r = r.clamp(0, kBoardSize - 1);
                                    c = c.clamp(0, kBoardSize - 1);
                                    setState(() {
                                      _previewShip = PlacedShip(
                                        spec: spec,
                                        row: r,
                                        col: c,
                                        horizontal: hh,
                                      );
                                      _previewValid = _board.canPlace(
                                        spec,
                                        r,
                                        c,
                                        hh,
                                      );
                                    });
                                  },
                                  onLeave: (_) =>
                                      setState(() => _previewShip = null),
                                  onAcceptWithDetails: (details) {
                                    final spec = kFleet.firstWhere(
                                      (s) => s.kind == details.data.kind,
                                    );
                                    final gridBox =
                                        _gridKey.currentContext
                                                ?.findRenderObject()
                                            as RenderBox?;
                                    if (gridBox == null) return;
                                    final cell =
                                        gridBox.size.width / kBoardSize;
                                    final local = _dropOrigin(
                                      gridBox,
                                      details.offset,
                                      spec,
                                      details.data.horizontal,
                                      cell,
                                    );
                                    var c = (local.dx / cell).floor();
                                    var r = (local.dy / cell).floor();
                                    final hh = details.data.horizontal;
                                    if (hh && c + spec.size > kBoardSize) {
                                      c = kBoardSize - spec.size;
                                    }
                                    if (!hh && r + spec.size > kBoardSize) {
                                      r = kBoardSize - spec.size;
                                    }
                                    r = r.clamp(0, kBoardSize - 1);
                                    c = c.clamp(0, kBoardSize - 1);
                                    if (_board.canPlace(spec, r, c, hh)) {
                                      _board.place(spec, r, c, hh);
                                      SoundService.instance.place(
                                        shipSkinId: skin.id,
                                      );
                                      setState(() {
                                        _selected = null;
                                        _previewShip = null;
                                      });
                                    } else {
                                      SoundService.instance.denied();
                                      setState(() => _previewShip = null);
                                    }
                                  },
                                  builder: (context, candidates, rejected) {
                                    return Container(
                                      key: _gridKey,
                                      // Cross-faded on the theme id AND the hull skin
                                      // id so switching EITHER battlefield OR hull in
                                      // the GEAR dialog dissolves from one board to
                                      // the next — the grid paints the placed ships
                                      // itself, so a hull-only change used to just
                                      // pop the new ships in mid-frame. A family
                                      // board/hull is real artwork rather than a
                                      // palette, so there is nothing to tween between
                                      // — two boards briefly stacked and faded is the
                                      // only honest way to make either change smooth.
                                      //
                                      // The key stays on the Container OUTSIDE this,
                                      // so the drop maths keeps measuring one stable
                                      // box while the switch is in flight.
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        child: BattleGrid(
                                          key: ValueKey(
                                            '${theme.id}::${skin.id}',
                                          ),
                                          shots: List.generate(
                                            kBoardSize,
                                            (_) => List.filled(kBoardSize, 0),
                                          ),
                                          ships: _board.ships,
                                          skin: skin,
                                          cellColor: theme.grid,
                                          glowColor: theme.accent,
                                          gridLineColor: theme.gridLine,
                                          boardFamily: boardFamily,
                                          previewShip: _previewShip,
                                          previewValid: _previewValid,
                                          onTapCell: _randomizing
                                              ? null
                                              : _onGridTap,
                                          onShipTap: _randomizing
                                              ? null
                                              : _rotateShip,
                                          onShipDragStart: _randomizing
                                              ? null
                                              : (kind) => SoundService.instance
                                                    .shipMove(
                                                      shipSkinId: skin.id,
                                                    ),
                                          onShipDragEnd: _randomizing
                                              ? null
                                              : _moveShip,
                                          onShipDragUpdate: _onShipDragPreview,
                                          animateEntrance: _entranceDeal,
                                          pullInScales: _pullInScales,
                                          pullInFrom: _pullInFrom,
                                          clip: false,
                                          aimCell: _previewAimCell,
                                          cannonSkinId: loadout.cannonSkinId,
                                          recentEvents: _previewEvents,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Cannon — decorative only, like the battle screen's
                              // parked gun. Overlaps the grid's bottom edge so
                              // only the pointy muzzle peeks onto the deck (same
                              // 0.07 overlap the battle screen uses). In the old
                              // layout this was a separate 92px strip below the
                              // grid that shrank the board.
                              Positioned(
                                left: w / 2 - renderSize / 2,
                                top: cannonCenterY - renderSize / 2,
                                width: renderSize,
                                height: renderSize,
                                child: IgnorePointer(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: ScaleTransition(
                                            scale: Tween(begin: 0.86, end: 1.0)
                                                .animate(
                                                  CurvedAnimation(
                                                    parent: anim,
                                                    curve: Curves.easeOut,
                                                  ),
                                                ),
                                            child: child,
                                          ),
                                        ),
                                    // The reload ring has to redraw as the
                                    // clock runs, and nothing else on this
                                    // screen ticks — so the cannon listens to
                                    // it directly rather than the whole
                                    // deploy screen rebuilding 60 times a
                                    // second behind it.
                                    child: AnimatedBuilder(
                                      key: ValueKey(loadout.cannonSkinId),
                                      animation: _previewReloadCtrl,
                                      builder: (context, _) => CannonWidget(
                                        skin: loadout.cannonSkin,
                                        cooldownFraction:
                                            _previewReloadCtrl.value,
                                        size: renderSize,
                                        fireTrigger: _previewFireCtrl.stream,
                                        readyTrigger: _previewReadyCtrl.stream,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // The preview shell itself, arcing from the
                              // cannon above to whichever empty cell was last
                              // tapped — see `_firePreviewShot`. Only mounted
                              // while a shot is actually in flight.
                              if (_previewAimCell != null)
                                _previewShotLayer(loadout.cannonSkin),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Opponent dropped mid-deploy: the same reconnect window a
          // battle drop gets, mapped onto this screen. Always mounted so
          // it can react to `NetworkService` on its own (this screen's
          // build only watches the controller); it renders as nothing
          // unless the peer is actually lost/gone.
          ReconnectOverlay(onAbandon: _abandonPeer),
        ],
      ),
    );
  }

  /// The opponent never came back (see the reconnect overlay) — the
  /// pre-battle match is void, so drop the connection and leave the flow
  /// entirely, mirroring the battle screen's `_abandon`.
  void _abandonPeer() {
    final controller = context.read<GameController>();
    if (controller.hasRemotePeer) controller.network.stop();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  final GlobalKey _gridKey = GlobalKey();
}

/// A dock-tray ship icon; tap to select, drag to drop onto the grid.
class _DockShip extends StatelessWidget {
  final ShipSpec spec;
  final ShipSkin skin;
  final bool placed;
  final bool selected;
  final double cell;
  final VoidCallback onTap;

  /// True for Player 2's (180°-rotated) placement screen. The dock icon
  /// and drop-target logic don't need to know about this — `RotatedBox`
  /// already handles them transparently (see `build()` on
  /// `_PlacementScreenState`) — but `Draggable.feedback` is the one
  /// exception: it's rendered into the app's root `Overlay`, which sits
  /// OUTSIDE that RotatedBox, so without this the drag ghost would show
  /// up right-side-up while dragged across an upside-down board. This
  /// only spins the ghost's own artwork; the drop math still reads the
  /// raw pointer offset exactly as before.
  final bool rotated;

  const _DockShip({
    super.key,
    required this.spec,
    required this.skin,
    required this.placed,
    required this.selected,
    required this.cell,
    required this.onTap,
    this.rotated = false,
  });

  @override
  Widget build(BuildContext context) {
    // Resting dock icon: width scales with the ship's cell-length (same
    // "unit * spec.size" pattern the battle-screen fleet row uses)
    // instead of every ship — a 2-cell destroyer and a 5-cell carrier
    // alike — rendering inside the same fixed 68px box.
    const dockUnit = 11.0;
    const dockBeam = 30.0;
    // Cross-faded on the hull skin id: picking a new hull in the GEAR
    // dialog used to swap every dock icon on the very next frame, which
    // read as a glitch next to the grid/deck's own 320ms dissolve. Same
    // fade+scale treatment as the cannon bay below, just quicker since
    // these icons are much smaller.
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.85,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: AnimatedShip(
        key: ValueKey(skin.id),
        spec: spec,
        skin: skin,
        width: dockUnit * spec.size + 14,
        height: dockBeam,
      ),
    );

    final child = GestureDetector(
      onTap: placed ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.cream.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: AppColors.outline, width: 2)
              : null,
        ),
        child: Opacity(opacity: placed ? 0.25 : 1, child: icon),
      ),
    );

    if (placed) return child;

    return Draggable<({ShipKind kind, bool horizontal})>(
      data: (kind: spec.kind, horizontal: true),
      // PICKUP TICK: the moment this ship leaves the dock it plays its
      // own skin's move sound — the lighter partner to the drop's
      // `place` sound (see `SoundService.shipMove`).
      onDragStarted: () => SoundService.instance.shipMove(shipSkinId: skin.id),
      // BUGFIX (placement controls): the grid's `onMove`/`onAcceptWithDetails`
      // (below) read `details.offset` — which Flutter documents as the
      // pointer's raw global position, not the feedback widget's
      // position — and treat that cell directly as the ship's TOP-LEFT
      // cell. With the default `childDragAnchorStrategy`, the feedback
      // ghost is anchored whatever point on the small dock icon you
      // happened to grab, so the ghost visually trails your finger from
      // an offset — but the drop math ignores that offset entirely and
      // places the ship's top-left wherever your finger ends up. Net
      // effect: grab a ship anywhere but its own top-left corner and it
      // lands shifted from where the ghost showed it, which reads as the
      // controls just being unreliable. `pointerDragAnchorStrategy` pins
      // the feedback's OWN top-left to the pointer instead, so the ghost
      // you see is always exactly the cell the ship will land on —
      // consistent no matter where on the dock icon you grabbed it.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Sized to the REAL grid cell (cell * spec.size wide, one cell
      // tall) instead of a fixed 110×60.5 box every ship used to share
      // regardless of length or the device's actual cell size — that
      // mismatch is what made the ghost ship look oversized/misaligned
      // against the green/red highlight cells while dragging it onto
      // the grid.
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: Transform.rotate(
            angle: rotated ? math.pi : 0,
            child: AnimatedShip(
              spec: spec,
              skin: skin,
              width: cell * spec.size,
              height: cell,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: child),
      child: child,
    );
  }
}

/// Round white EXIT pill (reference style).
class _ExitButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ExitButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        SoundService.instance.click();
        onTap();
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.cream,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline, width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0x44000000), offset: Offset(0, 3)),
          ],
        ),
        child: const Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: Text(
              'EXIT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1,
                color: AppColors.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interstitial when passing the device between local players.
/// Matches the 1:1 gameplay video: full steel-blue screen, big friendly
/// message, chunky green OK button.
class HandoffScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onReady;

  const HandoffScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.steelBlue,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: AppText.title(size: 30),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 16,
                      color: AppColors.cream.withValues(alpha: 0.85),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  NeonButton(
                    label: buttonLabel,
                    color: AppColors.seafoam,
                    onPressed: onReady,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header button that opens the pass-and-play gear picker. Wears the
/// seat's own fleet colour so it doubles as a reminder of whose screen
/// this is.
class _GearButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _GearButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = color.computeLuminance() > 0.5
        ? AppColors.outline
        : AppColors.cream;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: cartoonBox(color, radius: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.palette, size: 15, color: ink),
            const SizedBox(width: 5),
            Text('GEAR', style: AppText.label(size: 10, color: ink)),
          ],
        ),
      ),
    );
  }
}

/// Per-seat customization for local pass-and-play.
///
/// Only offers gear the profile actually OWNS: the shipyard is still the
/// only place anything gets bought, out of one shared wallet. This is
/// purely the two people sharing the device dividing up what is already
/// unlocked, so each of them sails something they picked rather than both
/// inheriting whatever the device owner last equipped.
class _GearDialog extends StatefulWidget {
  final ProfileStore profile;
  final String seatLabel;
  final Loadout current;
  final ValueChanged<Loadout> onChanged;

  const _GearDialog({
    required this.profile,
    required this.seatLabel,
    required this.current,
    required this.onChanged,
  });

  @override
  State<_GearDialog> createState() => _GearDialogState();
}

class _GearDialogState extends State<_GearDialog> {
  late Loadout _lo = widget.current;

  void _set(Loadout next) {
    SoundService.instance.click();
    setState(() => _lo = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ships = Catalog.shipSkins
        .where((s) => widget.profile.ownsShip(s.id))
        .toList();
    final cannons = Catalog.cannonSkins
        .where((c) => widget.profile.ownsCannon(c.id))
        .toList();
    final themes = Catalog.gameplayThemes
        .where((t) => widget.profile.ownsTheme(t.id))
        .toList();
    final sets = FleetFamilies.all
        .where((f) => widget.profile.ownsFamilySet(f))
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Container(
        decoration: cartoonBox(AppColors.navy, radius: 20),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.seatLabel} GEAR',
                    style: AppText.title(size: 18),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    SoundService.instance.click();
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.close, color: AppColors.cream),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'EVERYTHING THE SHIPYARD HAS UNLOCKED — PICK YOURS',
              style: AppText.label(
                size: 9,
                color: AppColors.cream.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _section('HULL'),
                  _ArrowScroller(
                    height: 76,
                    children: [
                      for (final s in ships)
                        _hullChip(
                          skin: s,
                          label: s.name.toUpperCase(),
                          selected: _lo.shipSkinId == s.id,
                          onTap: () => _set(
                            _lo.copyWith(shipSkinId: s.id, shipChosen: true),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _section('CANNON'),
                  _ArrowScroller(
                    height: 64,
                    children: [
                      for (final c in cannons)
                        _swatchChip(
                          top: c.barrel,
                          bottom: c.projectile,
                          label: c.name.toUpperCase(),
                          selected: _lo.cannonSkinId == c.id,
                          onTap: () => _set(_lo.copyWith(cannonSkinId: c.id)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Matches the shipyard's DECK tab — this used to say
                  // BATTLEFIELD, back when the shipyard's own tab was
                  // still called GAMEPLAY and covered both the boards
                  // and the matched sets. Every deployment screen shares
                  // this one dialog (vs AI, pass-and-play, online,
                  // hotspot), so the rename only needs to happen here.
                  _section('DECK'),
                  _ArrowScroller(
                    height: 64,
                    children: [
                      for (final t in themes)
                        _swatchChip(
                          top: t.grid,
                          bottom: t.deck,
                          label: t.name.toUpperCase(),
                          selected: _lo.themeId == t.id,
                          onTap: () => _set(_lo.copyWith(themeId: t.id)),
                        ),
                    ],
                  ),
                  // Only appears once at least one matched set is fully
                  // owned — this is a shortcut onto gear already unlocked
                  // above, not a fourth thing to buy, so an empty shelf
                  // here would just be dead space. Matches the shipyard's
                  // GAMEPLAY tab: tapping one of these sets HULL, CANNON
                  // and DECK together in one go, the same trio
                  // `ProfileStore.buyFamilySet` equips on purchase.
                  if (sets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _section('GAMEPLAY'),
                    _ArrowScroller(
                      height: 64,
                      children: [
                        for (final family in sets)
                          _setChip(
                            family: family,
                            label: family.fleetName.toUpperCase(),
                            selected:
                                _lo.shipChosen &&
                                _lo.shipSkinId == 'f_${family.key}' &&
                                _lo.cannonSkinId == 'f_${family.key}' &&
                                _lo.themeId == 'f_${family.key}',
                            onTap: () => _set(
                              _lo.copyWith(
                                shipSkinId: 'f_${family.key}',
                                shipChosen: true,
                                cannonSkinId: 'f_${family.key}',
                                themeId: 'f_${family.key}',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            NeonButton(
              label: 'DONE',
              icon: Icons.check,
              color: AppColors.seafoam,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(title, style: AppText.label(size: 10)),
  );

  Widget _hullChip({
    required ShipSkin skin,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 94,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.outline,
            width: selected ? 3 : 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              width: 78,
              child: CustomPaint(
                painter: ShipPainter(
                  spec: kFleet[2], // cruiser — reads clearly at this size
                  skin: skin,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(size: 8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatchChip({
    required Color top,
    required Color bottom,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 94,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.outline,
            width: selected ? 3 : 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.outline, width: 1.5),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, bottom],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(size: 8),
            ),
          ],
        ),
      ),
    );
  }

  /// A matched-set shortcut chip. Unlike [_hullChip] and [_swatchChip],
  /// which each preview one piece of gear, this one stands in for three
  /// at once — so instead of a hull silhouette or a colour swatch it
  /// just wears the family's own accent and name, the way the shipyard's
  /// matched-set card does.
  Widget _setChip({
    required FleetFamily family,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 94,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.outline,
            width: selected ? 3 : 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.outline, width: 1.5),
                color: family.accent,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: AppColors.cream,
                size: 14,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(size: 8),
            ),
          ],
        ),
      ),
    );
  }
}

/// A horizontally-scrolling chip row for the gear dialog, with left/right
/// arrow buttons that fade in only when there is actually more content to
/// scroll to on that side.
///
/// The dialog is narrow enough (it shares the width of a phone screen)
/// that a shipyard with more than three or four unlocks in a category
/// always runs off the right edge with nothing on screen to say so — the
/// row just looks cut off. The arrows make the overflow discoverable and
/// tappable, on top of the swipe gesture the ListView already supports.
class _ArrowScroller extends StatefulWidget {
  final double height;
  final List<Widget> children;

  const _ArrowScroller({required this.height, required this.children});

  @override
  State<_ArrowScroller> createState() => _ArrowScrollerState();
}

class _ArrowScrollerState extends State<_ArrowScroller> {
  final ScrollController _controller = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshArrows);
    // The list hasn't laid out yet on the first frame, so its
    // maxScrollExtent isn't known until just after — a single
    // post-frame check is enough to show the right arrow immediately
    // when the content overflows.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshArrows());
  }

  @override
  void didUpdateWidget(covariant _ArrowScroller old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshArrows());
  }

  void _refreshArrows() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > pos.minScrollExtent + 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _nudge(double delta) {
    if (!_controller.hasClients) return;
    SoundService.instance.click();
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_refreshArrows);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            children: widget.children,
          ),
          if (_canLeft)
            Positioned(left: 0, child: _edgeFade(alignRight: false)),
          if (_canRight)
            Positioned(right: 0, child: _edgeFade(alignRight: true)),
          if (_canLeft)
            Positioned(
              left: -6,
              child: _arrowButton(
                icon: Icons.chevron_left,
                onTap: () => _nudge(-110),
              ),
            ),
          if (_canRight)
            Positioned(
              right: -6,
              child: _arrowButton(
                icon: Icons.chevron_right,
                onTap: () => _nudge(110),
              ),
            ),
        ],
      ),
    );
  }

  /// A soft gradient behind each arrow so it reads on top of whichever
  /// chip happens to be scrolled underneath it, instead of the button
  /// floating with no visual anchor.
  Widget _edgeFade({required bool alignRight}) {
    return IgnorePointer(
      child: Container(
        width: 28,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: alignRight ? Alignment.centerLeft : Alignment.centerRight,
            end: alignRight ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              AppColors.navy.withValues(alpha: 0),
              AppColors.navy.withValues(alpha: 0.85),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrowButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.navyDeep,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: 16, color: AppColors.cream),
      ),
    );
  }
}

/// Custom painter for family shell artwork in the placement preview.
class _FamilyShellPainter extends CustomPainter {
  final FleetFamily family;

  const _FamilyShellPainter(this.family);

  @override
  void paint(Canvas canvas, Size size) =>
      paintFamilyShell(canvas, size, family);

  @override
  bool shouldRepaint(covariant _FamilyShellPainter old) =>
      old.family.id != family.id;
}

/// Custom painter for legacy cannon shell artwork in the placement preview.
class _LegacyCannonballPainter extends CustomPainter {
  final String cannonId;

  const _LegacyCannonballPainter(this.cannonId);

  @override
  void paint(Canvas canvas, Size size) =>
      paintLegacyShell(canvas, size, cannonId);

  @override
  bool shouldRepaint(covariant _LegacyCannonballPainter old) =>
      old.cannonId != cannonId;
}
