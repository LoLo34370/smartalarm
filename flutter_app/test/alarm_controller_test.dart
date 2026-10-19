import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/controllers/alarm_controller.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/services/alarm_connection.dart';

import 'helpers/fake_alarm_connection.dart';

void main() {
  late FakeAlarmConnection connection;
  late AlarmController controller;

  setUp(() {
    connection = FakeAlarmConnection();
    controller = AlarmController(
      connection,
      commandTimeout: const Duration(milliseconds: 50),
      historyLimit: 3,
    )..start();
  });

  tearDown(() {
    controller.dispose();
    connection.dispose();
  });

  test('démarre la connexion et n\'invente aucun état', () {
    expect(connection.connectCalls, 1);
    expect(controller.alarmState, isNull);
    expect(controller.canSendCommand, isFalse);
    expect(controller.pirStatus, PirStatus.inactive);
  });

  test('affiche l\'état retained reçu à la connexion', () {
    connection.goLive(AlarmState.armed);
    expect(controller.alarmState, AlarmState.armed);
    expect(controller.isLive, isTrue);
    expect(controller.nextCommand, AlarmCommand.disarm);
    expect(controller.pirStatus, PirStatus.monitoring);
  });

  test('ARM n\'arme rien localement : on attend la confirmation de l\'ESP32', () {
    connection.goLive(AlarmState.disarmed);

    controller.toggleAlarm();
    expect(connection.sentCommands, [AlarmCommand.arm]);
    expect(controller.pendingCommand, AlarmCommand.arm);
    expect(controller.alarmState, AlarmState.disarmed, reason: 'pas de changement artificiel');
    expect(controller.canSendCommand, isFalse, reason: 'pas de double envoi');

    connection.publishState(AlarmState.armed);
    expect(controller.alarmState, AlarmState.armed);
    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, isNull);
  });

  test('signale une commande non confirmée après le délai', () async {
    connection.goLive(AlarmState.disarmed);
    controller.toggleAlarm();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, contains('n\'a pas confirmé'));
    expect(controller.alarmState, AlarmState.disarmed);
    expect(controller.canSendCommand, isTrue);
  });

  test('signale une commande qui n\'a pas pu être envoyée', () {
    connection.goLive(AlarmState.disarmed);
    connection.acceptCommands = false;
    controller.toggleAlarm();
    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, contains('n\'a pas pu être envoyée'));
  });

  test('intrusion : sirène active, mouvement historisé, DISARM proposé', () {
    connection.goLive(AlarmState.armed);
    connection.publishMotion(125000);
    connection.publishState(AlarmState.triggered);

    expect(controller.isTriggered, isTrue);
    expect(controller.isSirenActive, isTrue);
    expect(controller.pirStatus, PirStatus.motionDetected);
    expect(controller.nextCommand, AlarmCommand.disarm);
    expect(controller.motionHistory.single.uptimeMs, 125000);

    controller.toggleAlarm();
    connection.publishState(AlarmState.disarmed);
    expect(connection.sentCommands.last, AlarmCommand.disarm);
    expect(controller.isSirenActive, isFalse);
  });

  test('l\'historique garde les plus récentes, dans la limite fixée', () {
    connection.goLive(AlarmState.armed);
    for (final uptime in [1000, 2000, 3000, 4000]) {
      connection.publishMotion(uptime);
    }
    expect(controller.motionHistory.map((e) => e.uptimeMs), [4000, 3000, 2000]);

    controller.clearMotionHistory();
    expect(controller.motionHistory, isEmpty);
  });

  test('ESP32 hors ligne : commandes désactivées, dernier état conservé', () {
    connection.goLive(AlarmState.armed);
    connection.publishAvailability(DeviceAvailability.offline);

    expect(controller.isLive, isFalse);
    expect(controller.canSendCommand, isFalse);
    expect(controller.alarmState, AlarmState.armed);
    controller.toggleAlarm();
    expect(connection.sentCommands, isEmpty);
  });

  test('perte du broker pendant une commande : attente annulée et signalée', () {
    connection.goLive(AlarmState.disarmed);
    controller.toggleAlarm();
    connection.status.value = BrokerStatus.reconnecting;

    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, contains('Connexion au broker perdue'));
    expect(controller.canSendCommand, isFalse);
  });

  test('reconnexion : l\'état retained resynchronise l\'affichage', () {
    connection.goLive(AlarmState.disarmed);
    connection.status.value = BrokerStatus.reconnecting;
    // Pendant la coupure, l'ESP32 a été armé par un autre client.
    connection.status.value = BrokerStatus.connected;
    connection.publishState(AlarmState.armed);

    expect(controller.alarmState, AlarmState.armed);
    expect(controller.isLive, isTrue);
  });
}
