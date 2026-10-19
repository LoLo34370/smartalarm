import 'package:flutter/foundation.dart';

import '../models/alarm_models.dart';

/// État de la connexion de l'application au broker MQTT.
enum BrokerStatus { disconnected, connecting, connected, reconnecting }

/// Ce dont le contrôleur a besoin pour dialoguer avec l'ESP32.
/// Implémenté par `MqttService` ; remplacé par un faux dans les tests.
abstract interface class AlarmConnection {
  ValueListenable<BrokerStatus> get status;
  ValueListenable<String?> get lastError;
  Stream<AlarmState> get alarmStates;
  Stream<MotionEvent> get motions;
  Stream<DeviceAvailability> get availability;

  Future<void> connect();
  bool sendCommand(AlarmCommand command);
  void dispose();
}
