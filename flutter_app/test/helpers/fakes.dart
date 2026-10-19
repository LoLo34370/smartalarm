import 'package:smartalarm/config/mqtt_config.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/services/journal_store.dart';
import 'package:smartalarm/services/settings_store.dart';

/// Journal stocké en mémoire.
class MemoryJournalStore implements JournalStore {
  MemoryJournalStore([List<AlarmEvent>? initial]) : saved = [...?initial];

  List<AlarmEvent> saved;
  int saveCalls = 0;

  @override
  Future<List<AlarmEvent>> load() async => List.of(saved);

  @override
  Future<void> save(List<AlarmEvent> events) async {
    saveCalls++;
    saved = List.of(events);
  }
}

/// Réglages stockés en mémoire.
class MemorySettingsStore implements SettingsStore {
  MqttConfig? broker;

  @override
  Future<MqttConfig?> loadBrokerConfig() async => broker;
  @override
  Future<void> saveBrokerConfig(MqttConfig? config) async => broker = config;
}

const testBrokerConfig = MqttConfig(
  host: 'build.s1.eu.hivemq.cloud',
  username: 'flutter',
  password: 'secret',
);
