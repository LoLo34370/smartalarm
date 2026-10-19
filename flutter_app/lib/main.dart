import 'package:flutter/material.dart';

import 'config/mqtt_config.dart';
import 'screens/mqtt_debug_screen.dart';
import 'services/mqtt_service.dart';

void main() {
  runApp(SmartAlarmApp(service: MqttService(config: MqttConfig.fromEnvironment())));
}

class SmartAlarmApp extends StatefulWidget {
  const SmartAlarmApp({super.key, required this.service});

  final MqttService service;

  @override
  State<SmartAlarmApp> createState() => _SmartAlarmAppState();
}

class _SmartAlarmAppState extends State<SmartAlarmApp> {
  @override
  void dispose() {
    widget.service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartAlarm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      ),
      home: MqttDebugScreen(service: widget.service),
    );
  }
}
