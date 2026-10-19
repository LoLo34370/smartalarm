import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/config/mqtt_config.dart';
import 'package:smartalarm/controllers/alarm_controller.dart';
import 'package:smartalarm/controllers/settings_controller.dart';
import 'package:smartalarm/main.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/screens/journal_screen.dart';

import 'helpers/fake_alarm_connection.dart';
import 'helpers/fakes.dart';

void main() {
  testWidgets('journal : regroupé par jour et filtrable', (tester) async {
    final connection = FakeAlarmConnection();
    final now = DateTime.now();
    final controller = AlarmController(
      connection,
      journalStore: MemoryJournalStore([
        AlarmEvent(kind: AlarmEventKind.triggered, at: now),
        AlarmEvent(kind: AlarmEventKind.motion, at: now, uptimeMs: 3000),
        AlarmEvent(kind: AlarmEventKind.armed, at: now.subtract(const Duration(days: 1))),
      ]),
    )..start();
    addTearDown(() {
      controller.dispose();
      connection.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: JournalScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Aujourd\'hui'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
    expect(find.text('Sirène déclenchée'), findsOneWidget);
    expect(find.text('Alarme activée'), findsOneWidget);

    await tester.tap(find.text('Mouvements'));
    await tester.pumpAndSettle();
    expect(find.text('Mouvement détecté'), findsOneWidget);
    expect(find.text('Sirène déclenchée'), findsNothing);
    expect(find.text('Hier'), findsNothing);
  });

  group('application complète', () {
    late MemorySettingsStore store;
    late SettingsController settings;
    late List<(MqttConfig, FakeAlarmConnection)> connections;

    setUp(() async {
      store = MemorySettingsStore();
      settings = SettingsController(
        store: store,
        authenticator: FakeAuthenticator(available: false),
        buildBrokerConfig: testBrokerConfig,
      );
      await settings.load();
      connections = [];
    });

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SmartAlarmApp(
        settings: settings,
        journalStore: MemoryJournalStore(),
        connectionFactory: (config) {
          final connection = FakeAlarmConnection();
          connections.add((config, connection));
          return connection;
        },
      ));
    }

    testWidgets('réglages : validation puis reconnexion au nouveau broker', (tester) async {
      await pumpApp(tester);
      connections.last.$2.goLive(AlarmState.disarmed);
      await tester.pump();
      expect(connections.single.$1, testBrokerConfig);

      await tester.tap(find.byTooltip('Réglages'));
      await tester.pumpAndSettle();

      final hostField = find.widgetWithText(TextFormField, 'Hôte');
      await tester.enterText(hostField, 'mqtts://bad:8883');
      await tester.tap(find.text('Enregistrer et se reconnecter'));
      await tester.pump();
      expect(find.text('Nom d\'hôte seul, sans « mqtts:// » ni port'), findsOneWidget);

      await tester.enterText(hostField, 'nouveau.s1.eu.hivemq.cloud');
      await tester.enterText(find.widgetWithText(TextFormField, 'Base des topics'), 'smartalarm/salon');
      await tester.tap(find.text('Enregistrer et se reconnecter'));
      // Pas de pumpAndSettle : l'indicateur « Connexion… » tourne en continu.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(store.broker?.host, 'nouveau.s1.eu.hivemq.cloud');
      expect(connections, hasLength(2), reason: 'nouvelle connexion créée');
      expect(connections.last.$1.topicBase, 'smartalarm/salon');
      expect(connections.last.$2.connectCalls, 1);
      expect(find.text('Alarme connectée · salon'), findsOneWidget);
    });

    testWidgets('« Tout voir » ouvre le journal complet', (tester) async {
      await pumpApp(tester);
      final connection = connections.single.$2;
      connection.goLive(AlarmState.armed);
      connection.publishMotion(1500, at: DateTime.now());
      connection.publishState(AlarmState.triggered);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('1 détection aujourd\'hui'), findsOneWidget);
      await tester.tap(find.text('Tout voir'));
      await tester.pumpAndSettle();
      expect(find.text('Journal d\'activité'), findsOneWidget);
      expect(find.text('Sirène déclenchée'), findsOneWidget);
    });
  });
}
