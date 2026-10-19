import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/models/sensor.dart';
import 'package:smartalarm/services/alarm_connection.dart';

/// Faux broker : les tests « publient » comme le ferait l'ESP32.
class FakeAlarmConnection implements AlarmConnection {
  @override
  final ValueNotifier<BrokerStatus> status = ValueNotifier(
    BrokerStatus.disconnected,
  );
  @override
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  final _states = StreamController<AlarmState>.broadcast(sync: true);
  final _motions = StreamController<MotionEvent>.broadcast(sync: true);
  final _availability = StreamController<DeviceAvailability>.broadcast(
    sync: true,
  );
  final _sensorStates = StreamController<Map<Sensor, bool>>.broadcast(
    sync: true,
  );

  final List<AlarmCommand> sentCommands = [];
  bool acceptCommands = true;
  int connectCalls = 0;

  @override
  Stream<AlarmState> get alarmStates => _states.stream;
  @override
  Stream<MotionEvent> get motions => _motions.stream;
  @override
  Stream<DeviceAvailability> get availability => _availability.stream;
  @override
  Stream<Map<Sensor, bool>> get sensorStates => _sensorStates.stream;

  @override
  Future<void> connect() async => connectCalls++;

  @override
  bool sendCommand(AlarmCommand command) {
    if (!acceptCommands) return false;
    sentCommands.add(command);
    return true;
  }

  @override
  void dispose() {
    _states.close();
    _motions.close();
    _availability.close();
    _sensorStates.close();
  }

  // ── Simulation des messages ────────────────────────────────────────────────

  void brokerConnected() => status.value = BrokerStatus.connected;
  void publishState(AlarmState state) => _states.add(state);
  void publishAvailability(DeviceAvailability value) =>
      _availability.add(value);
  void publishMotion(
    int uptimeMs, {
    DateTime? at,
    Sensor sensor = Sensor.pirSalon,
  }) => _motions.add(
    MotionEvent(
      uptimeMs: uptimeMs,
      receivedAt: at ?? DateTime(2026, 10, 19, 10),
      sensor: sensor,
    ),
  );
  void publishSensors(Map<Sensor, bool> states) => _sensorStates.add(states);

  /// Broker connecté + ESP32 en ligne dans l'état donné (messages retained).
  void goLive(AlarmState state) {
    brokerConnected();
    publishAvailability(DeviceAvailability.online);
    publishState(state);
  }
}
