import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/alarm_models.dart';

/// Bouton principal. Il envoie une commande et attend la confirmation de
/// l'ESP32 : il n'affiche jamais un état qui n'a pas été confirmé.
class AlarmControlButton extends StatelessWidget {
  const AlarmControlButton({
    super.key,
    required this.nextCommand,
    required this.isTriggered,
    required this.pendingCommand,
    required this.enabled,
    required this.disabledReason,
    required this.onPressed,
  });

  final AlarmCommand nextCommand;
  final bool isTriggered;
  final AlarmCommand? pendingCommand;
  final bool enabled;

  /// Explication affichée sous le bouton quand il est désactivé.
  final String? disabledReason;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isPending = pendingCommand != null;
    final (label, icon, color) = switch (nextCommand) {
      AlarmCommand.arm => ('Activer l\'alarme', Icons.lock_rounded, AppColors.protected),
      AlarmCommand.disarm when isTriggered =>
        ('Arrêter la sirène et désactiver', Icons.notifications_off_rounded, AppColors.alert),
      AlarmCommand.disarm => ('Désactiver l\'alarme', Icons.lock_open_rounded, AppColors.textPrimary),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: enabled && !isPending ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            // Pendant l'attente, le bouton garde sa couleur (atténuée) au lieu du gris.
            disabledBackgroundColor: isPending ? color.withValues(alpha: 0.75) : null,
            disabledForegroundColor: isPending ? Colors.white : null,
          ),
          icon: isPending
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Icon(icon),
          label: Text(isPending ? 'En attente de confirmation de l\'ESP32…' : label),
        ),
        if (!enabled && !isPending && disabledReason != null) ...[
          const SizedBox(height: 8),
          Text(
            disabledReason!,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
