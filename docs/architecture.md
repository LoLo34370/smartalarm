# Architecture — SmartAlarm

## Vue d'ensemble

```text
┌──────────────────────────┐          ┌──────────────────────┐          ┌────────────────────────────┐
│  ESP32 (simulé Wokwi)    │  MQTTS   │    HiveMQ Cloud      │   WSS    │   Application Flutter      │
│                          │  :8883   │    (Serverless)      │  :8884   │   (Web, iOS, Android)      │
│  PIR  → GPIO 13 (in)     │◀────────▶│                      │◀────────▶│                            │
│  LED verte → GPIO 26     │   TLS    │  broker MQTT 3.1.1   │   TLS    │  MqttService (WSS)         │
│  LED rouge → GPIO 27     │          │  auth user/password  │          │  AlarmController           │
│  Buzzer → GPIO 25        │          │  retained + LWT      │          │  DashboardScreen           │
│                          │          │                      │          │                            │
│  Machine à états         │          └──────────────────────┘          │  Affiche uniquement ce     │
│  = SOURCE DE VÉRITÉ      │                                            │  que l'ESP32 publie        │
└──────────────────────────┘                                            └────────────────────────────┘
       Wi-Fi « Wokwi-GUEST »
```

Pas de backend, de base de données ou de Firebase : le broker HiveMQ est le
seul intermédiaire. Les deux clients se connectent au broker et ne se parlent
jamais en direct.

## Rôles

| Composant | Responsabilités |
|-----------|-----------------|
| **ESP32** | Lit le PIR, pilote les LEDs et le buzzer, tient la machine à états, exécute les commandes `ARM` et `DISARM`, publie `state`, `motion` et `availability`. |
| **HiveMQ Cloud** | Relaie les messages, conserve les messages *retained* (dernier état, disponibilité) et publie le *Last Will* si l'ESP32 disparaît. |
| **Flutter** | Affiche l'état reçu et envoie des commandes. **Ne modifie jamais lui-même l'état métier.** |

## Machine à états (ESP32)

```text
                 ARM
   ┌──────────┐ ───────▶ ┌─────────┐   mouvement PIR (front montant)   ┌───────────┐
   │ DISARMED │          │  ARMED  │ ────────────────────────────────▶ │ TRIGGERED │
   └──────────┘ ◀─────── └─────────┘                                   └───────────┘
        ▲        DISARM                                                      │
        └──────────────────────────── DISARM ────────────────────────────────┘
```

| État | LED verte | LED rouge | Buzzer | PIR surveillé |
|------|-----------|-----------|--------|---------------|
| `DISARMED` | éteinte | éteinte | off | non |
| `ARMED` | allumée | éteinte | off | **oui** |
| `TRIGGERED` | allumée | **clignote** | **on** | (déjà déclenché) |

Règles :
- **Démarrage** : l'ESP32 démarre toujours en `DISARMED`, pour que la démo commence dans un état sûr, puis publie cet état.
- `TRIGGERED` **reste actif** même si le PIR repasse à LOW. Seul un `DISARM` en sort.
- `ARM` reçu en `ARMED` ou en `TRIGGERED` ne change rien (commande idempotente). L'état courant est republié.
- `DISARM` reçu en `DISARMED` ne change rien non plus. L'état courant est republié.
- Une détection n'est retenue que sur un **front montant** du PIR (LOW → HIGH). Un PIR qui reste à HIGH ne génère donc pas un flux continu d'événements.

## Flux « commande → confirmation »

```text
Flutter                    HiveMQ                     ESP32
   │  publish command ARM     │                          │
   │ ───────────────────────▶ │ ───────────────────────▶ │  applique ARM
   │  (bouton en attente…)    │                          │  LED verte ON
   │                          │  publish state ARMED (R) │
   │ ◀─────────────────────── │ ◀─────────────────────── │
   │  UI → « Maison protégée »│                          │
```

Le bouton Flutter ne fait **qu'envoyer** la commande. L'interface ne passe en
« protégée » qu'à la réception de `state = ARMED`. Si aucune confirmation
n'arrive dans un délai raisonnable, l'interface affiche un message
d'avertissement et ne simule jamais l'état.

## Connexion, reconnexion et cohérence

- **ESP32** : les reconnexions Wi-Fi et MQTT sont gérées dans `loop()` avec des
  temporisations `millis()` non bloquantes (pas de `while` infini, pas de longs
  `delay()`). À chaque (re)connexion MQTT, l'ESP32 publie `availability = online`
  (retained), se réabonne à `command` et republie son état courant.
- **Last Will** : l'ESP32 déclare à la connexion un testament `offline`
  (retained, QoS 1) sur `availability`. Si la liaison est coupée sans
  déconnexion propre, le broker le publie à sa place.
- **Flutter** : à la (re)connexion, Flutter se réabonne. Le broker lui renvoie
  aussitôt les derniers messages *retained* de `state` et `availability`.
  L'interface est donc resynchronisée sans aucune requête supplémentaire.
- Si `availability = offline`, Flutter grise les commandes et signale que le
  dernier état affiché n'est peut-être plus à jour.

## Choix techniques (justifications)

| Choix | Pourquoi |
|-------|----------|
| MQTT plutôt que HTTP | Protocole publish/subscribe léger, pensé pour l'IoT, avec un push temps réel dans les deux sens. |
| HiveMQ Cloud Serverless | Gratuit, TLS inclus, accès en MQTTS (ESP32) et en WSS (navigateur). |
| WSS pour Flutter Web | Un navigateur ne peut pas ouvrir de socket TCP brute. MQTT passe donc par une WebSocket sécurisée. |
| TLS avec CA racine | Le certificat du broker est vérifié avec le certificat racine (CA) embarqué dans l'ESP32. Pas de `setInsecure()`. |
| ESP32 = source de vérité | Évite les incohérences : l'UI reflète toujours l'état physique réel. |
| `ValueNotifier` / `ChangeNotifier` | Suffisant pour trois écrans (dashboard, journal, réglages), sans dépendance externe de gestion d'état. |
| Journal stocké sur l'appareil | Pas de backend : chaque téléphone garde son propre historique. Les entrées sont horodatées à la réception, car l'ESP32 n'a pas d'horloge réelle. |
| Réglages dans l'application | Permet de changer de broker sans recompiler (fin de l'offre HiveMQ Serverless au 31/12/2026). Les identifiants restent hors du code compilé. |
| Face ID pour désactiver | Désactiver est l'action sensible : un téléphone déverrouillé laissé sur une table ne doit pas suffire. Armer reste immédiat. |

## Vérification des GPIO (ESP32 DevKit V1)

| Fonction | GPIO | Sens | Compatibilité |
|----------|------|------|---------------|
| PIR OUT | 13 | entrée | ✅ GPIO standard. Ce n'est pas une broche de *strapping*. L'usage ADC2 n'est pas concerné, car on fait une lecture numérique. |
| Buzzer | 25 | sortie | ✅ Sortie numérique et PWM (LEDC) sans restriction. |
| LED verte | 26 | sortie | ✅ |
| LED rouge | 27 | sortie | ✅ |

À éviter, et non utilisés : GPIO 0, 2, 5, 12 et 15 (*strapping*), 6 à 11
(flash SPI), 34 à 39 (entrée seule). Le brochage proposé est donc conservé
tel quel.
