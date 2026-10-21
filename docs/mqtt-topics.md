# Topics MQTT — SmartAlarm

Base des topics : `smartalarm/demo01/`. `demo01` est l'identifiant de
l'appareil. Un second boîtier utiliserait `demo02`.

## Récapitulatif

| Topic | Émetteur | Récepteur | QoS | Retained | Payload |
|-------|----------|-----------|-----|----------|---------|
| `smartalarm/demo01/command` | Flutter | ESP32 | 1 | **non** | JSON `{"command": "ARM" \| "ARM_NIGHT" \| "DISARM"}` |
| `smartalarm/demo01/state` | ESP32 | Flutter | 1 | **oui** | JSON `{"state": "DISARMED" \| "ARMED" \| "ARMED_NIGHT" \| "TRIGGERED"}` |
| `smartalarm/demo01/motion` | ESP32 | Flutter | 1 | **non** | JSON `{"event": "MOTION_DETECTED" \| "OPENING_DETECTED", "sensor": <id>, "room": "salon" \| "chambre" \| "entree", "uptimeMs": <int>}` |
| `smartalarm/demo01/sensors` | ESP32 | Flutter | 1 | **oui** | JSON `{"pir_salon": "IDLE" \| "ACTIVE", "pir_chambre": "IDLE" \| "ACTIVE", "door": "CLOSED" \| "OPEN", "window": "CLOSED" \| "OPEN"}` |
| `smartalarm/demo01/availability` | ESP32 (et broker via LWT) | Flutter | 1 | **oui** | texte brut `online` / `offline` |

> **Note PubSubClient** : côté ESP32, PubSubClient ne sait **publier** qu'en
> QoS 0. En revanche, il peut s'abonner en QoS 1 et le Last Will peut être
> déclaré en QoS 1. Les publications `state`, `motion` et `sensors` de l'ESP32
> partent donc en QoS 0, ce qui est autorisé pour `state` par le cahier des charges.
> Pour `motion`, c'est la limite de la bibliothèque imposée. L'impact est
> faible, car la connexion TLS repose sur TCP, qui est fiable, et l'état
> `TRIGGERED`, conservé en retained, porte de toute façon l'alerte. Flutter
> (`mqtt_client`) publie bien les commandes en QoS 1.

## Détail des messages

### `command` (Flutter → ESP32)

```json
{ "command": "ARM" }
```
```json
{ "command": "ARM_NIGHT" }
```
```json
{ "command": "DISARM" }
```

`ARM` arme en mode total (tous les capteurs), `ARM_NIGHT` en mode nuit
(porte et fenêtre seulement, voir [Architecture](architecture.md#machine-à-états-esp32)).

- **Jamais retained.** Sinon, un ESP32 qui redémarre ré-exécuterait une
  ancienne commande et pourrait s'armer tout seul.
- Un payload invalide (JSON mal formé ou commande inconnue) est ignoré par
  l'ESP32 et signalé dans les logs Serial.

### `state` (ESP32 → Flutter)

```json
{ "state": "ARMED" }
```

- **Retained** : tout client qui s'abonne reçoit immédiatement le dernier état.
- Publié au démarrage (`DISARMED`), à chaque changement d'état, à chaque
  reconnexion MQTT et en réponse à une commande sans effet (confirmation).

### `motion` (ESP32 → Flutter)

```json
{ "event": "MOTION_DETECTED", "sensor": "pir_chambre", "room": "chambre", "uptimeMs": 125000 }
```
```json
{ "event": "OPENING_DETECTED", "sensor": "door", "room": "entree", "uptimeMs": 131000 }
```

- Publié **une fois par nouvelle détection valide** : front montant d'un
  capteur surveillé dans l'état courant, ou de n'importe quel capteur pendant
  `TRIGGERED` (pour l'historique).
- `sensor` : `pir_salon`, `pir_chambre`, `door` ou `window`.
- `room` : pièce du capteur (`salon`, `chambre` ou `entree`). Il sert à lire
  les messages dans un client MQTT. L'application déduit la pièce du capteur
  et accepte donc aussi un message sans `room`.
- Le nom du topic est resté `motion` pour ne pas casser le contrat existant,
  même s'il porte aussi les ouvertures.
- `uptimeMs` = `millis()` de l'ESP32. L'ESP32 n'a pas d'horloge réelle (pas
  de NTP dans cette V1). Flutter horodate donc l'événement à sa réception
  pour l'historique.
- Non retained : c'est un événement ponctuel, pas un état.

### `sensors` (ESP32 → Flutter)

```json
{ "pir_salon": "IDLE", "pir_chambre": "IDLE", "door": "CLOSED", "window": "OPEN" }
```

- **Retained** : l'application connaît l'état des capteurs dès sa connexion,
  par exemple une fenêtre restée ouverte avant d'armer.
- Publié à chaque changement d'un capteur (dans les deux sens) et à chaque
  connexion MQTT.
- C'est un état en direct, indépendant du mode : un capteur ouvert alors que
  l'alarme est désactivée apparaît ici, mais pas dans `motion`.

### `availability` (ESP32 / broker → Flutter)

- `online` : publié en retained par l'ESP32 juste après sa connexion MQTT.
- `offline` : **Last Will** déclaré à la connexion (retained, QoS 1). Le
  broker le publie si l'ESP32 disparaît sans déconnexion propre (simulation
  arrêtée, perte réseau).

## Identifiants clients MQTT

Chaque connexion au broker doit avoir un *client ID* unique. Deux clients
portant le même ID se déconnecteraient mutuellement en boucle.

| Client | Client ID |
|--------|-----------|
| ESP32 | `smartalarm-esp32-demo01` |
| Flutter | `smartalarm-flutter-<suffixe aléatoire>`, généré à chaque lancement pour autoriser plusieurs onglets |

## Tester à la main (client web HiveMQ ou MQTT CLI)

- S'abonner à `smartalarm/demo01/#` pour tout voir.
- Publier `{"command":"ARM"}` sur `smartalarm/demo01/command` **sans** cocher *retain*.

## Purger un message retained

Pour effacer un retained, il faut publier un **payload vide** avec *retain*
coché sur le topic concerné. C'est utile si un état de test traîne sur le
broker.
