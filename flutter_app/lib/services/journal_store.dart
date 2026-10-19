import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm_event.dart';

/// Persistance du journal d'activité (remplacée par une version en mémoire
/// dans les tests).
abstract interface class JournalStore {
  /// Entrées enregistrées, la plus récente en premier.
  Future<List<AlarmEvent>> load();
  Future<void> save(List<AlarmEvent> events);
}

/// Journal stocké localement sur l'appareil (UserDefaults sur iOS,
/// SharedPreferences sur Android, localStorage sur le web).
class SharedPreferencesJournalStore implements JournalStore {
  SharedPreferencesJournalStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'smartalarm.journal.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<AlarmEvent>> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map(AlarmEvent.tryFromJson).nonNulls.toList();
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> save(List<AlarmEvent> events) =>
      _preferences.setString(_key, jsonEncode([for (final e in events) e.toJson()]));
}
