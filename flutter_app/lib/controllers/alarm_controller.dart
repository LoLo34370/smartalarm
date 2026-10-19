import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/alarm_event.dart';
import '../models/alarm_models.dart';
import '../models/sensor.dart';
import '../services/alarm_connection.dart';
import '../services/device_authenticator.dart';
import '../services/journal_store.dart';

/// Ce qu'un capteur signifie pour l'utilisateur, déduit de l'état publié.
enum SensorStatus {
  /// Alarme désactivée : le capteur ne déclenche rien.
  inactive,

  /// Mode nuit : capteur intérieur volontairement ignoré.
  ignoredAtNight,

  /// Le capteur déclenche l'alarme.
  monitoring,

  /// Le capteur est à l'origine de l'intrusion en cours.
  intrusion,
}

/// État de l'écran, construit UNIQUEMENT à partir des messages MQTT.
///
/// Un clic sur « Activer » n'arme rien localement : il envoie une commande et
/// passe en attente ([pendingCommand]) jusqu'à ce que l'ESP32 publie son état.
///
/// Les changements d'état confirmés et les détections alimentent un journal
/// d'activité, conservé sur l'appareil entre deux lancements.
class AlarmController extends ChangeNotifier {
  AlarmController(
    this._connection, {
    this.commandTimeout = const Duration(seconds: 10),
    this.historyLimit = 200,
    JournalStore? journalStore,
    DeviceAuthenticator? authenticator,
    bool requireAuthToDisarm = false,
    this.onIntrusion,
    DateTime Function()? clock,
  })  : _journalStore = journalStore,
        _authenticator = authenticator,
        _requireAuthToDisarm = requireAuthToDisarm,
        _clock = clock ?? DateTime.now;

  final AlarmConnection _connection;
  final JournalStore? _journalStore;
  final DeviceAuthenticator? _authenticator;
  final DateTime Function() _clock;

  /// Délai au-delà duquel une commande non confirmée est signalée.
  final Duration commandTimeout;

  /// Nombre maximal d'entrées conservées dans le journal.
  final int historyLimit;

  /// Appelé quand l'alarme passe en TRIGGERED (vibration de l'appareil…).
  final VoidCallback? onIntrusion;

  final List<StreamSubscription<Object>> _subscriptions = [];
  final List<AlarmEvent> _journal = [];
  Timer? _commandTimer;
  bool _started = false;
  bool _disposed = false;
  bool _journalLoaded = false;
  bool _authenticating = false;
  bool _requireAuthToDisarm;

  AlarmState? _alarmState;
  DeviceAvailability _availability = DeviceAvailability.unknown;
  final Map<Sensor, bool> _sensorStates = {};
  Sensor? _intrusionSensor;
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

  /// Journal d'activité, l'entrée la plus récente en premier.
  List<AlarmEvent> get journal => List.unmodifiable(_journal);

  /// Dernière détection connue, tous capteurs confondus.
  AlarmEvent? get lastMotion =>
      _journal.where((e) => e.kind == AlarmEventKind.motion).firstOrNull;

  /// Dernière détection connue de ce capteur.
  AlarmEvent? lastDetection(Sensor sensor) => _journal
      .where((e) => e.kind == AlarmEventKind.motion && (e.sensor ?? Sensor.pirSalon) == sensor)
      .firstOrNull;

  /// Capteur actif (mouvement, ouverture), `null` tant que l'ESP32 ne l'a pas publié.
  bool? isSensorActive(Sensor sensor) => _sensorStates[sensor];

  /// Portes et fenêtres ouvertes : elles ne déclencheront l'alarme qu'à
  /// leur prochaine ouverture si on arme maintenant.
  List<Sensor> get openContacts =>
      [for (final s in Sensor.values) if (s.isContact && _sensorStates[s] == true) s];

  /// Capteur à l'origine de l'intrusion en cours, s'il est connu.
  Sensor? get intrusionSensor => isTriggered ? _intrusionSensor : null;

  SensorStatus sensorStatus(Sensor sensor) {
    if (isTriggered) {
      return sensor == _intrusionSensor ? SensorStatus.intrusion : SensorStatus.monitoring;
    }
    if (sensor.isMonitoredIn(_alarmState)) return SensorStatus.monitoring;
    return _alarmState == AlarmState.armedNight
        ? SensorStatus.ignoredAtNight
        : SensorStatus.inactive;
  }

  /// Une confirmation Face ID / Touch ID / code est demandée avant DISARM.
  bool get requireAuthToDisarm => _requireAuthToDisarm && _authenticator != null;
  set requireAuthToDisarm(bool value) {
    if (value == _requireAuthToDisarm) return;
    _requireAuthToDisarm = value;
    _notify();
  }

  /// La demande d'authentification système est affichée.
  bool get isAuthenticating => _authenticating;

