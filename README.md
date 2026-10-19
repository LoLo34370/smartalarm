# SmartAlarm 🏠🔔

Alarme domestique connectée : un **ESP32** simulé sur **Wokwi** surveille un
capteur de mouvement PIR. Une application **Flutter** permet de l'activer et
de la désactiver à distance via le broker **HiveMQ Cloud** (MQTT sur TLS).

```text
ESP32 (Wokwi)  ⇄  MQTTS :8883  ⇄  HiveMQ Cloud  ⇄  WSS :8884  ⇄  Flutter Web
```

> 🚧 Projet en cours de réalisation. Ce README sera finalisé à l'étape 7.

## Fonctionnalités

- Activer et désactiver l'alarme depuis Flutter, avec confirmation par l'ESP32.
- Trois états : `DISARMED`, `ARMED`, `TRIGGERED`.
- Sirène (buzzer) et LED rouge clignotante en cas d'intrusion.
- Historique des détections pendant la session.
- Affichage de la connexion au broker et de la disponibilité de l'ESP32 (Last Will).

## Structure du dépôt

```text
smartalarm/
├── README.md
├── docs/
│   ├── architecture.md   # architecture, machine à états, choix techniques, GPIO
│   ├── mqtt-topics.md    # contrat MQTT (topics, payloads, QoS, retained)
│   └── setup.md          # installation et configuration
├── esp32/                # sketch Wokwi (étapes 3 et 4)
└── flutter_app/          # application Flutter (étapes 5 et 6)
```

## Documentation

- [Architecture](docs/architecture.md)
- [Topics MQTT](docs/mqtt-topics.md)
- [Installation](docs/setup.md)

## Avancement

| Étape | Contenu | Statut |
|-------|---------|--------|
| 1 | Initialisation et architecture | ✅ |
| 2 | Configuration HiveMQ Cloud | ✅ |
| 3 | Circuit Wokwi (logique locale) | ✅ |
| 4 | ESP32 et MQTT | ✅ |
| 5 | Initialisation Flutter et service MQTT | ✅ |
| 6 | Dashboard Flutter | 🔄 en attente de validation |
| 7 | Tests finaux et documentation | ⏳ |

## Sécurité

Aucun identifiant n'est commité : voir [Gestion des secrets](docs/setup.md#gestion-des-secrets).
