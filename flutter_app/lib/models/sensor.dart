import 'dart:convert';

import 'alarm_models.dart';

/// Zone d'un capteur : le mode nuit ne surveille que le périmètre.
enum SensorZone { perimeter, interior }

/// Capteurs câblés sur l'ESP32 (voir docs/architecture.md).
enum Sensor {
  pirSalon('pir_salon', 'Mouvement salon', SensorZone.interior, isContact: false),
  door('door', 'Porte d\'entrée', SensorZone.perimeter, isContact: true),
  window('window', 'Fenêtre', SensorZone.perimeter, isContact: true);

  const Sensor(this.wireId, this.label, this.zone, {required this.isContact});

  /// Identifiant dans les messages MQTT.
  final String wireId;
  final String label;
  final SensorZone zone;

  /// Contact d'ouverture (porte, fenêtre), sinon détecteur de mouvement.
  final bool isContact;

  static Sensor? tryParse(Object? wireId) =>
      values.where((s) => s.wireId == wireId).firstOrNull;

  /// Le capteur déclenche-t-il l'alarme dans cet état ? (même règle que l'ESP32)
  bool isMonitoredIn(AlarmState? state) => switch (state) {
        AlarmState.armed => true,
        AlarmState.armedNight => zone == SensorZone.perimeter,
        AlarmState.disarmed || AlarmState.triggered || null => false,
      };
}

/// Analyse `{"pir_salon":"IDLE","door":"OPEN","window":"CLOSED"}` publié
/// en retained sur `<base>/sensors`. Valeur `true` = capteur actif (mouvement
/// en cours, porte ou fenêtre ouverte). Les clés inconnues sont ignorées.
Map<Sensor, bool>? tryParseSensorStates(String payload) {
  Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final states = <Sensor, bool>{};
  for (final MapEntry(:key, :value) in decoded.entries) {
    final sensor = Sensor.tryParse(key);
    final active = switch (value) {
      'OPEN' || 'ACTIVE' => true,
      'CLOSED' || 'IDLE' => false,
      _ => null,
    };
    if (sensor != null && active != null) states[sensor] = active;
  }
  return states;
}
