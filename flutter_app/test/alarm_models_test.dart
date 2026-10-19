import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/models/mqtt_topics.dart';
import 'package:smartalarm/models/sensor.dart';

void main() {
  group('AlarmState.tryParse', () {
    test('décode les quatre états publiés par l\'ESP32', () {
      expect(AlarmState.tryParse('{"state":"DISARMED"}'), AlarmState.disarmed);
      expect(AlarmState.tryParse('{"state":"ARMED"}'), AlarmState.armed);
      expect(AlarmState.tryParse('{"state":"ARMED_NIGHT"}'), AlarmState.armedNight);
      expect(AlarmState.tryParse('{"state":"TRIGGERED"}'), AlarmState.triggered);
    });

    test('ignore les payloads invalides, inconnus ou vides (purge retained)', () {
      expect(AlarmState.tryParse(''), isNull);
      expect(AlarmState.tryParse('ARMED'), isNull);
      expect(AlarmState.tryParse('{"state":"armed"}'), isNull);
      expect(AlarmState.tryParse('{"state":42}'), isNull);
      expect(AlarmState.tryParse('[]'), isNull);
    });
  });

  test('AlarmCommand produit le JSON attendu par l\'ESP32', () {
    expect(jsonDecode(AlarmCommand.arm.toPayload()), {'command': 'ARM'});
    expect(jsonDecode(AlarmCommand.armNight.toPayload()), {'command': 'ARM_NIGHT'});
    expect(jsonDecode(AlarmCommand.disarm.toPayload()), {'command': 'DISARM'});
  });

  test('DeviceAvailability.parse', () {
    expect(DeviceAvailability.parse('online'), DeviceAvailability.online);
    expect(DeviceAvailability.parse('offline'), DeviceAvailability.offline);
    expect(DeviceAvailability.parse(''), DeviceAvailability.unknown);
  });

  group('MotionEvent.tryParse', () {
    test('décode une détection et l\'horodate à la réception', () {
      final now = DateTime(2026, 10, 19, 10);
      final event = MotionEvent.tryParse(
        '{"event":"MOTION_DETECTED","uptimeMs":125000}',
        receivedAt: now,
      );
      expect(event?.uptimeMs, 125000);
      expect(event?.receivedAt, now);
      expect(event?.sensor, Sensor.pirSalon, reason: 'ancien firmware : PIR');
    });

    test('décode le capteur à l\'origine de la détection', () {
      final event = MotionEvent.tryParse(
        '{"event":"OPENING_DETECTED","sensor":"door","uptimeMs":7000}',
      );
      expect(event?.sensor, Sensor.door);
      expect(
        MotionEvent.tryParse('{"event":"OPENING_DETECTED","sensor":"garage","uptimeMs":1}'),
        isNull,
      );
    });

    test('rejette un événement inconnu ou incomplet', () {
      expect(MotionEvent.tryParse('{"event":"OTHER","uptimeMs":1}'), isNull);
      expect(MotionEvent.tryParse('{"event":"MOTION_DETECTED"}'), isNull);
      expect(MotionEvent.tryParse('pas du json'), isNull);
    });
  });

  test('tryParseSensorStates', () {
    expect(
      tryParseSensorStates('{"pir_salon":"ACTIVE","door":"CLOSED","window":"OPEN","x":"OPEN"}'),
      {Sensor.pirSalon: true, Sensor.door: false, Sensor.window: true},
    );
    expect(tryParseSensorStates('{"door":"?"}'), isEmpty);
    expect(tryParseSensorStates(''), isNull);
  });

  test('le mode nuit ne surveille que le périmètre', () {
    expect(Sensor.door.isMonitoredIn(AlarmState.armedNight), isTrue);
    expect(Sensor.pirSalon.isMonitoredIn(AlarmState.armedNight), isFalse);
    expect(Sensor.pirSalon.isMonitoredIn(AlarmState.armed), isTrue);
    expect(Sensor.window.isMonitoredIn(AlarmState.disarmed), isFalse);
  });

  test('MqttTopics construit les topics à partir de la base', () {
    const topics = MqttTopics('smartalarm/demo01');
    expect(topics.command, 'smartalarm/demo01/command');
    expect(topics.subscriptions, [
      'smartalarm/demo01/state',
      'smartalarm/demo01/motion',
      'smartalarm/demo01/availability',
      'smartalarm/demo01/sensors',
    ]);
  });
}
