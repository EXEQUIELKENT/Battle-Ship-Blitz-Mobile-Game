import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The app's ONE yes/no confirmation box.
///
/// Born from the battle screen's surrender prompt, which set the look:
/// navy panel, chunky outline frame, cream heading/body text, and a
/// green "keep going" action beside a red "do it" action, all riding the
/// framework's stock dialog motion (the same fade-and-grow every
/// AlertDialog here uses).
///
/// Shared verbatim so every risky tap in the game asks in exactly the
/// same voice — the shipyard's buy confirmations included — instead of
/// each screen hand-rolling its own idea of what a warning looks like.
Future<bool> showCartoonConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'NO',
  String confirmLabel = 'YES',
}) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.navy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.outline, width: 3),
      ),
      title: Text(title, style: AppText.heading(size: 16)),
      content: Text(
        message,
        style: AppText.body(
            size: 13, color: AppColors.cream.withValues(alpha: 0.85)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child:
              Text(cancelLabel, style: AppText.label(color: AppColors.green)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: AppText.label(color: AppColors.hit)),
        ),
      ],
    ),
  );
  return choice ?? false;
}
