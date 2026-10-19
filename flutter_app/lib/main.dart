import 'package:flutter/material.dart';

import 'config/app_theme.dart';
import 'config/mqtt_config.dart';
import 'controllers/alarm_controller.dart';
import 'screens/dashboard_screen.dart';
import 'services/alarm_connection.dart';
import 'services/mqtt_service.dart';

void main() {
  runApp(SmartAlarmApp(connection: MqttService(config: MqttConfig.fromEnvironment())));
}

class SmartAlarmApp extends StatefulWidget {
  const SmartAlarmApp({super.key, required this.connection});

  final AlarmConnection connection;

  @override
  State<SmartAlarmApp> createState() => _SmartAlarmAppState();
}

class _SmartAlarmAppState extends State<SmartAlarmApp> {
  late final AlarmController _controller = AlarmController(widget.connection)..start();

  @override
  void dispose() {
    _controller.dispose();
    widget.connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAlarm',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DashboardScreen(controller: _controller),
    );
  }
}
