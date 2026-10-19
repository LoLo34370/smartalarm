import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/alarm_models.dart';
import '../services/alarm_connection.dart';

/// En-tête : logo SmartAlarm + statut du broker MQTT et de l'ESP32.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.brokerStatus,
    required this.availability,
  });

  final BrokerStatus brokerStatus;
  final DeviceAvailability availability;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.protected,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SmartAlarm',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Alarme connectée · demo01',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _brokerPill(brokerStatus),
            _devicePill(availability, brokerConnected: brokerStatus == BrokerStatus.connected),
          ],
        ),
      ],
    );
  }

  static Widget _brokerPill(BrokerStatus status) => switch (status) {
        BrokerStatus.connected => const StatusPill(
            icon: Icons.cloud_done_rounded, label: 'MQTT connecté', color: AppColors.protected),
        BrokerStatus.connecting => const StatusPill(
            icon: Icons.cloud_sync_rounded, label: 'Connexion…', color: AppColors.warning, busy: true),
        BrokerStatus.reconnecting => const StatusPill(
            icon: Icons.cloud_sync_rounded, label: 'Reconnexion…', color: AppColors.warning, busy: true),
        BrokerStatus.disconnected => const StatusPill(
            icon: Icons.cloud_off_rounded, label: 'MQTT déconnecté', color: AppColors.alert),
      };

  static Widget _devicePill(DeviceAvailability availability, {required bool brokerConnected}) {
    if (!brokerConnected) {
      return const StatusPill(
          icon: Icons.memory_rounded, label: 'ESP32 : inconnu', color: AppColors.inactive);
    }
    return switch (availability) {
      DeviceAvailability.online => const StatusPill(
          icon: Icons.memory_rounded, label: 'ESP32 en ligne', color: AppColors.protected),
      DeviceAvailability.offline => const StatusPill(
          icon: Icons.memory_rounded, label: 'ESP32 hors ligne', color: AppColors.alert),
      DeviceAvailability.unknown => const StatusPill(
          icon: Icons.memory_rounded, label: 'ESP32 : en attente', color: AppColors.inactive),
    };
  }
}

/// Petite pastille de statut (icône + texte coloré).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
