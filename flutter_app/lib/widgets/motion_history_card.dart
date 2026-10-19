import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/alarm_models.dart';
import 'formatters.dart';

/// Historique des détections reçues pendant la session (non persisté).
class MotionHistoryCard extends StatelessWidget {
  const MotionHistoryCard({super.key, required this.events, required this.onClear});

  final List<MotionEvent> events;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Détections',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                _CountBadge(count: events.length),
                const Spacer(),
                if (events.isNotEmpty)
                  TextButton(onPressed: onClear, child: const Text('Effacer')),
              ],
            ),
            Text('Reçues pendant cette session',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const _EmptyHistory()
            else
              for (final (index, event) in events.indexed)
                _MotionTile(event: event, isLatest: index == 0),
          ],
        ),
      ),
    );
  }
}

class _MotionTile extends StatelessWidget {
  const _MotionTile({required this.event, required this.isLatest});

  final MotionEvent event;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLatest ? AppColors.alertSoft : AppColors.inactiveSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.directions_run_rounded,
                size: 20, color: isLatest ? AppColors.alert : AppColors.inactive),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mouvement détecté',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text('ESP32 allumé depuis ${formatUptime(event.uptimeMs)}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(formatTime(event.receivedAt),
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: AppColors.inactive),
          SizedBox(width: 10),
          Expanded(
            child: Text('Aucun mouvement détecté depuis l\'ouverture de l\'application.',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: count > 0 ? AppColors.alertSoft : AppColors.inactiveSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: count > 0 ? AppColors.alert : AppColors.inactive,
          )),
    );
  }
}
