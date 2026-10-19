# SmartAlarm 🏠🔔

Alarme domestique connectée : un **ESP32** simulé sur **Wokwi** surveille un
capteur de mouvement PIR et les contacts d'une porte et d'une fenêtre. Une application **Flutter** (iOS, Android, Web)
permet de l'activer et de la désactiver à distance via le broker
**HiveMQ Cloud** (MQTT sur TLS).

```text
ESP32 (Wokwi)  ⇄  MQTTS :8883  ⇄  HiveMQ Cloud  ⇄  WSS :8884   ⇄  Flutter Web
                                              ⇄  MQTTS :8883 ⇄  Flutter iOS / Android
```

> 🚧 Projet en cours de réalisation. Ce README sera finalisé à l'étape 7.

## Fonctionnalités

- Activer et désactiver l'alarme depuis Flutter, avec confirmation par l'ESP32.
- Quatre états : `DISARMED`, `ARMED`, `ARMED_NIGHT`, `TRIGGERED`.
- **Mode nuit** : seules la porte et la fenêtre sont surveillées, on peut
  circuler dans la maison sans déclencher le PIR.
- **État des capteurs en direct** dans l'application, avec un avertissement
  si une porte ou une fenêtre est ouverte avant d'armer.
- Sirène (buzzer) et LED rouge clignotante en cas d'intrusion.
- Affichage de la connexion au broker et de la disponibilité de l'ESP32 (Last Will).
- **Journal d'activité conservé sur l'appareil** : activations, désactivations,
  intrusions et détections, regroupés par jour et filtrables.
- **Réglages dans l'application** : broker MQTT modifiable sans recompiler,
  identifiants stockés dans le Trousseau iOS / Keystore Android.
- **Désactivation protégée** (option) par Face ID, Touch ID ou code de l'appareil.
- **Vibration** de l'appareil à chaque intrusion.

## Structure du dépôt

```text
smartalarm/
├── README.md
├── docs/
│   ├── architecture.md   # architecture, machine à états, choix techniques, GPIO
│   ├── mqtt-topics.md    # contrat MQTT (topics, payloads, QoS, retained)
│   └── setup.md          # installation et configuration
├── esp32/                # sketch Wokwi (étapes 3, 4 et 6 ter)
└── flutter_app/          # application Flutter (étapes 5, 6, 6 bis et 6 ter)
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
| 6 | Dashboard Flutter | ✅ |
| 6 bis | Version iOS, journal persistant, réglages, Face ID, vibration | ✅ |
| 6 ter | Capteurs de porte et de fenêtre, mode nuit | ✅ |
| 7 | Tests finaux et documentation | ⏳ |

## Sécurité

Aucun identifiant n'est commité : voir [Gestion des secrets](docs/setup.md#gestion-des-secrets).
