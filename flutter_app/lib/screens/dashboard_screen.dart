import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../controllers/alarm_controller.dart';
import '../models/alarm_models.dart';
import '../services/alarm_connection.dart';
import '../widgets/alarm_control_button.dart';
import '../widgets/alarm_status_card.dart';
import '../widgets/alert_banners.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/device_status_cards.dart';
import '../widgets/journal_widgets.dart';
import 'journal_screen.dart';

/// Écran principal. Tout ce qui est affiché provient des messages MQTT
/// relayés par [AlarmController].
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    this.deviceId = 'demo01',
    this.onOpenSettings,
  });

  final AlarmController controller;
  final String deviceId;
  final VoidCallback? onOpenSettings;

  static const double _wideBreakpoint = 860;
  static const double _maxContentWidth = 1120;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              final padding = wide ? 32.0 : 16.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: padding, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DashboardHeader(
                          brokerStatus: controller.brokerStatus,
                          availability: controller.availability,
                          deviceId: deviceId,
                          onOpenSettings: onOpenSettings,
                        ),
                        const SizedBox(height: 20),
                        _Banners(controller: controller),
                        if (wide) _wideLayout(context) else _narrowLayout(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _narrowLayout(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusCard(),
          const SizedBox(height: 16),
          _controlButton(),
          const SizedBox(height: 16),
          _deviceCards(),
          const SizedBox(height: 16),
          _history(context),
        ],
      );

  Widget _wideLayout(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statusCard(),
                const SizedBox(height: 20),
                _controlButton(),
                const SizedBox(height: 20),
                _deviceCards(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(flex: 5, child: _history(context)),
        ],
      );

  Widget _statusCard() => AlarmStatusCard(
        state: controller.alarmState,
        isLive: controller.isLive,
        isLoading: controller.alarmState == null &&
            controller.brokerStatus != BrokerStatus.connected &&
            controller.connectionError == null,
      );

  Widget _controlButton() => AlarmControlButton(
        nextCommand: controller.nextCommand,
        isTriggered: controller.isTriggered,
        pendingCommand: controller.pendingCommand,
        enabled: controller.canSendCommand,
        disabledReason: _disabledReason(),
        onPressed: controller.toggleAlarm,
        isAuthenticating: controller.isAuthenticating,
        requireAuthToDisarm: controller.requireAuthToDisarm,
      );

  String? _disabledReason() {
    if (!controller.isBrokerConnected) return 'Commandes indisponibles : pas de connexion au broker MQTT.';
    if (!controller.isDeviceOnline) return 'Commandes indisponibles : l\'ESP32 est hors ligne.';
    return null;
  }

  Widget _deviceCards() {
    final cards = [
      PirStatusCard(
        status: controller.pirStatus,
        lastMotionAt: controller.lastMotion?.at,
      ),
      SirenStatusCard(active: controller.isSirenActive),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 380
          ? Column(children: [cards[0], const SizedBox(height: 16), cards[1]])
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              ),
            ),
    );
  }

  Widget _history(BuildContext context) => ActivityJournalCard(
        events: controller.journal,
        onOpenJournal: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => JournalScreen(controller: controller),
        )),
      );
}

/// Bandeaux d'alerte : intrusion, perte de connexion, ESP32 hors ligne, commande.
class _Banners extends StatelessWidget {
  const _Banners({required this.controller});

  final AlarmController controller;

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[
      if (controller.isTriggered) const IntrusionBanner(),
      if (controller.connectionError case final error?)
        NoticeBanner(icon: Icons.cloud_off_rounded, message: error)
      else if (controller.brokerStatus == BrokerStatus.reconnecting)
        const NoticeBanner(
          icon: Icons.cloud_sync_rounded,
          message: 'Connexion au broker perdue, reconnexion en cours… '
              'Les informations affichées peuvent ne plus être à jour.',
        ),
      if (controller.isBrokerConnected &&
          controller.availability == DeviceAvailability.offline)
        const NoticeBanner(
          icon: Icons.portable_wifi_off_rounded,
          message: 'L\'ESP32 est hors ligne. L\'état affiché est le dernier connu '
              'et les commandes sont désactivées.',
          color: AppColors.alert,
          background: AppColors.alertSoft,
        ),
      if (controller.isBrokerConnected &&
          controller.availability == DeviceAvailability.unknown)
        const NoticeBanner(
          icon: Icons.hourglass_empty_rounded,
          message: 'En attente d\'un message de l\'ESP32…',
          color: AppColors.inactive,
          background: AppColors.inactiveSoft,
        ),
      if (controller.commandWarning case final warning?)
        NoticeBanner(icon: Icons.info_outline_rounded, message: warning),
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final banner in banners) ...[banner, const SizedBox(height: 12)],
          if (banners.isNotEmpty) const SizedBox(height: 4),
        ],
      ),
    );
  }
}
