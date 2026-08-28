import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/game_controller.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_notification.dart';
import 'battle_screen.dart';

/// Resumes a hotspot match `MatchStore` remembers this device as the
/// HOST of — reopens hosting under the exact same room code (without
/// which the code the joiner remembers no longer resolves to anything),
/// restores this device's own state from the saved snapshot via
/// `GameController.restoreFromOwnSnapshot`, and puts up the same
/// "waiting for them" overlay a live drop would (see
/// `NetworkService.beginHoldingSeatForReturn`) — there is no live
/// connection to have dropped, but functionally it's the identical
/// situation: this side is back, and whether the peer is remains
/// unknown.
Future<void> resumeHotspotAsHost(
  BuildContext context,
  Map<String, dynamic> saved,
) async {
  final network = context.read<NetworkService>();
  final controller = context.read<GameController>();
  final profile = context.read<ProfileStore>();

  final roomCode = saved['roomCode'] as String?;
  final rawSnapshot = saved['snapshot'];
  if (roomCode == null || roomCode.isEmpty || rawSnapshot is! Map) {
    AppNotification.show(context, 'That saved match is incomplete.',
        type: AppNoticeType.error);
    return;
  }

  final code = await network.hostHotspot(
    playerName: profile.playerName,
    resumeRoomCode: roomCode,
  );
  if (!context.mounted) return;
  if (code == null) {
    AppNotification.show(
      context,
      network.statusMessage.isNotEmpty
          ? network.statusMessage
          : 'Could not reopen the match.',
      type: AppNoticeType.error,
    );
    return;
  }

  network.peerName = saved['peerName'] as String? ?? 'Opponent';
  network.peerShipSkinId = saved['peerShipSkinId'] as String? ?? 'steel';
  network.peerShipSkinChosen = saved['peerShipSkinChosen'] as bool? ?? false;
  network.peerCannonSkinId = saved['peerCannonSkinId'] as String? ?? 'mk1';
  network.peerThemeId = saved['peerThemeId'] as String? ?? 'classic';

  controller.mode = GameMode.hotspot;
  network.setMatchHost(true); // this device is the one that just re-hosted
  controller.restoreFromOwnSnapshot(Map<String, dynamic>.from(rawSnapshot));
  network.beginHoldingSeatForReturn();

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const BattleScreen()),
  );
}
