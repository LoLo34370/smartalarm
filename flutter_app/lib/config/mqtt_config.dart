/// Configuration MQTT injectée à la compilation via `--dart-define-from-file`.
///
/// ⚠️ Sur Flutter Web, ces valeurs (identifiants compris) sont embarquées dans
/// le JavaScript livré au navigateur : elles sont lisibles par l'utilisateur.
/// Acceptable uniquement pour une démonstration avec un identifiant dédié.
class MqttConfig {
  const MqttConfig({
    required this.host,
    required this.username,
    required this.password,
    this.webSocketPort = 8884,
    this.webSocketPath = '/mqtt',
    this.tlsPort = 8883,
    this.topicBase = 'smartalarm/demo01',
  });

  /// Lit les valeurs fournies par `--dart-define` / `--dart-define-from-file`.
  factory MqttConfig.fromEnvironment() => const MqttConfig(
        host: String.fromEnvironment('MQTT_HOST'),
        username: String.fromEnvironment('MQTT_USERNAME'),
        password: String.fromEnvironment('MQTT_PASSWORD'),
        webSocketPort: int.fromEnvironment('MQTT_WS_PORT', defaultValue: 8884),
        webSocketPath: String.fromEnvironment('MQTT_WS_PATH', defaultValue: '/mqtt'),
        tlsPort: int.fromEnvironment('MQTT_TLS_PORT', defaultValue: 8883),
        topicBase: String.fromEnvironment('MQTT_TOPIC_BASE', defaultValue: 'smartalarm/demo01'),
      );

  /// Nom d'hôte du cluster HiveMQ, sans schéma ni port.
  final String host;
  final String username;
  final String password;

  /// MQTT over Secure WebSocket (Flutter Web).
  final int webSocketPort;
  final String webSocketPath;

  /// MQTT over TLS (Android et autres plateformes natives).
  final int tlsPort;

  final String topicBase;

  /// Clés obligatoires absentes, pour afficher un message explicite.
  List<String> get missingKeys => [
        if (host.isEmpty) 'MQTT_HOST',
        if (username.isEmpty) 'MQTT_USERNAME',
        if (password.isEmpty) 'MQTT_PASSWORD',
      ];

  bool get isComplete => missingKeys.isEmpty;

  /// URL WSS utilisée par le client navigateur (le port est passé à part).
  String get webSocketUrl => 'wss://$host$webSocketPath';
}
