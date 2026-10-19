import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/widgets/formatters.dart';

void main() {
  group('AlarmEvent', () {
    test('aller-retour JSON pour le stockage', () {
      final event = AlarmEvent(
        kind: AlarmEventKind.motion,
        at: DateTime(2026, 10, 19, 14, 5, 9),
        uptimeMs: 42000,
      );
      final back = AlarmEvent.tryFromJson(event.toJson())!;
      expect(back.kind, AlarmEventKind.motion);
      expect(back.at, event.at);
      expect(back.uptimeMs, 42000);
    });

    test('ignore une entrée illisible', () {
      expect(AlarmEvent.tryFromJson({'kind': 'BOOM', 'at': '2026-10-19'}), isNull);
      expect(AlarmEvent.tryFromJson({'kind': 'ARMED'}), isNull);
      expect(AlarmEvent.tryFromJson('texte'), isNull);
    });
  });

  group('formatDay', () {
    final now = DateTime(2026, 10, 19, 15);
    test('aujourd\'hui, hier, puis date en français', () {
      expect(formatDay(DateTime(2026, 10, 19, 8), now: now), 'Aujourd\'hui');
      expect(formatDay(DateTime(2026, 10, 18, 23), now: now), 'Hier');
      expect(formatDay(DateTime(2026, 10, 12), now: now), 'lundi 12 octobre');
      expect(formatDay(DateTime(2025, 12, 25), now: now), 'jeudi 25 décembre 2025');
    });
  });
}
