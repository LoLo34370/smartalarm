import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../config/mqtt_config.dart';
import '../models/alarm_models.dart';
import '../models/mqtt_topics.dart';
import 'mqtt_client_factory.dart';

/// État de la connexion de l'application au broker MQTT.
enum BrokerStatus { disconnected, connecting, connected, reconnecting }

typedef MqttClientBuilder = MqttClient Function(MqttConfig config, String clientId);

/// Connexion MQTT de l'application : connexion, reconnexion, abonnements,
/// décodage des messages de l'ESP32 et envoi des commandes.
///
/// Le service ne stocke AUCUN état métier : il relaie uniquement ce que
/// l'ESP32 publie. Grâce aux messages retained, chaque (re)connexion
/// redélivre immédiatement le dernier `state` et la dernière `availability`.
class MqttService {
  MqttService({required MqttConfig config, MqttClientBuilder? clientBuilder})
      : _config = config,
        _topics = MqttTopics(config.topicBase),
        _clientBuilder = clientBuilder ?? createPlatformMqttClient,
        clientId = 'smartalarm-flutter-${_randomSuffix()}';

  static const int keepAliveSeconds = 20;
  static const int connectTimeoutMs = 8000;
  static const Duration maxRetryDelay = Duration(seconds: 30);

  final MqttConfig _config;
  final MqttTopics _topics;
  final MqttClientBuilder _clientBuilder;

  /// Identifiant client unique par lancement (plusieurs onglets possibles,
  /// et jamais le même que l'ESP32).
  final String clientId;

  final ValueNotifier<BrokerStatus> status = ValueNotifier(BrokerStatus.disconnected);

  /// Dernière erreur lisible par l'utilisateur, `null` si tout va bien.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  final _alarmStates = StreamController<AlarmState>.broadcast();
  final _motions = StreamController<MotionEvent>.broadcast();
  final _availability = StreamController<DeviceAvailability>.broadcast();

  Stream<AlarmState> get alarmStates => _alarmStates.stream;
  Stream<MotionEvent> get motions => _motions.stream;
  Stream<DeviceAvailability> get availability => _availability.stream;

  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSubscription;
  Timer? _retryTimer;
  int _failedAttempts = 0;
  bool _wantConnected = false;
  bool _disposed = false;

  bool get isConnected => status.value == BrokerStatus.connected;

  /// Démarre la connexion. En cas d'échec, réessaie automatiquement avec un
  /// délai croissant (2 s, 4 s, 8 s… plafonné à 30 s) jusqu'à [disconnect].
  Future<void> connect() async {
    if (_disposed || _wantConnected) return;
    if (!_config.isComplete) {
      lastError.value = 'Configuration MQTT incomplète : ${_config.missingKeys.join(', ')}. '
          'Lancez l\'application avec --dart-define-from-file=config/dart_defines.json';
      return;
    }
    _wantConnected = true;
    await _attemptConnection();
  }

  /// Déconnexion volontaire : arrête aussi les tentatives de reconnexion.
  void disconnect() {
    _wantConnected = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failedAttempts = 0;
    _releaseClient();
    _setStatus(BrokerStatus.disconnected);
  }

  /// Publie une commande (QoS 1, jamais retained). L'état affiché ne change
  /// PAS ici : il changera quand l'ESP32 publiera son nouvel état.
  /// Retourne `false` si la commande n'a pas pu être envoyée.
  bool sendCommand(AlarmCommand command) {
    final client = _client;
    if (client == null || !isConnected) return false;
    final payload = MqttClientPayloadBuilder()..addUTF8String(command.toPayload());
    try {
      client.publishMessage(_topics.command, MqttQos.atLeastOnce, payload.payload!);
      return true;
    } on Exception catch (error) {
      lastError.value = 'Échec de l\'envoi de la commande ${command.wireValue} : $error';
      return false;
    }
  }

  void dispose() {
    if (_disposed) return;
    disconnect();
    _disposed = true;
    _alarmStates.close();
    _motions.close();
    _availability.close();
    status.dispose();
    lastError.dispose();
  }

  // ── Connexion ────────────────────────────────────────────────────────────

