import 'package:flutter_test/flutter_test.dart';
import 'package:smartalarm/controllers/alarm_controller.dart';
import 'package:smartalarm/models/alarm_event.dart';
import 'package:smartalarm/models/alarm_models.dart';
import 'package:smartalarm/models/sensor.dart';
import 'package:smartalarm/services/alarm_connection.dart';

import 'helpers/fake_alarm_connection.dart';
import 'helpers/fakes.dart';

void main() {
  late FakeAlarmConnection connection;
  late AlarmController controller;

  setUp(() {
    connection = FakeAlarmConnection();
    controller = AlarmController(
      connection,
      commandTimeout: const Duration(milliseconds: 50),
      historyLimit: 3,
    )..start();
  });

  tearDown(() {
    controller.dispose();
    connection.dispose();
  });

  test('démarre la connexion et n\'invente aucun état', () {
    expect(connection.connectCalls, 1);
    expect(controller.alarmState, isNull);
    expect(controller.canSendCommand, isFalse);
    expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.inactive);
  });

  test('affiche l\'état retained reçu à la connexion', () {
    connection.goLive(AlarmState.armed);
    expect(controller.alarmState, AlarmState.armed);
    expect(controller.isLive, isTrue);
    expect(controller.nextCommand, AlarmCommand.disarm);
    expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.monitoring);
  });

  test(
    'ARM n\'arme rien localement : on attend la confirmation de l\'ESP32',
    () {
      connection.goLive(AlarmState.disarmed);

      controller.toggleAlarm();
      expect(connection.sentCommands, [AlarmCommand.arm]);
      expect(controller.pendingCommand, AlarmCommand.arm);
      expect(
        controller.alarmState,
        AlarmState.disarmed,
        reason: 'pas de changement artificiel',
      );
      expect(controller.canSendCommand, isFalse, reason: 'pas de double envoi');

      connection.publishState(AlarmState.armed);
      expect(controller.alarmState, AlarmState.armed);
      expect(controller.pendingCommand, isNull);
      expect(controller.commandWarning, isNull);
    },
  );

  test('signale une commande non confirmée après le délai', () async {
    connection.goLive(AlarmState.disarmed);
    controller.toggleAlarm();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, contains('n\'a pas confirmé'));
    expect(controller.alarmState, AlarmState.disarmed);
    expect(controller.canSendCommand, isTrue);
  });

  test('signale une commande qui n\'a pas pu être envoyée', () {
    connection.goLive(AlarmState.disarmed);
    connection.acceptCommands = false;
    controller.toggleAlarm();
    expect(controller.pendingCommand, isNull);
    expect(controller.commandWarning, contains('n\'a pas pu être envoyée'));
  });

  test('détection par pièce : seule la chambre passe en intrusion', () {
    connection.goLive(AlarmState.armed);
    connection.publishDetection(9000, sensor: Sensor.pirChambre);
    connection.publishState(AlarmState.triggered);

    expect(controller.intrusionRooms, [Room.chambre]);
    expect(controller.roomStatus(Room.chambre), SensorStatus.intrusion);
    expect(controller.roomStatus(Room.salon), SensorStatus.monitoring);
    expect(controller.roomStatus(Room.entree), SensorStatus.monitoring);
    expect(controller.sensorStatus(Sensor.pirChambre), SensorStatus.intrusion);
    expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.monitoring);

    connection.publishState(AlarmState.disarmed);
    expect(controller.intrusionRooms, isEmpty);
    expect(controller.roomStatus(Room.chambre), SensorStatus.inactive);
  });

  test('intrusion qui se déplace : salon puis chambre, les deux en alerte', () {
    connection.goLive(AlarmState.armed);
    connection.publishDetection(9000, sensor: Sensor.pirSalon);
    connection.publishState(AlarmState.triggered);
    expect(controller.intrusionRooms, [Room.salon]);
    expect(controller.roomStatus(Room.chambre), SensorStatus.monitoring);

    // Nouvelle détection publiée par l'ESP32 alors que la sirène sonne déjà.
    connection.publishDetection(16000, sensor: Sensor.pirChambre);
    expect(controller.intrusionSensor, Sensor.pirSalon, reason: 'déclencheur inchangé');
    expect(controller.intrusionRooms, [Room.salon, Room.chambre]);
    expect(controller.roomStatus(Room.salon), SensorStatus.intrusion);
    expect(controller.roomStatus(Room.chambre), SensorStatus.intrusion);
    expect(controller.roomStatus(Room.entree), SensorStatus.monitoring);

    connection.publishState(AlarmState.disarmed);
    expect(controller.intrusionRooms, isEmpty);
  });

  test('mode nuit : les PIR du salon et de la chambre sont ignorés', () {
    connection.goLive(AlarmState.armedNight);
    expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.ignoredAtNight);
    expect(controller.sensorStatus(Sensor.pirChambre), SensorStatus.ignoredAtNight);
    expect(controller.roomStatus(Room.salon), SensorStatus.ignoredAtNight);
    expect(controller.roomStatus(Room.chambre), SensorStatus.monitoring, reason: 'fenêtre');
  });

  test('intrusion : sirène active, mouvement historisé, DISARM proposé', () {
    connection.goLive(AlarmState.armed);
    connection.publishDetection(125000);
    connection.publishState(AlarmState.triggered);

    expect(controller.isTriggered, isTrue);
    expect(controller.isTriggered, isTrue);
    expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.intrusion);
    expect(controller.intrusionSensor, Sensor.pirSalon);
    expect(controller.nextCommand, AlarmCommand.disarm);
    expect(controller.lastDetection(Sensor.pirSalon)?.uptimeMs, 125000);

    controller.toggleAlarm();
    connection.publishState(AlarmState.disarmed);
    expect(connection.sentCommands.last, AlarmCommand.disarm);
    expect(controller.isTriggered, isFalse);
  });

  test('le journal garde les plus récentes, dans la limite fixée', () {
    connection.goLive(AlarmState.armed);
    for (final uptime in [1000, 2000, 3000, 4000]) {
      connection.publishDetection(uptime);
    }
    expect(controller.journal.map((e) => e.uptimeMs), [4000, 3000, 2000]);

    controller.clearJournal();
    expect(controller.journal, isEmpty);
  });

  test(
    'journal : transitions confirmées seulement, pas l\'instantané retained',
    () {
      connection.goLive(AlarmState.disarmed);
      expect(
        controller.journal,
        isEmpty,
        reason: 'état initial = pas un changement',
      );

      connection.publishState(AlarmState.armed);
      connection.publishState(
        AlarmState.armed,
      ); // republication sans changement
      connection.publishDetection(5000);
      connection.publishState(AlarmState.triggered);
      connection.publishState(AlarmState.disarmed);

      expect(controller.journal.map((e) => e.kind), [
        AlarmEventKind.disarmed,
        AlarmEventKind.triggered,
        AlarmEventKind.detection,
      ], reason: 'les 3 plus récentes (limite de ces tests) : ARMED est sorti');
    },
  );

  test('ESP32 hors ligne : commandes désactivées, dernier état conservé', () {
    connection.goLive(AlarmState.armed);
    connection.publishAvailability(DeviceAvailability.offline);

    expect(controller.isLive, isFalse);
    expect(controller.canSendCommand, isFalse);
    expect(controller.alarmState, AlarmState.armed);
    controller.toggleAlarm();
    expect(connection.sentCommands, isEmpty);
  });

  test(
    'perte du broker pendant une commande : attente annulée et signalée',
    () {
      connection.goLive(AlarmState.disarmed);
      controller.toggleAlarm();
      connection.status.value = BrokerStatus.reconnecting;

      expect(controller.pendingCommand, isNull);
      expect(controller.commandWarning, contains('Connexion au broker perdue'));
      expect(controller.canSendCommand, isFalse);
    },
  );

  test('reconnexion : l\'état retained resynchronise l\'affichage', () {
    connection.goLive(AlarmState.disarmed);
    connection.status.value = BrokerStatus.reconnecting;
    // Pendant la coupure, l'ESP32 a été armé par un autre client.
    connection.status.value = BrokerStatus.connected;
    connection.publishState(AlarmState.armed);

    expect(controller.alarmState, AlarmState.armed);
    expect(controller.isLive, isTrue);
  });

  group('capteurs et mode nuit', () {
    test('mode nuit : périmètre surveillé, PIR intérieur ignoré', () {
      connection.goLive(AlarmState.armedNight);
      expect(controller.sensorStatus(Sensor.door), SensorStatus.monitoring);
      expect(controller.sensorStatus(Sensor.window), SensorStatus.monitoring);
      expect(
        controller.sensorStatus(Sensor.pirSalon),
        SensorStatus.ignoredAtNight,
      );
      expect(controller.nextCommand, AlarmCommand.disarm);
    });

    test('ARM_NIGHT envoyé, puis journalisé à la confirmation', () {
      connection.goLive(AlarmState.disarmed);
      controller.armNight();
      expect(connection.sentCommands, [AlarmCommand.armNight]);
      expect(controller.pendingCommand, AlarmCommand.armNight);

      connection.publishState(AlarmState.armedNight);
      expect(controller.pendingCommand, isNull);
      expect(controller.journal.single.kind, AlarmEventKind.armedNight);
    });

    test('intrusion par la porte : capteur identifié puis oublié', () {
      connection.goLive(AlarmState.armedNight);
      connection.publishDetection(9000, sensor: Sensor.door);
      connection.publishState(AlarmState.triggered);

      expect(controller.intrusionSensor, Sensor.door);
      expect(controller.sensorStatus(Sensor.door), SensorStatus.intrusion);
      expect(controller.sensorStatus(Sensor.pirSalon), SensorStatus.monitoring);
      expect(controller.lastDetection(Sensor.door)?.uptimeMs, 9000);
      expect(controller.lastDetection(Sensor.window), isNull);

      connection.publishState(AlarmState.disarmed);
      expect(controller.intrusionSensor, isNull);
    });

    test('état en direct des capteurs et contacts ouverts', () {
      connection.goLive(AlarmState.disarmed);
      expect(controller.isSensorActive(Sensor.window), isNull);

      connection.publishSensors({
        Sensor.pirSalon: true,
        Sensor.door: false,
        Sensor.window: true,
      });
      expect(controller.isSensorActive(Sensor.pirSalon), isTrue);
      expect(controller.openContacts, [Sensor.window]);
    });
  });

  group('avec persistance, authentification et vibration', () {
    late FakeAlarmConnection conn;
    late MemoryJournalStore store;
    late FakeAuthenticator auth;
    late int intrusions;
    AlarmController? ctrl;

    setUp(() {
      conn = FakeAlarmConnection();
      store = MemoryJournalStore([
        AlarmEvent(kind: AlarmEventKind.armed, at: DateTime(2026, 10, 18, 9)),
      ]);
      auth = FakeAuthenticator();
      intrusions = 0;
    });

    tearDown(() {
      ctrl?.dispose();
      conn.dispose();
    });

    AlarmController build({bool requireAuth = false}) =>
        ctrl = AlarmController(
          conn,
          journalStore: store,
          authenticator: auth,
          requireAuthToDisarm: requireAuth,
          onIntrusion: () => intrusions++,
          clock: () => DateTime(2026, 10, 19, 12),
        )..start();

    test(
      'recharge le journal enregistré et y ajoute les nouvelles entrées',
      () async {
        final c = build();
        // Entrée reçue avant la fin du chargement : elle doit rester en tête.
        conn.publishDetection(1000, at: DateTime(2026, 10, 19, 11));
        await pumpEventQueue();

        expect(c.journal.map((e) => e.kind), [
          AlarmEventKind.detection,
          AlarmEventKind.armed,
        ]);
        expect(store.saved.length, 2, reason: 'rien de perdu à la sauvegarde');

        conn.goLive(AlarmState.armed);
        conn.publishState(AlarmState.disarmed);
        await pumpEventQueue();
        expect(store.saved.first.kind, AlarmEventKind.disarmed);
        expect(store.saved.first.at, DateTime(2026, 10, 19, 12));
      },
    );

    test('vibre une seule fois par intrusion', () async {
      build();
      conn.goLive(AlarmState.armed);
      conn.publishState(AlarmState.triggered);
      conn.publishState(AlarmState.triggered);
      expect(intrusions, 1);
      conn.publishState(AlarmState.disarmed);
      conn.publishState(AlarmState.armed);
      conn.publishState(AlarmState.triggered);
      expect(intrusions, 2);
    });

    test(
      'DISARM protégé : envoyé seulement si l\'identité est confirmée',
      () async {
        final c = build(requireAuth: true);
        conn.goLive(AlarmState.armed);

        auth.accept = false;
        await c.toggleAlarm();
        expect(conn.sentCommands, isEmpty);
        expect(c.commandWarning, contains('identité non confirmée'));
        expect(c.canSendCommand, isTrue);

        auth.accept = true;
        await c.toggleAlarm();
        expect(conn.sentCommands, [AlarmCommand.disarm]);
        expect(auth.reasons, hasLength(2));
      },
    );

    test('ARM n\'exige jamais d\'authentification', () async {
      final c = build(requireAuth: true);
      conn.goLive(AlarmState.disarmed);
      await c.toggleAlarm();
      expect(conn.sentCommands, [AlarmCommand.arm]);
      expect(auth.reasons, isEmpty);
    });
  });
}
