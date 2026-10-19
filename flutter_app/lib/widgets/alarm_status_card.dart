import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/alarm_models.dart';
import 'pulse.dart';

/// Grande carte d'état : « Maison protégée », « Mode nuit », « Alarme désactivée »,
/// « Intrusion détectée », ou chargement tant qu'aucun état n'est reçu.
class AlarmStatusCard extends StatelessWidget {
  const AlarmStatusCard({
    super.key,
    required this.state,
    required this.isLive,
    required this.isLoading,
  });

  /// Dernier état publié par l'ESP32 (`null` = jamais reçu).
  final AlarmState? state;

  /// `false` si le broker ou l'ESP32 est injoignable : l'état est peut-être périmé.
  final bool isLive;

  /// Connexion en cours et aucun état encore reçu.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final visual = _StatusVisual.of(state, isLoading: isLoading);
    final textTheme = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: visual.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: visual.gradient.last.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? const SizedBox.square(
                        dimension: 36,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : Pulse(
                        active: state == AlarmState.triggered,
                        child: Icon(visual.icon, color: Colors.white, size: 36),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: !isLive && state != null
                      ? const _Tag(icon: Icons.history_rounded, label: 'Dernier état connu')
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Column(
              key: ValueKey(visual.title),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visual.title,
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  visual.subtitle,
                  style: textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusVisual {
  const _StatusVisual(this.icon, this.title, this.subtitle, this.gradient);

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;

  static _StatusVisual of(AlarmState? state, {required bool isLoading}) {
    if (isLoading) {
      return const _StatusVisual(Icons.sync_rounded, 'Connexion…',
          'Récupération de l\'état de l\'alarme.', [Color(0xFF7D8783), AppColors.inactive]);
    }
    return switch (state) {
      AlarmState.armed => const _StatusVisual(Icons.verified_user_rounded, 'Maison protégée',
          'L\'alarme est activée, tous les capteurs surveillent.',
          [Color(0xFF43A047), AppColors.protected]),
      AlarmState.armedNight => const _StatusVisual(Icons.bedtime_rounded, 'Mode nuit',
          'Porte et fenêtre surveillées. Vous pouvez circuler dans la maison.',
          [Color(0xFF3F51B5), AppColors.night]),
      AlarmState.triggered => const _StatusVisual(Icons.warning_amber_rounded,
          'Intrusion détectée', 'La sirène est en marche. Désactivez l\'alarme pour l\'arrêter.',
          [Color(0xFFE53935), AppColors.alert]),
      AlarmState.disarmed => const _StatusVisual(Icons.shield_outlined, 'Alarme désactivée',
          'Les mouvements ne déclenchent aucune alerte.', [Color(0xFF8A9490), AppColors.inactive]),
      null => const _StatusVisual(Icons.help_outline_rounded, 'État inconnu',
          'Aucun état reçu de l\'ESP32 pour le moment.', [Color(0xFF8A9490), AppColors.inactive]),
    };
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
