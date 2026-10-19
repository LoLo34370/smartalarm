import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../config/mqtt_config.dart';

/// Client navigateur : WebSocket sécurisée. Le certificat du broker est
/// vérifié par le navigateur lui-même (pas de contournement possible).
MqttClient createPlatformMqttClient(MqttConfig config, String clientId) =>
    MqttBrowserClient.withPort(
      config.webSocketUrl,
      clientId,
      config.webSocketPort,
      maxConnectionAttempts: 1,
    )..websocketProtocols = MqttClientConstants.protocolsSingleDefault;
