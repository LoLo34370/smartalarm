import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/alarm_models.dart';
import '../services/alarm_connection.dart';

/// Ce que le capteur PIR signifie pour l'utilisateur, déduit de l'état publié.
enum PirStatus { inactive, monitoring, motionDetected }

/// État de l'écran, construit UNIQUEMENT à partir des messages MQTT.
///
/// Un clic sur « Activer » n'arme rien localement : il envoie une commande et
/// passe en attente ([pendingCommand]) jusqu'à ce que l'ESP32 publie son état.
class AlarmController extends ChangeNotifier {
  AlarmController(
    this._connection, {
    this.commandTimeout = const Duration(seconds: 10),
    this.historyLimit = 20,
  });

  final AlarmConnection _connection;

  /// Délai au-delà duquel une commande non confirmée est signalée.
  final Duration commandTimeout;

  /// Nombre maximal de détections conservées pendant la session.
  final int historyLimit;

  final List<StreamSubscription<Object>> _subscriptions = [];
  final List<MotionEvent> _motionHistory = [];
  Timer? _commandTimer;
  bool _started = false;
  bool _disposed = false;

  AlarmState? _alarmState;
  DeviceAvailability _availability = DeviceAvailability.unknown;
  AlarmCommand? _pendingCommand;
  String? _commandWarning;

  // ── État exposé à l'interface ──────────────────────────────────────────────

  BrokerStatus get brokerStatus => _connection.status.value;
  String? get connectionError => _connection.lastError.value;

  /// Dernier état publié par l'ESP32, `null` tant qu'aucun n'a été reçu.
  AlarmState? get alarmState => _alarmState;
  DeviceAvailability get availability => _availability;

  /// Commande envoyée et pas encore confirmée par l'ESP32.
  AlarmCommand? get pendingCommand => _pendingCommand;

  /// Avertissement lié à la dernière commande (non envoyée, non confirmée…).
  String? get commandWarning => _commandWarning;

  /// Détections reçues pendant la session, la plus récente en premier.
  List<MotionEvent> get motionHistory => List.unmodifiable(_motionHistory);

  bool get isBrokerConnected => brokerStatus == BrokerStatus.connected;
  bool get isDeviceOnline => _availability == DeviceAvailability.online;

  /// L'état affiché reflète-t-il l'ESP32 en temps réel ?
  bool get isLive => isBrokerConnected && isDeviceOnline;

  bool get isTriggered => _alarmState == AlarmState.triggered;
  bool get isSirenActive => isTriggered;

  /// Désarmé (ou inconnu) → proposer ARM ; armé ou déclenché → proposer DISARM.
  AlarmCommand get nextCommand => switch (_alarmState) {
        AlarmState.armed || AlarmState.triggered => AlarmCommand.disarm,
        AlarmState.disarmed || null => AlarmCommand.arm,
      };

  bool get canSendCommand => isLive && _pendingCommand == null;

  PirStatus get pirStatus => switch (_alarmState) {
        AlarmState.armed => PirStatus.monitoring,
        AlarmState.triggered => PirStatus.motionDetected,
        AlarmState.disarmed || null => PirStatus.inactive,
      };

  // ── Cycle de vie ───────────────────────────────────────────────────────────

  /// Branche les écouteurs puis lance la connexion MQTT.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _connection.status.addListener(_onConnectionChanged);
    _connection.lastError.addListener(_notify);
    _subscriptions.addAll([
      _connection.alarmStates.listen(_onAlarmState),
      _connection.availability.listen(_onAvailability),
      _connection.motions.listen(_onMotion),
    ]);
    _connection.connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _commandTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_started) {
      _connection.status.removeListener(_onConnectionChanged);
      _connection.lastError.removeListener(_notify);
    }
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Envoie [nextCommand]. L'état ne changera qu'à la confirmation de l'ESP32.
  void toggleAlarm() => sendCommand(nextCommand);

  void sendCommand(AlarmCommand command) {
    if (!canSendCommand) return;
    if (!_connection.sendCommand(command)) {
      _commandWarning = 'La commande ${_label(command)} n\'a pas pu être envoyée.';
      _notify();
      return;
    }
    _pendingCommand = command;
    _commandWarning = null;
    _commandTimer?.cancel();
    _commandTimer = Timer(commandTimeout, () {
      _pendingCommand = null;
      _commandWarning = 'L\'ESP32 n\'a pas confirmé la commande ${_label(command)} '
          '(${commandTimeout.inSeconds} s). Vérifiez qu\'il est bien en ligne.';
      _notify();
    });
    _notify();
  }

  void clearMotionHistory() {
    _motionHistory.clear();
    _notify();
  }

  // ── Messages MQTT ──────────────────────────────────────────────────────────

  void _onAlarmState(AlarmState state) {
    _alarmState = state;
    // L'ESP32 publie son état après chaque commande : c'est la confirmation.
    _clearPending();
    _notify();
  }

  void _onAvailability(DeviceAvailability value) {
    _availability = value;
    if (value == DeviceAvailability.offline && _pendingCommand != null) {
      _clearPending(warning: 'L\'ESP32 s\'est déconnecté avant de confirmer la commande.');
    }
    _notify();
  }

  void _onMotion(MotionEvent event) {
    _motionHistory.insert(0, event);
    if (_motionHistory.length > historyLimit) {
      _motionHistory.removeRange(historyLimit, _motionHistory.length);
    }
    _notify();
  }

  void _onConnectionChanged() {
    if (!isBrokerConnected && _pendingCommand != null) {
      _clearPending(warning: 'Connexion au broker perdue avant la confirmation de l\'ESP32.');
    }
    _notify();
  }

  void _clearPending({String? warning}) {
    _commandTimer?.cancel();
    _commandTimer = null;
    _pendingCommand = null;
    _commandWarning = warning;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _label(AlarmCommand command) => switch (command) {
        AlarmCommand.arm => 'd\'activation',
        AlarmCommand.disarm => 'de désactivation',
      };
}
