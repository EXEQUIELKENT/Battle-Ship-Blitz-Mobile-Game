import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/network_service.dart';
import 'neon_widgets.dart';

/// Full-screen "opponent lost connection" overlay — the same three-state
/// UI the battle screen's `_ReconnectOverlay` shows, lifted out so the
/// mode-VOTE screen and the DEPLOY screen can hold a dropped opponent
/// open too, not just a live battle.
///
/// The reconnect window itself lives in [NetworkService] (see
/// `_openGraceWindow`); the overlay is purely its face:
///
///  * `peerLost` + a positive [NetworkService.graceSecondsLeft] — the
///    visible countdown, telling the survivor they can rejoin from
///    MULTIPLAYER → SCAN FOR GAMES.
///  * `peerLost` with the countdown at/below zero — the silent hold: the
///    seat is still open, they're just not being counted down any more.
///  * [NetworkService.peerGone] — the peer gave up or the window truly
///    expired; the only way forward is to abandon.
///
/// Must be a direct child of a [Stack] (it returns a `Positioned.fill`,
/// exactly like the battle screen's original).
class ReconnectOverlay extends StatelessWidget {
  final VoidCallback onAbandon;

  const ReconnectOverlay({super.key, required this.onAbandon});

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkService>();
    if (!net.peerLost && !net.peerGone) return const SizedBox.shrink();

    final expired = net.peerGone;
    final counting = net.peerLost && net.graceSecondsLeft > 0;
    final holding = net.peerLost && net.graceSecondsLeft <= 0;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: cartoonBox(AppColors.navy, radius: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expired
                      ? Icons.person_off
                      : holding
                      ? Icons.hourglass_bottom
                      : Icons.wifi_tethering_off,
                  color: expired ? AppColors.hit : AppColors.gold,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  expired
                      ? '${net.peerName.toUpperCase()} DID NOT RETURN'
                      : '${net.peerName.toUpperCase()} LOST CONNECTION',
                  textAlign: TextAlign.center,
                  style: AppText.heading(size: 15),
                ),
                const SizedBox(height: 10),
                if (counting) ...[
                  Text(
                    '${net.graceSecondsLeft}s',
                    style: AppText.title(size: 42, color: AppColors.gold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Holding the match open. They can rejoin from\n'
                    'MULTIPLAYER → SCAN FOR GAMES.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 12,
                      color: AppColors.cream.withValues(alpha: 0.85),
                    ),
                  ),
                ] else if (holding) ...[
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.gold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Still holding their seat — no rush.\n'
                    'They can rejoin whenever they\'re back.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 12,
                      color: AppColors.cream.withValues(alpha: 0.85),
                    ),
                  ),
                ] else
                  Text(
                    'The match is void — no win, no loss,\n'
                    'and no RP for either captain.',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 12,
                      color: AppColors.cream.withValues(alpha: 0.85),
                    ),
                  ),
                const SizedBox(height: 18),
                NeonButton(
                  label: expired ? 'BACK TO MENU' : 'LEAVE — NO RESULT',
                  icon: Icons.logout,
                  color: expired ? AppColors.blue : AppColors.inkSoft,
                  compact: true,
                  onPressed: onAbandon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
