import 'dart:async';

import 'package:flutter/material.dart';

import '../models/alarm_models.dart';
import '../services/mqtt_service.dart';

/// Écran TEMPORAIRE de l'étape 5 : vérifie la connexion MQTT, la réception
/// de l'état de l'ESP32 et l'envoi de ARM / DISARM.
/// Il sera remplacé par le dashboard à l'étape 6.
class MqttDebugScreen extends StatefulWidget {
  const MqttDebugScreen({super.key, required this.service});

  final MqttService service;

  @override
  State<MqttDebugScreen> createState() => _MqttDebugScreenState();
}

class _MqttDebugScreenState extends State<MqttDebugScreen> {
  final List<String> _log = [];
  final List<StreamSubscription<Object>> _subscriptions = [];
  AlarmState? _alarmState;
  DeviceAvailability _availability = DeviceAvailability.unknown;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _subscriptions.addAll([
      service.alarmStates.listen((state) {
        setState(() => _alarmState = state);
        _addLog('state ← ${state.wireValue}');
      }),
      service.availability.listen((value) {
        setState(() => _availability = value);
        _addLog('availability ← ${value.name}');
      }),
      service.motions.listen((event) => _addLog('motion ← uptimeMs=${event.uptimeMs}')),
    ]);
    service.status.addListener(_onStatusChanged);
    service.connect();
  }

  @override
  void dispose() {
    widget.service.status.removeListener(_onStatusChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _onStatusChanged() => _addLog('broker : ${widget.service.status.value.name}');

  void _addLog(String line) {
    if (!mounted) return;
    final time = TimeOfDay.now().format(context);
    setState(() => _log.insert(0, '$time  $line'));
  }

  void _send(AlarmCommand command) {
    final sent = widget.service.sendCommand(command);
    _addLog(sent ? 'command → ${command.wireValue}' : 'command ${command.wireValue} NON envoyée');
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Scaffold(
      appBar: AppBar(title: const Text('SmartAlarm — test MQTT (étape 5)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder(
            valueListenable: service.status,
            builder: (context, status, _) => ListTile(
              leading: Icon(
                status == BrokerStatus.connected ? Icons.cloud_done : Icons.cloud_off,
                color: status == BrokerStatus.connected ? Colors.green : Colors.grey,
              ),
              title: Text('Broker MQTT : ${status.name}'),
              subtitle: Text('Client ID : ${service.clientId}'),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: service.lastError,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(error),
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text('ESP32 : ${_availability.name}'),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text('État de l\'alarme : ${_alarmState?.wireValue ?? 'inconnu'}'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: service.status,
            builder: (context, status, _) {
              final enabled = status == BrokerStatus.connected;
              return Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    onPressed: enabled ? () => _send(AlarmCommand.arm) : null,
                    child: const Text('ARM'),
                  ),
                  OutlinedButton(
                    onPressed: enabled ? () => _send(AlarmCommand.disarm) : null,
                    child: const Text('DISARM'),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 32),
          Text('Journal', style: Theme.of(context).textTheme.titleMedium),
          for (final line in _log)
            Text(line, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
