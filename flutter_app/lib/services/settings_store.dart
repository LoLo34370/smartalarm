import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/mqtt_config.dart';

/// Persistance des réglages de l'application (remplacée par une version en
/// mémoire dans les tests).
abstract interface class SettingsStore {
  /// Broker saisi dans l'application, `null` si aucun (configuration de build).
  Future<MqttConfig?> loadBrokerConfig();
  Future<void> saveBrokerConfig(MqttConfig? config);

  Future<bool> loadRequireAuthToDisarm();
  Future<void> saveRequireAuthToDisarm(bool value);
}

/// Les identifiants MQTT vont dans le stockage chiffré du système
/// (Trousseau iOS, Keystore Android) ; le reste dans les préférences.
class DeviceSettingsStore implements SettingsStore {
  DeviceSettingsStore({FlutterSecureStorage? secureStorage, SharedPreferencesAsync? preferences})
      : _secure = secureStorage ?? const FlutterSecureStorage(),
        _preferences = preferences ?? SharedPreferencesAsync();

  static const _brokerKey = 'smartalarm.broker.v1';
  static const _requireAuthKey = 'smartalarm.requireAuthToDisarm';

  final FlutterSecureStorage _secure;
  final SharedPreferencesAsync _preferences;

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

  @override
  Future<bool> loadRequireAuthToDisarm() async =>
      await _preferences.getBool(_requireAuthKey) ?? false;

  @override
  Future<void> saveRequireAuthToDisarm(bool value) =>
      _preferences.setBool(_requireAuthKey, value);
}