  bool get isBrokerConnected => brokerStatus == BrokerStatus.connected;
  bool get isDeviceOnline => _availability == DeviceAvailability.online;

  /// L'état affiché reflète-t-il l'ESP32 en temps réel ?
  bool get isLive => isBrokerConnected && isDeviceOnline;

  bool get isTriggered => _alarmState == AlarmState.triggered;
  bool get isSirenActive => isTriggered;

  /// Désarmé (ou inconnu) → proposer ARM (ou ARM_NIGHT) ;
  /// armé ou déclenché → proposer DISARM.
  AlarmCommand get nextCommand => switch (_alarmState) {
        AlarmState.armed || AlarmState.armedNight || AlarmState.triggered =>
          AlarmCommand.disarm,
        AlarmState.disarmed || null => AlarmCommand.arm,
      };

  bool get canSendCommand => isLive && _pendingCommand == null && !_authenticating;

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
      _connection.sensorStates.listen(_onSensorStates),
    ]);
    _connection.connect();
    _loadJournal();
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
  Future<void> toggleAlarm() => requestCommand(nextCommand);

  /// Arme en mode nuit : seuls la porte et la fenêtre sont surveillées.
  Future<void> armNight() => requestCommand(AlarmCommand.armNight);

  /// Envoie [command]. Si la protection est activée, DISARM exige d'abord
  /// l'authentification.
  Future<void> requestCommand(AlarmCommand command) async {
    if (!canSendCommand) return;
    if (command == AlarmCommand.disarm && requireAuthToDisarm) {
      _authenticating = true;
      _notify();
      final confirmed = await _authenticator!
          .authenticate('Confirmez votre identité pour désactiver l\'alarme');
      _authenticating = false;
      if (_disposed) return;
      if (!confirmed) {
        _commandWarning = 'Désactivation annulée : identité non confirmée.';
        _notify();
        return;
      }
    }
    sendCommand(command);
  }

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

  void clearJournal() {
    _journal.clear();
    _persistJournal();
    _notify();
  }

  // ── Messages MQTT ──────────────────────────────────────────────────────────

  void _onAlarmState(AlarmState state) {
    final previous = _alarmState;
    _alarmState = state;
    // L'ESP32 publie son état après chaque commande : c'est la confirmation.
    _clearPending();
    // Le premier état reçu est l'instantané retained, pas un changement :
    // on ne journalise que les vraies transitions.
    if (previous != null && previous != state) {
      _record(AlarmEvent(kind: AlarmEventKind.fromState(state), at: _clock()));
    }
    if (state == AlarmState.triggered && previous != AlarmState.triggered) {
      onIntrusion?.call();
    }
    if (state != AlarmState.triggered) _intrusionSensor = null;
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
    // L'ESP32 publie la détection juste avant de passer en TRIGGERED.
    if (_alarmState?.isArmed ?? false) _intrusionSensor = event.sensor;
    _record(AlarmEvent.fromMotion(event));
    _notify();
  }

  void _onSensorStates(Map<Sensor, bool> states) {
    _sensorStates
      ..clear()
      ..addAll(states);
    _notify();
  }

  void _onConnectionChanged() {
    if (!isBrokerConnected && _pendingCommand != null) {
      _clearPending(warning: 'Connexion au broker perdue avant la confirmation de l\'ESP32.');
    }
    _notify();
  }

  // ── Journal ────────────────────────────────────────────────────────────────

  void _record(AlarmEvent event) {
    _journal.insert(0, event);
    _trimJournal();
    _persistJournal();
  }

  void _trimJournal() {
    if (_journal.length > historyLimit) {
      _journal.removeRange(historyLimit, _journal.length);
    }
  }

  Future<void> _loadJournal() async {
    final store = _journalStore;
    if (store == null) {
      _journalLoaded = true;
      return;
    }
    List<AlarmEvent> stored;
    try {
      stored = await store.load();
    } on Exception catch (error) {
      debugPrint('Journal illisible, ignoré : $error');
      stored = [];
    }
    if (_disposed) return;
    final receivedWhileLoading = _journal.isNotEmpty;
    // Les entrées reçues pendant le chargement sont plus récentes.
    _journal.addAll(stored);
    _trimJournal();
    _journalLoaded = true;
    if (receivedWhileLoading) _persistJournal();
    _notify();
  }

  /// Sauvegarde en arrière-plan. Pas avant la fin du chargement, sinon on
  /// écraserait le journal stocké par les seules entrées de la session.
  void _persistJournal() {
    final store = _journalStore;
    if (store == null || !_journalLoaded) return;
    store.save(List.of(_journal)).catchError(
          (Object error) => debugPrint('Échec de sauvegarde du journal : $error'),
        );
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
        AlarmCommand.armNight => 'd\'activation du mode nuit',
        AlarmCommand.disarm => 'de désactivation',
      };
}
