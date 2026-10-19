import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/config/mqtt_config.dart';
import 'package:smartalarm/controllers/settings_controller.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/widgets/formatters.dart';

import 'helpers/fakes.dart';

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

  group('MqttConfig', () {
    test('aller-retour JSON et égalité par valeur', () {
      const config = MqttConfig(
        host: 'abc.s1.eu.hivemq.cloud',
        username: 'u',
        password: 'p',
        topicBase: 'smartalarm/salon',
        tlsPort: 8883,
      );
      expect(MqttConfig.tryFromJson(config.toJson()), config);
      expect(config.deviceId, 'salon');
      expect(MqttConfig.tryFromJson({'host': 'h'}), isNull);
    });
  });

  group('SettingsController', () {
    late MemorySettingsStore store;
    late SettingsController settings;

    setUp(() async {
      store = MemorySettingsStore();
      settings = SettingsController(
        store: store,
        buildBrokerConfig: testBrokerConfig,
      );
    });

    test('utilise la configuration du build tant que rien n\'est saisi', () async {
      await settings.load();
      expect(settings.brokerConfig, testBrokerConfig);
      expect(settings.usesAppBrokerConfig, isFalse);
    });

    test('le broker saisi est prioritaire, persistant et réinitialisable', () async {
      await settings.load();
      const other = MqttConfig(host: 'new.hivemq.cloud', username: 'a', password: 'b');
      await settings.saveBrokerConfig(other);
      expect(settings.brokerConfig, other);
      expect(store.broker, other);

      final reloaded = SettingsController(
        store: store,
        buildBrokerConfig: testBrokerConfig,
      );
      await reloaded.load();
      expect(reloaded.brokerConfig, other);

      await settings.resetBrokerConfig();
      expect(settings.brokerConfig, testBrokerConfig);
      expect(store.broker, isNull);
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
