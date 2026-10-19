// Sélectionne à la compilation le client MQTT adapté à la plateforme :
// - Web     : MqttBrowserClient, MQTT over Secure WebSocket (wss://…:8884/mqtt)
// - Android : MqttServerClient, MQTT over TLS (port 8883)
// Le client navigateur ne peut pas ouvrir de socket TCP brute, d'où le WSS.
export 'mqtt_client_factory_stub.dart'
    if (dart.library.io) 'mqtt_client_factory_io.dart'
    if (dart.library.js_interop) 'mqtt_client_factory_web.dart';
