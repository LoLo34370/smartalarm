# Architecture — SmartAlarm

## Vue d'ensemble

```text
┌──────────────────────────┐          ┌──────────────────────┐          ┌────────────────────────────┐
│  ESP32 (simulé Wokwi)    │  MQTTS   │    HiveMQ Cloud      │   WSS    │   Application Flutter      │
│                          │  :8883   │    (Serverless)      │  :8884   │   (Web, iOS, Android)      │
│  PIR  → GPIO 13 (in)     │◀────────▶│                      │◀────────▶│                            │
│  Porte → GPIO 14 (in)    │          │                      │          │                            │
│  Fenêtre → GPIO 32 (in)  │          │                      │          │                            │
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
| **ESP32** | Lit les capteurs (PIR, contacts de porte et de fenêtre), pilote les LEDs et le buzzer, tient la machine à états, exécute les commandes `ARM`, `ARM_NIGHT` et `DISARM`, publie `state`, `motion`, `sensors` et `availability`. |
| **HiveMQ Cloud** | Relaie les messages, conserve les messages *retained* (dernier état, disponibilité) et publie le *Last Will* si l'ESP32 disparaît. |
| **Flutter** | Affiche l'état reçu et envoie des commandes. **Ne modifie jamais lui-même l'état métier.** |

## Capteurs

| Capteur | Identifiant MQTT | Zone | Simulation Wokwi | Actif quand |
|---------|------------------|------|------------------|-------------|
| PIR du salon | `pir_salon` | intérieur | capteur PIR | mouvement détecté |
| Porte d'entrée | `door` | périmètre | interrupteur à glissière de gauche | contact ouvert |
| Fenêtre | `window` | périmètre | interrupteur à glissière de droite | contact ouvert |

Les contacts sont câblés entre la broche et GND, avec la résistance de
*pull-up* interne de l'ESP32 : contact fermé = LOW, contact ouvert = HIGH.
C'est le montage d'un vrai contact magnétique (ILS) de porte, sans résistance
externe.

## Machine à états (ESP32)

```text
                    ARM                 capteur surveillé (front montant)
   ┌──────────┐ ─────────▶ ┌─────────────┐ ───────────────────────▶ ┌───────────┐
   │          │            │    ARMED    │                          │           │
   │          │ ◀───────── └─────────────┘                          │           │
   │ DISARMED │   DISARM     ARM ▲  │ ARM_NIGHT                     │ TRIGGERED │
   │          │                  │  ▼                               │           │
   │          │ ─────────▶ ┌─────────────┐ ───────────────────────▶ │           │
   │          │  ARM_NIGHT │ ARMED_NIGHT │   porte ou fenêtre       │           │
   └──────────┘ ◀───────── └─────────────┘                          └───────────┘
        ▲         DISARM                                                  │
        └──────────────────────────── DISARM ─────────────────────────────┘
```

| État | LED verte | LED rouge | Buzzer | Capteurs surveillés |
|------|-----------|-----------|--------|---------------------|
| `DISARMED` | éteinte | éteinte | off | aucun |
| `ARMED` | allumée | éteinte | off | **tous** |
| `ARMED_NIGHT` | **clignote lentement** | éteinte | off | **porte et fenêtre** (PIR ignoré) |
| `TRIGGERED` | allumée | **clignote** | **on** | (déjà déclenché) |

Règles :
- **Démarrage** : l'ESP32 démarre toujours en `DISARMED`, pour que la démo commence dans un état sûr, puis publie cet état.
- **Mode nuit** : on reste chez soi, alarme armée. Les ouvertures de porte et de fenêtre déclenchent l'alarme, mais pas les mouvements dans le salon.
- On peut passer directement de `ARMED` à `ARMED_NIGHT` et inversement. Dans l'application, seule la désactivation est proposée une fois armé, pour garder un bouton simple.
- `TRIGGERED` **reste actif** même si le capteur revient au repos. Seul un `DISARM` en sort.
- `ARM` ou `ARM_NIGHT` reçu en `TRIGGERED` ne coupe pas la sirène. Une commande qui ne change rien republie l'état courant.
- `DISARM` reçu en `DISARMED` ne change rien non plus. L'état courant est republié.
- Une détection n'est retenue que sur un **front montant** (LOW → HIGH) : un mouvement qui commence, une porte qui s'ouvre. Un capteur qui reste actif ne génère donc pas un flux continu d'événements.
- **Contact déjà ouvert à l'armement** : l'alarme s'arme quand même, mais ce contact ne déclenchera qu'à sa prochaine ouverture. L'ESP32 le signale dans ses logs et l'application prévient avant d'armer (« Fenêtre ouverte : pensez à la fermer… »).

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
| Contact porte | 14 | entrée, *pull-up* interne | ✅ Pas une broche de *strapping*. Le signal PWM émis au démarrage n'a pas d'effet sur une entrée. |
| Contact fenêtre | 32 | entrée, *pull-up* interne | ✅ GPIO standard (ADC1), *pull-up* interne disponible, contrairement à 34 à 39. |
| Buzzer | 25 | sortie | ✅ Sortie numérique et PWM (LEDC) sans restriction. |
| LED verte | 26 | sortie | ✅ |
| LED rouge | 27 | sortie | ✅ |

À éviter, et non utilisés : GPIO 0, 2, 5, 12 et 15 (*strapping*), 6 à 11
(flash SPI), 34 à 39 (entrée seule). Le brochage proposé est donc conservé
tel quel.
