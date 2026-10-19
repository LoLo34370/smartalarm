import 'package:mqtt_client/mqtt_client.dart';

import '../config/mqtt_config.dart';

MqttClient createPlatformMqttClient(MqttConfig config, String clientId) =>
    throw UnsupportedError('Aucun client MQTT disponible pour cette plateforme.');
