import 'alarm_models.dart';
import 'sensor.dart';

/// Type d'entrée du journal d'activité.
enum AlarmEventKind {
  armed('ARMED'),
  armedNight('ARMED_NIGHT'),
  disarmed('DISARMED'),
  triggered('TRIGGERED'),
  detection('MOTION');

  const AlarmEventKind(this.storageValue);

  final String storageValue;

  /// Entrée correspondant à un nouvel état publié par l'ESP32.
  static AlarmEventKind fromState(AlarmState state) => switch (state) {
        AlarmState.armed => armed,
        AlarmState.armedNight => armedNight,
        AlarmState.disarmed => disarmed,
        AlarmState.triggered => triggered,
      };
}

/// Entrée du journal : changement d'état confirmé par l'ESP32 ou détection.
///
/// Comme pour l'historique, l'horodatage est celui de la RÉCEPTION par
/// l'application (l'ESP32 n'a pas d'horloge réelle).
class AlarmEvent {
  const AlarmEvent({required this.kind, required this.at, this.uptimeMs, this.sensor});

  factory AlarmEvent.fromDetection(Detection detection) => AlarmEvent(
        kind: AlarmEventKind.detection,
        at: detection.receivedAt,
        uptimeMs: detection.uptimeMs,
        sensor: detection.sensor,
      );

  final AlarmEventKind kind;
  final DateTime at;

  /// `millis()` de l'ESP32, uniquement pour les détections.
  final int? uptimeMs;

  /// Capteur à l'origine d'une détection.
  final Sensor? sensor;

  Map<String, Object?> toJson() => {
        'kind': kind.storageValue,
        'at': at.toIso8601String(),
        if (uptimeMs != null) 'uptimeMs': uptimeMs,
        if (sensor != null) 'sensor': sensor!.wireId,
      };

  /// Retourne `null` pour une entrée illisible (stockage corrompu ou ancien).
  static AlarmEvent? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final kind = AlarmEventKind.values
        .where((k) => k.storageValue == json['kind'])
        .firstOrNull;
    final at = json['at'] is String ? DateTime.tryParse(json['at']! as String) : null;
    final uptime = json['uptimeMs'];
    if (kind == null || at == null) return null;
    return AlarmEvent(
      kind: kind,
      at: at,
      uptimeMs: uptime is int ? uptime : null,
      // Les détections enregistrées avant l'ajout des contacts viennent du PIR.
      sensor: Sensor.tryParse(json['sensor']) ??
          (kind == AlarmEventKind.detection ? Sensor.pirSalon : null),
    );
  }
}
