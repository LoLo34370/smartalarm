import 'package:flutter/foundation.dart';

import '../config/mqtt_config.dart';
import '../services/device_authenticator.dart';
import '../services/settings_store.dart';

/// Réglages modifiables depuis l'application.
///
/// Le broker saisi dans l'écran Réglages a priorité sur celui fourni au build
/// (`--dart-define`). On peut donc changer de cluster HiveMQ sans recompiler.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsStore store,
    required DeviceAuthenticator authenticator,
    required this.buildBrokerConfig,
  })  : _store = store,
        _authenticator = authenticator;

  final SettingsStore _store;
  final DeviceAuthenticator _authenticator;

  /// Configuration fournie à la compilation (peut être incomplète).
  final MqttConfig buildBrokerConfig;

  MqttConfig? _savedBrokerConfig;
  bool _requireAuthToDisarm = false;
  bool _authAvailable = false;

  /// Broker saisi dans l'application, `null` si on utilise celui du build.
  MqttConfig? get savedBrokerConfig => _savedBrokerConfig;

  /// Broker réellement utilisé par l'application.
  MqttConfig get brokerConfig => _savedBrokerConfig ?? buildBrokerConfig;

  bool get usesAppBrokerConfig => _savedBrokerConfig != null;

  /// Demander Face ID / Touch ID / code avant d'envoyer DISARM.
  bool get requireAuthToDisarm => _requireAuthToDisarm && _authAvailable;

  /// L'appareil propose-t-il une authentification locale ? (faux sur le web)
  bool get authAvailable => _authAvailable;

  /// Lit les réglages enregistrés. Un stockage illisible ne bloque pas le
  /// démarrage : on garde alors les valeurs par défaut.
  Future<void> load() async {
    try {
      _savedBrokerConfig = await _store.loadBrokerConfig();
      _requireAuthToDisarm = await _store.loadRequireAuthToDisarm();
    } on Exception catch (error) {
      debugPrint('Réglages illisibles, valeurs par défaut utilisées : $error');
    }
    _authAvailable = await _authenticator.isAvailable();
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

  /// Active ou désactive la protection du désarmement. L'activation demande
  /// une première authentification, pour vérifier qu'elle fonctionne bien.
  /// Retourne `false` si l'utilisateur n'a pas été reconnu.
  Future<bool> setRequireAuthToDisarm(bool value) async {
    if (value && !_authAvailable) return false;
    if (value &&
        !await _authenticator.authenticate('Confirmez pour protéger la désactivation de l\'alarme')) {
      return false;
    }
    await _store.saveRequireAuthToDisarm(value);
    _requireAuthToDisarm = value;
    notifyListeners();
    return true;
  }
}
