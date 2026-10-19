import 'package:flutter/material.dart';

import 'config/app_theme.dart';
import 'config/mqtt_config.dart';
import 'controllers/alarm_controller.dart';
import 'controllers/settings_controller.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'services/alarm_connection.dart';
import 'services/device_authenticator.dart';
import 'services/journal_store.dart';
import 'services/mqtt_service.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authenticator = LocalAuthAuthenticator();
  final settings = SettingsController(
    store: DeviceSettingsStore(),
    authenticator: authenticator,
    buildBrokerConfig: MqttConfig.fromEnvironment(),
  );
  await settings.load();
  runApp(SmartAlarmApp(
    settings: settings,
    journalStore: SharedPreferencesJournalStore(),
    authenticator: authenticator,
  ));
}

typedef AlarmConnectionFactory = AlarmConnection Function(MqttConfig config);

class SmartAlarmApp extends StatefulWidget {
  const SmartAlarmApp({
    super.key,
    required this.settings,
    this.journalStore,
    this.authenticator,
    this.connectionFactory = _mqttConnection,
  });

  final SettingsController settings;
  final JournalStore? journalStore;
  final DeviceAuthenticator? authenticator;

  /// Crée la connexion au broker (remplacée par un faux dans les tests).
  final AlarmConnectionFactory connectionFactory;

  static AlarmConnection _mqttConnection(MqttConfig config) => MqttService(config: config);

  @override
  State<SmartAlarmApp> createState() => _SmartAlarmAppState();
}

class _SmartAlarmAppState extends State<SmartAlarmApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late MqttConfig _brokerConfig;
  late AlarmConnection _connection;
  late AlarmController _controller;

  SettingsController get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _brokerConfig = _settings.brokerConfig;
    _createController();
    _settings.addListener(_onSettingsChanged);
  }

  void _createController() {
    _connection = widget.connectionFactory(_brokerConfig);
    _controller = AlarmController(
      _connection,
      journalStore: widget.journalStore,
      authenticator: widget.authenticator,
      requireAuthToDisarm: _settings.requireAuthToDisarm,
    )..start();
  }

  void _onSettingsChanged() {
    _controller.requireAuthToDisarm = _settings.requireAuthToDisarm;
    if (_settings.brokerConfig == _brokerConfig) return;

    // Nouveau broker : on repart d'une connexion neuve. L'ancienne est libérée
    // après le prochain affichage, quand plus aucun widget ne l'écoute.
    final oldController = _controller;
    final oldConnection = _connection;
    setState(() {
      _brokerConfig = _settings.brokerConfig;
      _createController();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
      oldConnection.dispose();
    });
  }

  void _openSettings() {
    _navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        settings: _settings,
        journalLength: _controller.journal.length,
        onClearJournal: _controller.clearJournal,
      ),
    ));
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _controller.dispose();
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAlarm',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DashboardScreen(
        controller: _controller,
        deviceId: _brokerConfig.deviceId,
        onOpenSettings: _openSettings,
      ),
    );
  }
}
