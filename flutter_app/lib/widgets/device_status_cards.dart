import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../controllers/alarm_controller.dart';
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

/// Statut du capteur PIR, déduit de l'état publié par l'ESP32.
class PirStatusCard extends StatelessWidget {
  const PirStatusCard({super.key, required this.status, required this.lastMotionAt});

  final PirStatus status;
  final DateTime? lastMotionAt;

  @override
  Widget build(BuildContext context) {
    final detail = lastMotionAt == null
        ? 'Aucune détection reçue'
        : 'Dernière détection : ${formatShortDateTime(lastMotionAt!)}';
    return switch (status) {
      PirStatus.inactive => InfoCard(
          icon: Icons.sensors_off_rounded,
          title: 'Capteur de mouvement',
          value: 'Inactif',
          detail: detail,
          color: AppColors.inactive,
          background: AppColors.inactiveSoft,
        ),
      PirStatus.monitoring => InfoCard(
          icon: Icons.sensors_rounded,
          title: 'Capteur de mouvement',
          value: 'Surveillance',
          detail: detail,
          color: AppColors.protected,
          background: AppColors.protectedSoft,
        ),
      PirStatus.motionDetected => InfoCard(
          icon: Icons.directions_run_rounded,
          title: 'Capteur de mouvement',
          value: 'Mouvement !',
          detail: detail,
          color: AppColors.alert,
          background: AppColors.alertSoft,
          animate: true,
        ),
    };
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
