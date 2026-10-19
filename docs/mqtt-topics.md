# Topics MQTT — SmartAlarm

Base des topics : `smartalarm/demo01/`. `demo01` est l'identifiant de
l'appareil. Un second boîtier utiliserait `demo02`.

## Récapitulatif

| Topic | Émetteur | Récepteur | QoS | Retained | Payload |
|-------|----------|-----------|-----|----------|---------|
| `smartalarm/demo01/command` | Flutter | ESP32 | 1 | **non** | JSON `{"command": "ARM" \| "DISARM"}` |
| `smartalarm/demo01/state` | ESP32 | Flutter | 1 | **oui** | JSON `{"state": "DISARMED" \| "ARMED" \| "TRIGGERED"}` |
| `smartalarm/demo01/motion` | ESP32 | Flutter | 1 | **non** | JSON `{"event": "MOTION_DETECTED", "uptimeMs": <int>}` |
| `smartalarm/demo01/availability` | ESP32 (et broker via LWT) | Flutter | 1 | **oui** | texte brut `online` / `offline` |

> **Note PubSubClient** : côté ESP32, PubSubClient ne sait **publier** qu'en
> QoS 0. En revanche, il peut s'abonner en QoS 1 et le Last Will peut être
> déclaré en QoS 1. Les publications `state` et `motion` de l'ESP32 partiront
> donc en QoS 0, ce qui est autorisé pour `state` par le cahier des charges.
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
{ "command": "DISARM" }
```

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
{ "event": "MOTION_DETECTED", "uptimeMs": 125000 }
```

- Publié **une fois par nouvelle détection valide** : front montant du PIR
  alors que l'alarme est `ARMED`.
- `uptimeMs` = `millis()` de l'ESP32. L'ESP32 n'a pas d'horloge réelle (pas
  de NTP dans cette V1). Flutter horodate donc l'événement à sa réception
  pour l'historique.
- Non retained : c'est un événement ponctuel, pas un état.

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
