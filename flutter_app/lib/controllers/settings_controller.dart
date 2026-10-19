import 'package:flutter/foundation.dart';

import '../config/mqtt_config.dart';
import '../services/settings_store.dart';

/// Réglages modifiables depuis l'application.
///
/// Le broker saisi dans l'écran Réglages a priorité sur celui fourni au build
/// (`--dart-define`). On peut donc changer de cluster HiveMQ sans recompiler.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsStore store,
    required this.buildBrokerConfig,
  }) : _store = store;

  final SettingsStore _store;

  /// Configuration fournie à la compilation (peut être incomplète).
  final MqttConfig buildBrokerConfig;

  MqttConfig? _savedBrokerConfig;

  /// Broker saisi dans l'application, `null` si on utilise celui du build.
  MqttConfig? get savedBrokerConfig => _savedBrokerConfig;

  /// Broker réellement utilisé par l'application.
  MqttConfig get brokerConfig => _savedBrokerConfig ?? buildBrokerConfig;

  bool get usesAppBrokerConfig => _savedBrokerConfig != null;

  /// Lit les réglages enregistrés. Un stockage illisible ne bloque pas le
  /// démarrage : on garde alors les valeurs par défaut.
  Future<void> load() async {
    try {
      _savedBrokerConfig = await _store.loadBrokerConfig();
    } on Exception catch (error) {
      debugPrint('Réglages illisibles, valeurs par défaut utilisées : $error');
    }
    notifyListeners();
  }

  Future<void> saveBrokerConfig(MqttConfig config) async {
    await _store.saveBrokerConfig(config);
    _savedBrokerConfig = config;
    notifyListeners();
  }

  /// Revient à la configuration fournie au build.
  Future<void> resetBrokerConfig() async {
    await _store.saveBrokerConfig(null);
    _savedBrokerConfig = null;
    notifyListeners();
  }
}
