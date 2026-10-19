import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/services/journal_store.dart';

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
