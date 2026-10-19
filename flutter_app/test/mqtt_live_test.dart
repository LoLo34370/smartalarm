// ignore_for_file: avoid_print
// Test d'intégration RÉEL contre HiveMQ et l'ESP32 simulé (non exécuté par défaut).
//
//   flutter test --platform chrome --tags live \
//     --dart-define-from-file=config/dart_defines.json test/mqtt_live_test.dart
//
// Sur Chrome, c'est le vrai client WSS (MqttBrowserClient) qui est utilisé.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/config/mqtt_config.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/services/mqtt_service.dart';

Future<void> _waitFor(bool Function() condition, Duration timeout, String what) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Délai dépassé ($timeout) en attendant : $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  final config = MqttConfig.fromEnvironment();

  test(
    'connexion WSS, état retained, puis ARM/DISARM confirmés par l\'ESP32',
    () async {
      final service = MqttService(config: config);
      final states = <AlarmState>[];
      final availability = <DeviceAvailability>[];
      service.alarmStates.listen(states.add);
      service.availability.listen(availability.add);

      final stopwatch = Stopwatch()..start();
      await service.connect();
      await _waitFor(() => service.isConnected, const Duration(seconds: 20), 'connexion au broker');
      print('[live] connecté en ${stopwatch.elapsedMilliseconds} ms (client ${service.clientId})');

      await _waitFor(
        () => states.isNotEmpty && availability.isNotEmpty,
        const Duration(seconds: 10),
        'messages retained state + availability',
      );
      print('[live] retained reçus : availability=${availability.last.name}, state=${states.last.wireValue}');

      if (availability.last != DeviceAvailability.online) {
        print('[live] ESP32 hors ligne : test des commandes ignoré');
      } else {
        for (final (command, expected) in [
          (AlarmCommand.arm, AlarmState.armed),
          (AlarmCommand.disarm, AlarmState.disarmed),
        ]) {
          final sentAt = stopwatch.elapsedMilliseconds;
          expect(service.sendCommand(command), isTrue);
          await _waitFor(
            () => states.last == expected,
            const Duration(seconds: 15),
            'confirmation ${expected.wireValue} par l\'ESP32',
          );
          print('[live] ${command.wireValue} → ${expected.wireValue} confirmé en '
              '${stopwatch.elapsedMilliseconds - sentAt} ms');
        }
      }

      service.dispose();
      expect(service.status.value, BrokerStatus.disconnected);
    },
    skip: config.isComplete ? false : 'dart_defines.json absent (MQTT_HOST…)',
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
