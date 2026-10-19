import 'dart:convert';

import 'sensor.dart';

/// États métier publiés par l'ESP32 (source de vérité) sur `<base>/state`.
enum AlarmState {
  disarmed('DISARMED'),
  armed('ARMED'),
  armedNight('ARMED_NIGHT'),
  triggered('TRIGGERED');

  const AlarmState(this.wireValue);

  final String wireValue;

  /// Armée, en mode total ou nuit (sans intrusion en cours).
  bool get isArmed => this == armed || this == armedNight;

  /// Analyse `{"state":"ARMED"}`. Retourne `null` si le payload est invalide
  /// (ou vide : purge d'un message retained).
  static AlarmState? tryParse(String payload) {
    final value = _readJsonString(payload, 'state');
    for (final state in values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

/// Commandes envoyées à l'ESP32 sur `<base>/command`.
enum AlarmCommand {
  arm('ARM'),
  armNight('ARM_NIGHT'),
  disarm('DISARM');

  const AlarmCommand(this.wireValue);

  final String wireValue;

  String toPayload() => jsonEncode({'command': wireValue});
}

/// Disponibilité de l'ESP32, publiée en retained (+ Last Will « offline »).
enum DeviceAvailability {
  unknown,
  online,
  offline;

  static DeviceAvailability parse(String payload) => switch (payload.trim()) {
        'online' => online,
        'offline' => offline,
        _ => unknown,
      };
}

/// Détection publiée par l'ESP32 sur `<base>/motion` : mouvement (PIR) ou
/// ouverture (porte, fenêtre).
class Detection {
  const Detection({required this.sensor, required this.uptimeMs, required this.receivedAt});

  /// Capteur à l'origine de la détection.
  final Sensor sensor;

  /// `millis()` de l'ESP32 au moment de la détection.
  final int uptimeMs;

  /// Horodatage côté application (l'ESP32 n'a pas d'horloge réelle).
  final DateTime receivedAt;

  /// Analyse `{"event":"OPENING_DETECTED","sensor":"door","uptimeMs":125000}`.
  static Detection? tryParse(String payload, {DateTime? receivedAt}) {
    final json = _decodeObject(payload);
    if (json == null) return null;
    if (json['event'] != 'MOTION_DETECTED' && json['event'] != 'OPENING_DETECTED') return null;
    final sensor = Sensor.tryParse(json['sensor']);
    final uptime = json['uptimeMs'];
    if (sensor == null || uptime is! int) return null;
    return Detection(sensor: sensor, uptimeMs: uptime, receivedAt: receivedAt ?? DateTime.now());
  }
}

Map<String, Object?>? _decodeObject(String payload) {
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String? _readJsonString(String payload, String key) {
  final value = _decodeObject(payload)?[key];
  return value is String ? value : null;
}
