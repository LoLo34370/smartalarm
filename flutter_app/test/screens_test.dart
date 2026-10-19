import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/controllers/alarm_controller.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/screens/dashboard_screen.dart';
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

  testWidgets('« Tout voir » ouvre le journal complet', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final connection = FakeAlarmConnection();
    final controller = AlarmController(connection, journalStore: MemoryJournalStore())..start();
    addTearDown(() {
      controller.dispose();
      connection.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(controller: controller)));
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
}
