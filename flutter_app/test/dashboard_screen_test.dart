import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/config/app_theme.dart';
import 'package:smartalarm/controllers/alarm_controller.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/models/sensor.dart';
import 'package:smartalarm/screens/dashboard_screen.dart';

import 'helpers/fake_alarm_connection.dart';

void main() {
  late FakeAlarmConnection connection;
  late AlarmController controller;

  setUp(() {
    connection = FakeAlarmConnection();
    controller = AlarmController(connection)..start();
  });

  tearDown(() {
    controller.dispose();
    connection.dispose();
  });

  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: DashboardScreen(controller: controller),
    ));
  }

  for (final (name, size) in [('mobile', Size(390, 844)), ('bureau', Size(1280, 800))]) {
    testWidgets('affichage $name : désarmé puis intrusion, sans débordement', (tester) async {
      await pumpDashboard(tester, size);
      connection.goLive(AlarmState.disarmed);
      await tester.pump();

      expect(find.text('Alarme désactivée'), findsOneWidget);
      expect(find.text('Activer l\'alarme'), findsOneWidget);
      expect(find.text('MQTT connecté'), findsOneWidget);
      expect(find.text('ESP32 en ligne'), findsOneWidget);

      connection.publishMotion(42000);
      connection.publishState(AlarmState.triggered);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Intrusion détectée !'), findsOneWidget);
      expect(find.text('Intrusion détectée'), findsOneWidget);
      expect(find.text('Arrêter la sirène et désactiver'), findsOneWidget);
      expect(find.text('En marche'), findsOneWidget);
      expect(find.text('Mouvement détecté'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('le bouton envoie ARM et attend la confirmation', (tester) async {
    await pumpDashboard(tester, const Size(390, 844));
    connection.goLive(AlarmState.disarmed);
    await tester.pump();

    await tester.tap(find.text('Activer l\'alarme'));
    await tester.pump();
    expect(connection.sentCommands, [AlarmCommand.arm]);
    expect(find.text('En attente de confirmation de l\'ESP32…'), findsOneWidget);
    expect(find.text('Alarme désactivée'), findsOneWidget);

    connection.publishState(AlarmState.armed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Maison protégée'), findsOneWidget);
    expect(find.text('Désactiver l\'alarme'), findsOneWidget);
  });

  testWidgets('mode nuit : ARM_NIGHT, PIR ignoré, intrusion par la fenêtre', (tester) async {
    await pumpDashboard(tester, const Size(390, 844));
    connection.goLive(AlarmState.disarmed);
    connection.publishSensors({Sensor.pirSalon: false, Sensor.door: false, Sensor.window: true});
    await tester.pump();
    expect(find.textContaining('Fenêtre ouverte'), findsOneWidget);

    await tester.ensureVisible(find.text('Mode nuit (porte et fenêtre)'));
    await tester.tap(find.text('Mode nuit (porte et fenêtre)'));
    await tester.pump();
    expect(connection.sentCommands, [AlarmCommand.armNight]);

    connection.publishState(AlarmState.armedNight);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Mode nuit'), findsOneWidget);
    expect(find.text('Ignoré la nuit'), findsOneWidget);
    expect(find.text('Surveillé'), findsNWidgets(2));

    connection.publishMotion(8000, sensor: Sensor.window);
    connection.publishState(AlarmState.triggered);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Ouverture : Fenêtre.'), findsOneWidget);
    expect(find.text('Intrusion !'), findsOneWidget);
    expect(find.text('Ouverture détectée'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ESP32 hors ligne : message explicite et bouton désactivé', (tester) async {
    await pumpDashboard(tester, const Size(390, 844));
    connection.goLive(AlarmState.armed);
    connection.publishAvailability(DeviceAvailability.offline);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('L\'ESP32 est hors ligne'), findsOneWidget);
    expect(find.text('Dernier état connu'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(button.onPressed, isNull);
  });
}
