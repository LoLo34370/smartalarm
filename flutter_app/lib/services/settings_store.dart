import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/mqtt_config.dart';

/// Persistance des réglages de l'application (remplacée par une version en
/// mémoire dans les tests).
abstract interface class SettingsStore {
  /// Broker saisi dans l'application, `null` si aucun (configuration de build).
  Future<MqttConfig?> loadBrokerConfig();
  Future<void> saveBrokerConfig(MqttConfig? config);
}

/// Les identifiants MQTT vont dans le stockage chiffré du système
/// (Trousseau iOS, Keystore Android).
class DeviceSettingsStore implements SettingsStore {
  DeviceSettingsStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _brokerKey = 'smartalarm.broker.v1';

  final FlutterSecureStorage _secure;

  @override
  Future<MqttConfig?> loadBrokerConfig() async {
    final raw = await _secure.read(key: _brokerKey);
    if (raw == null) return null;
    try {
      return MqttConfig.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveBrokerConfig(MqttConfig? config) => config == null
      ? _secure.delete(key: _brokerKey)
      : _secure.write(key: _brokerKey, value: jsonEncode(config.toJson()));
}
