import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Vérification de l'identité de l'utilisateur sur l'appareil
/// (Face ID, Touch ID, empreinte, ou à défaut le code de l'appareil).
abstract interface class DeviceAuthenticator {
  /// L'appareil permet-il une authentification locale ?
  Future<bool> isAvailable();

  /// Affiche la demande système. Retourne `true` si l'utilisateur est reconnu.
  Future<bool> authenticate(String reason);
}

class LocalAuthAuthenticator implements DeviceAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false; // local_auth n'existe pas sur le web
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (kIsWeb) return false;
    try {
      // biometricOnly: false → repli sur le code de l'appareil si Face ID échoue.
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }
}
