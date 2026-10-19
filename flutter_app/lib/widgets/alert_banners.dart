import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'pulse.dart';

/// Bandeau rouge animé affiché pendant une intrusion (état TRIGGERED).
class IntrusionBanner extends StatelessWidget {
  const IntrusionBanner({super.key, this.cause = 'Une intrusion a été détectée.'});

  /// Ce qui a déclenché l'alarme, ex. « Ouverture : Porte d'entrée. »
  final String cause;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.alert,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.alert.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Pulse(child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Intrusion détectée !',
                      style: TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$cause La sirène est en marche.',
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message d'information (connexion perdue, ESP32 hors ligne, commande…).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.message,
    this.color = AppColors.warning,
    this.background = AppColors.warningSoft,
  });

  final IconData icon;
  final String message;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color, fontWeight: FontWeight.w500, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
