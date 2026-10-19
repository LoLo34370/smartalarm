import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/models/mqtt_topics.dart';

void main() {
  group('AlarmState.tryParse', () {
    test('décode les trois états publiés par l\'ESP32', () {
      expect(AlarmState.tryParse('{"state":"DISARMED"}'), AlarmState.disarmed);
      expect(AlarmState.tryParse('{"state":"ARMED"}'), AlarmState.armed);
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
    });

    test('rejette un événement inconnu ou incomplet', () {
      expect(MotionEvent.tryParse('{"event":"OTHER","uptimeMs":1}'), isNull);
      expect(MotionEvent.tryParse('{"event":"MOTION_DETECTED"}'), isNull);
      expect(MotionEvent.tryParse('pas du json'), isNull);
    });
  });

  test('MqttTopics construit les topics à partir de la base', () {
    const topics = MqttTopics('smartalarm/demo01');
    expect(topics.command, 'smartalarm/demo01/command');
    expect(topics.subscriptions, [
      'smartalarm/demo01/state',
      'smartalarm/demo01/motion',
      'smartalarm/demo01/availability',
    ]);
  });
}