  Future<void> _attemptConnection() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_wantConnected || _disposed) return;

    _releaseClient();
    final client = _clientBuilder(_config, clientId)
      ..setProtocolV311()
      ..keepAlivePeriod = keepAliveSeconds // 0 par défaut = coupures non détectées
      ..connectTimeoutPeriod = connectTimeoutMs
      ..autoReconnect = true // prend le relais après une 1re connexion réussie
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    client
      ..onAutoReconnect = _onAutoReconnect
      ..onAutoReconnected = _onAutoReconnected;
    _client = client;
    _setStatus(_failedAttempts == 0 ? BrokerStatus.connecting : BrokerStatus.reconnecting);

    Object? connectError;
    try {
      await client.connect(_config.username, _config.password);
    } on Exception catch (error) {
      connectError = error;
    }

    // Déconnexion ou nouvelle tentative pendant l'attente : on abandonne celle-ci.
    if (!identical(client, _client) || !_wantConnected) return;

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      _failedAttempts = 0;
      lastError.value = null;
      // connect() recrée le flux des messages : on s'y (ré)abonne à chaque fois.
      _updatesSubscription = client.updates?.listen(_onMessages);
      for (final topic in _topics.subscriptions) {
        client.subscribe(topic, MqttQos.atLeastOnce);
      }
      _setStatus(BrokerStatus.connected);
      return;
    }

    _failedAttempts++;
    final delay = _retryDelay(_failedAttempts);
    lastError.value = '${_describeFailure(client.connectionStatus, connectError)} '
        'Nouvel essai dans ${delay.inSeconds} s.';
    _setStatus(BrokerStatus.disconnected);
    _retryTimer = Timer(delay, _attemptConnection);
  }

  void _onAutoReconnect() {
    lastError.value = 'Connexion au broker perdue, reconnexion en cours…';
    _setStatus(BrokerStatus.reconnecting);
  }

  void _onAutoReconnected() {
    // Les abonnements sont rétablis automatiquement et le broker renvoie les
    // messages retained : l'état affiché se resynchronise tout seul.
    lastError.value = null;
    _setStatus(BrokerStatus.connected);
  }

  void _releaseClient() {
    _updatesSubscription?.cancel();
    _updatesSubscription = null;
    final client = _client;
    _client = null;
    if (client == null) return;
    client
      ..autoReconnect = false
      ..onAutoReconnect = null
      ..onAutoReconnected = null;
    try {
      client.disconnect();
    } on Exception {
      // Déjà déconnecté : rien à libérer de plus.
    }
  }

  // ── Réception ────────────────────────────────────────────────────────────

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final publish = message.payload;
      if (publish is! MqttPublishMessage) continue;
      final payload = utf8.decode(publish.payload.message, allowMalformed: true);
      _dispatch(message.topic, payload);
    }
  }

  void _dispatch(String topic, String payload) {
    if (_disposed) return;
    if (topic == _topics.state) {
      final state = AlarmState.tryParse(payload);
      if (state != null) _alarmStates.add(state);
    } else if (topic == _topics.motion) {
      final event = MotionEvent.tryParse(payload);
      if (event != null) _motions.add(event);
    } else if (topic == _topics.availability) {
      _availability.add(DeviceAvailability.parse(payload));
    }
  }

  // ── Utilitaires ──────────────────────────────────────────────────────────

  void _setStatus(BrokerStatus value) {
    if (!_disposed) status.value = value;
  }

  static Duration _retryDelay(int failedAttempts) {
    final seconds = 2 << min(failedAttempts - 1, 4); // 2, 4, 8, 16, 32
    final delay = Duration(seconds: seconds);
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }

  static String _describeFailure(MqttClientConnectionStatus? status, Object? error) {
    switch (status?.returnCode) {
      case MqttConnectReturnCode.badUsernameOrPassword:
      case MqttConnectReturnCode.notAuthorized:
        return 'Identifiants MQTT refusés par le broker.';
      case MqttConnectReturnCode.brokerUnavailable:
        return 'Broker MQTT indisponible.';
      default:
        return error == null
            ? 'Connexion au broker impossible.'
            : 'Broker injoignable (${error.runtimeType}).';
    }
  }

  static String _randomSuffix() =>
      Random().nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
}
