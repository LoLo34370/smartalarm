import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../controllers/alarm_controller.dart';
import '../models/sensor.dart';
import 'formatters.dart';
import 'pulse.dart';

/// Carte compacte : icône, titre, valeur et détail, colorée selon le statut.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
    required this.background,
    this.animate = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;
  final Color background;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
              child: Pulse(active: animate, child: Icon(icon, color: color)),
            ),
            const SizedBox(height: 14),
            Text(title, style: textTheme.labelLarge?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                value,
                key: ValueKey(value),
                style: textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            Text(detail, style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Ligne de [SensorsCard].
typedef SensorEntry = ({
  Sensor sensor,
  SensorStatus status,
  bool? isActive,
  DateTime? lastDetectionAt,
});

/// Section de [SensorsCard] : une pièce et ses capteurs.
typedef RoomEntry = ({
  Room room,
  SensorStatus status,
  List<SensorEntry> sensors,
});

/// Libellé et couleurs d'un statut de capteur ou de pièce.
(String, Color, Color) _statusStyle(SensorStatus status) => switch (status) {
      SensorStatus.inactive => ('Inactif', AppColors.inactive, AppColors.inactiveSoft),
      SensorStatus.ignoredAtNight => ('Ignoré la nuit', AppColors.night, AppColors.nightSoft),
      SensorStatus.monitoring => ('Surveillé', AppColors.protected, AppColors.protectedSoft),
      SensorStatus.intrusion => ('Intrusion !', AppColors.alert, AppColors.alertSoft),
    };

/// Capteurs de la maison, regroupés par pièce : état en direct et rôle dans
/// le mode courant. Seule la pièce de l'intrusion passe en rouge.
class SensorsCard extends StatelessWidget {
  const SensorsCard({super.key, required this.rooms});

  final List<RoomEntry> rooms;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pièces',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            for (final room in rooms) _RoomSection(entry: room),
          ],
        ),
      ),
    );
  }
}

class _RoomSection extends StatelessWidget {
  const _RoomSection({required this.entry});

  final RoomEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final intrusion = entry.status == SensorStatus.intrusion;
    final (_, color, background) = _statusStyle(entry.status);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      decoration: BoxDecoration(
        color: intrusion ? background : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: intrusion ? color : AppColors.inactiveSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.room.label,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: intrusion ? color : null,
                    )),
              ),
              if (intrusion)
                Flexible(
                  child: Text('Intrusion ${entry.room.inLabel}',
                      textAlign: TextAlign.end,
                      style: textTheme.labelMedium
                          ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          for (final sensor in entry.sensors) _SensorRow(entry: sensor),
        ],
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({required this.entry});

  final SensorEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (statusLabel, color, background) = _statusStyle(entry.status);
    final sensor = entry.sensor;
    final icon = switch (sensor) {
      Sensor.pirSalon => Icons.sensors_rounded,
      Sensor.pirChambre => Icons.bed_outlined,
      Sensor.door => Icons.door_front_door_outlined,
      Sensor.window => Icons.window_outlined,
    };
    final live = switch ((entry.isActive, sensor.isContact)) {
      (null, _) => 'État inconnu',
      (true, true) => 'Ouverte',
      (false, true) => 'Fermée',
      (true, false) => 'Mouvement en cours',
      (false, false) => 'Aucun mouvement',
    };
    final last = entry.lastDetectionAt;
    final detail =
        last == null ? live : '$live · dernière détection ${formatShortDateTime(last)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
            child: Pulse(
              active: entry.status == SensorStatus.intrusion,
              child: Icon(icon, size: 20, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sensor.label,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: entry.isActive == true && sensor.isContact
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
            child: Text(statusLabel,
                style: textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// État de la sirène (buzzer) : active uniquement en TRIGGERED.
class SirenStatusCard extends StatelessWidget {
  const SirenStatusCard({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return active
        ? const InfoCard(
            icon: Icons.campaign_rounded,
            title: 'Sirène',
            value: 'En marche',
            detail: 'LED rouge clignotante',
            color: AppColors.alert,
            background: AppColors.alertSoft,
            animate: true,
          )
        : const InfoCard(
            icon: Icons.volume_off_rounded,
            title: 'Sirène',
            value: 'Éteinte',
            detail: 'Aucune alerte en cours',
            color: AppColors.inactive,
            background: AppColors.inactiveSoft,
          );
  }
}
