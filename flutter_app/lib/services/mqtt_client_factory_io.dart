import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/mqtt_config.dart';

/// Client natif (Android…) : MQTT sur TLS. Le certificat du broker est validé
/// avec le magasin de certificats du système (ISRG Root X1 y figure).
MqttClient createPlatformMqttClient(MqttConfig config, String clientId) =>
    MqttServerClient.withPort(
      config.host,
      clientId,
      config.tlsPort,
      maxConnectionAttempts: 1,
    )..secure = true;
