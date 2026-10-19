import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/alarm_event.dart';
import '../models/sensor.dart';
import 'formatters.dart';

/// Apparence d'une entrée du journal selon son type (et son capteur).
({IconData icon, String title, Color color, Color background}) journalStyle(AlarmEvent event) =>
    switch (event.kind) {
      AlarmEventKind.armed => (
          icon: Icons.lock_rounded,
          title: 'Alarme activée',
          color: AppColors.protected,
          background: AppColors.protectedSoft,
        ),
      AlarmEventKind.armedNight => (
          icon: Icons.bedtime_rounded,
          title: 'Mode nuit activé',
          color: AppColors.night,
          background: AppColors.nightSoft,
        ),
      AlarmEventKind.disarmed => (
          icon: Icons.lock_open_rounded,
          title: 'Alarme désactivée',
          color: AppColors.inactive,
          background: AppColors.inactiveSoft,
        ),
      AlarmEventKind.triggered => (
          icon: Icons.campaign_rounded,
          title: 'Sirène déclenchée',
          color: AppColors.alert,
          background: AppColors.alertSoft,
        ),
      AlarmEventKind.detection when event.sensor?.isContact ?? false => (
          icon: Icons.sensor_door_outlined,
          title: 'Ouverture détectée',
          color: AppColors.warning,
          background: AppColors.warningSoft,
        ),
      AlarmEventKind.detection => (
          icon: Icons.directions_run_rounded,
          title: 'Mouvement détecté',
          color: AppColors.warning,
          background: AppColors.warningSoft,
        ),
    };

/// Ligne du journal : icône colorée, libellé, détail et heure de réception.
class JournalEventTile extends StatelessWidget {
  const JournalEventTile({super.key, required this.event, this.showDate = true});

  final AlarmEvent event;

  /// Afficher la date si l'entrée ne date pas d'aujourd'hui.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = journalStyle(event);
    final uptime = event.uptimeMs;
    final sensor = event.sensor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(style.icon, size: 20, color: style.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(style.title,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  switch ((sensor, uptime)) {
                    (final Sensor s, final int u) =>
                      '${s.label} · ESP32 allumé depuis ${formatUptime(u)}',
                    _ => 'Confirmé par l\'ESP32',
                  },
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(showDate ? formatShortDateTime(event.at) : formatTime(event.at),
              style: textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.textSecondary,
              )),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Carte du dashboard : dernières entrées du journal et accès au journal complet.
class ActivityJournalCard extends StatelessWidget {
  const ActivityJournalCard({
    super.key,
    required this.events,
    required this.onOpenJournal,
    this.maxEntries = 6,
  });

  final List<AlarmEvent> events;
  final VoidCallback onOpenJournal;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final detectionsToday = events
        .where((e) => e.kind == AlarmEventKind.detection && isSameDay(e.at, now))
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text('Activité récente',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onOpenJournal,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Tout voir'),
                ),
              ],
            ),
            Text(
              detectionsToday == 0
                  ? 'Aucune détection aujourd\'hui'
                  : '$detectionsToday détection${detectionsToday > 1 ? 's' : ''} aujourd\'hui',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const JournalEmptyState()
            else
              for (final event in events.take(maxEntries)) JournalEventTile(event: event),
          ],
        ),
      ),
    );
  }
}

class JournalEmptyState extends StatelessWidget {
  const JournalEmptyState({
    super.key,
    this.message = 'Aucune activité enregistrée pour l\'instant.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppColors.inactive),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
