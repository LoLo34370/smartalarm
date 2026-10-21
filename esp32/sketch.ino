// ─────────────────────────────────────────────────────────────────────────────
// SmartAlarm — ESP32 (Wokwi), relié à HiveMQ Cloud en MQTT sur TLS.
//
// L'ESP32 est la SOURCE DE VÉRITÉ de l'état de l'alarme :
//   - il reçoit les commandes ARM / ARM_NIGHT / DISARM sur  <base>/command
//   - il publie son état (retained)                     sur  <base>/state
//   - il publie chaque détection                         sur  <base>/motion
//   - il publie l'état des capteurs (retained)           sur  <base>/sensors
//   - il publie online / offline (retained)              sur  <base>/availability (+ Last Will)
//
// Capteurs : PIR du salon (intérieur), contacts de la porte d'entrée et de la
// fenêtre (périmètre). ARMED surveille tout ; ARMED_NIGHT seulement le
// périmètre, pour pouvoir circuler dans la maison la nuit.
//
// Les commandes restent aussi utilisables depuis le moniteur série
// (débogage). Elles passent par la même fonction handleCommand().
// ─────────────────────────────────────────────────────────────────────────────
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

#include "config.h"  // identifiants (non versionné) — voir config.example.h

// ── Brochage (voir docs/architecture.md) ────────────────────────────────────
constexpr uint8_t PIN_PIR       = 13;  // entrée : sortie OUT du capteur PIR
constexpr uint8_t PIN_DOOR      = 14;  // entrée (pull-up) : contact porte d'entrée
constexpr uint8_t PIN_WINDOW    = 32;  // entrée (pull-up) : contact fenêtre
constexpr uint8_t PIN_BUZZER    = 25;  // sortie : sirène
constexpr uint8_t PIN_LED_GREEN = 26;  // sortie : alarme activée
constexpr uint8_t PIN_LED_RED   = 27;  // sortie : intrusion

// ── Réglages de la sirène et du clignotement ────────────────────────────────
constexpr uint32_t RED_BLINK_MS     = 250;   // demi-période de clignotement LED rouge
constexpr uint32_t NIGHT_BLINK_MS   = 1000;  // demi-période de la LED verte en mode nuit
constexpr uint32_t SIREN_STEP_MS    = 400;   // alternance des deux tons de la sirène
constexpr uint16_t SIREN_FREQ_LOW   = 880;   // Hz
constexpr uint16_t SIREN_FREQ_HIGH  = 1320;  // Hz

// ── Réglages réseau ─────────────────────────────────────────────────────────
constexpr uint32_t WIFI_RETRY_MS     = 10000;  // nouvelle tentative Wi-Fi
constexpr uint32_t MQTT_RETRY_MS     = 5000;   // nouvelle tentative MQTT
constexpr uint16_t MQTT_KEEPALIVE_S  = 60;     // large : le simulateur Wokwi peut tourner plus lentement que le temps réel
constexpr uint16_t MQTT_BUFFER_SIZE  = 512;

const String TOPIC_COMMAND      = String(TOPIC_BASE) + "/command";
const String TOPIC_STATE        = String(TOPIC_BASE) + "/state";
const String TOPIC_MOTION       = String(TOPIC_BASE) + "/motion";
const String TOPIC_AVAILABILITY = String(TOPIC_BASE) + "/availability";
const String TOPIC_SENSORS      = String(TOPIC_BASE) + "/sensors";

WiFiClientSecure tlsClient;
PubSubClient     mqtt(tlsClient);

bool     wifiConnected     = false;
bool     mqttConnected     = false;
uint32_t lastWifiAttemptMs = 0;
uint32_t lastMqttAttemptMs = 0;

// ── Machine à états ─────────────────────────────────────────────────────────
enum class AlarmState { DISARMED, ARMED, ARMED_NIGHT, TRIGGERED };

AlarmState alarmState = AlarmState::DISARMED;

// ── Capteurs ────────────────────────────────────────────────────────────────
// Un capteur est « actif » quand son entrée est HIGH : mouvement pour le PIR,
// contact ouvert pour la porte et la fenêtre (l'interrupteur fermé relie
// l'entrée à GND, la résistance de pull-up interne la tire à HIGH sinon).
enum class SensorZone { PERIMETER, INTERIOR };

struct Sensor {
  const char *id;           // identifiant dans les messages MQTT
  uint8_t     pin;
  SensorZone  zone;
  bool        isContact;    // contact d'ouverture (sinon : détecteur de mouvement)
  bool        lastLevel;    // pour détecter le front montant LOW → HIGH
};

Sensor sensors[] = {
  {"pir_salon", PIN_PIR,    SensorZone::INTERIOR,  false, LOW},
  {"door",      PIN_DOOR,   SensorZone::PERIMETER, true,  LOW},
  {"window",    PIN_WINDOW, SensorZone::PERIMETER, true,  LOW},
};

bool     redLedOn         = false;
bool     greenLedOn       = false;
bool     sirenHighTone    = false;
bool     sirenActive      = false;
uint32_t lastBlinkMs      = 0;
uint32_t lastNightBlinkMs = 0;
uint32_t lastSirenMs      = 0;
String   serialBuffer;

const char *stateName(AlarmState state) {
  switch (state) {
    case AlarmState::DISARMED:    return "DISARMED";
    case AlarmState::ARMED:       return "ARMED";
    case AlarmState::ARMED_NIGHT: return "ARMED_NIGHT";
    case AlarmState::TRIGGERED:   return "TRIGGERED";
  }
  return "UNKNOWN";
}

// Le capteur déclenche-t-il l'alarme dans l'état courant ?
bool isMonitored(const Sensor &sensor) {
  switch (alarmState) {
    case AlarmState::ARMED:       return true;
    case AlarmState::ARMED_NIGHT: return sensor.zone == SensorZone::PERIMETER;
    default:                      return false;
  }
}

const char *sensorLevelName(const Sensor &sensor, bool level) {
  if (sensor.isContact) return level == HIGH ? "OPEN" : "CLOSED";
  return level == HIGH ? "ACTIVE" : "IDLE";
}

// ── Publications MQTT ───────────────────────────────────────────────────────
// Remarque : PubSubClient ne publie qu'en QoS 0 (voir docs/mqtt-topics.md).

void publishState() {
  char payload[40];
  snprintf(payload, sizeof(payload), "{\"state\":\"%s\"}", stateName(alarmState));

  if (mqtt.connected()) {
    const bool ok = mqtt.publish(TOPIC_STATE.c_str(), payload, true);  // retained
    Serial.printf("[STATE ] %s -> %s %s\r\n", stateName(alarmState), TOPIC_STATE.c_str(),
                  ok ? "(publié)" : "(ÉCHEC publication)");
  } else {
    Serial.printf("[STATE ] %s (MQTT hors ligne : publié à la reconnexion)\r\n",
                  stateName(alarmState));
  }
}

void publishDetection(const Sensor &sensor, uint32_t uptimeMs) {
  char payload[112];
  snprintf(payload, sizeof(payload),
           "{\"event\":\"%s\",\"sensor\":\"%s\",\"uptimeMs\":%lu}",
           sensor.isContact ? "OPENING_DETECTED" : "MOTION_DETECTED", sensor.id,
           (unsigned long)uptimeMs);

  if (mqtt.connected()) {
    const bool ok = mqtt.publish(TOPIC_MOTION.c_str(), payload, false);  // jamais retained
    Serial.printf("[MOTION] %s %s\r\n", payload, ok ? "(publié)" : "(ÉCHEC publication)");
  } else {
    Serial.printf("[MOTION] %s (MQTT hors ligne : événement non transmis)\r\n", payload);
  }
}

// État courant de chaque capteur, ex. {"pir_salon":"IDLE","door":"CLOSED",...}.
void publishSensors() {
  char payload[128];
  size_t length = snprintf(payload, sizeof(payload), "{");
  for (size_t i = 0; i < sizeof(sensors) / sizeof(sensors[0]); i++) {
    length += snprintf(payload + length, sizeof(payload) - length, "%s\"%s\":\"%s\"",
                       i == 0 ? "" : ",", sensors[i].id,
                       sensorLevelName(sensors[i], sensors[i].lastLevel));
  }
  snprintf(payload + length, sizeof(payload) - length, "}");

  if (mqtt.connected()) {
    const bool ok = mqtt.publish(TOPIC_SENSORS.c_str(), payload, true);  // retained
    Serial.printf("[SENSOR] %s %s\r\n", payload, ok ? "(publié)" : "(ÉCHEC publication)");
  }
}

// ── Sorties physiques ───────────────────────────────────────────────────────

void sirenOn(uint16_t frequency) {
  tone(PIN_BUZZER, frequency);
  sirenActive = true;
}

void sirenOff() {
  // noTone() sans tone() préalable provoque « LEDC is not initialized ».
  if (sirenActive) {
    noTone(PIN_BUZZER);
    sirenActive = false;
  }
  digitalWrite(PIN_BUZZER, LOW);
}

// Applique l'état « statique » des sorties correspondant à l'état métier.
// Le clignotement et la sirène de TRIGGERED sont animés dans updateAlarmOutputs().
void applyOutputs() {
  switch (alarmState) {
    case AlarmState::DISARMED:
      digitalWrite(PIN_LED_GREEN, LOW);
      digitalWrite(PIN_LED_RED, LOW);
      sirenOff();
      break;

    case AlarmState::ARMED:
      digitalWrite(PIN_LED_GREEN, HIGH);
      digitalWrite(PIN_LED_RED, LOW);
      sirenOff();
      break;

    case AlarmState::ARMED_NIGHT:  // LED verte clignotante lente, voir updateAlarmOutputs()
      greenLedOn       = true;
      lastNightBlinkMs = millis();
      digitalWrite(PIN_LED_GREEN, HIGH);
      digitalWrite(PIN_LED_RED, LOW);
      sirenOff();
      break;

    case AlarmState::TRIGGERED: {
      const uint32_t now = millis();
      digitalWrite(PIN_LED_GREEN, HIGH);
      redLedOn      = true;
      sirenHighTone = false;
      lastBlinkMs   = now;
      lastSirenMs   = now;
      digitalWrite(PIN_LED_RED, HIGH);
      sirenOn(SIREN_FREQ_LOW);
      break;
    }
  }
}

void setState(AlarmState newState) {
  if (newState == alarmState) {
    publishState();  // commande sans effet : on reconfirme l'état courant
    return;
  }
  Serial.printf("[ALARM ] %s -> %s\r\n", stateName(alarmState), stateName(newState));
  alarmState = newState;
  applyOutputs();
  publishState();
}

// Arme dans le mode demandé. Un contact déjà ouvert ne déclenchera l'alarme
// qu'à sa prochaine ouverture : on le signale (l'application l'affiche aussi).
void arm(AlarmState mode) {
  // ARM pendant TRIGGERED ne doit pas couper la sirène.
  if (alarmState == AlarmState::TRIGGERED) {
    setState(alarmState);
    return;
  }
  for (const Sensor &sensor : sensors) {
    if (sensor.isContact && sensor.lastLevel == HIGH) {
      Serial.printf("[ALARM ] attention : %s ouvert à l'activation\r\n", sensor.id);
    }
  }
  setState(mode);
}

// Traite une commande, quelle que soit sa provenance (MQTT ou série).
void handleCommand(String command) {
  command.trim();
  command.toUpperCase();

  if (command == "ARM") {
    arm(AlarmState::ARMED);
  } else if (command == "ARM_NIGHT") {
    arm(AlarmState::ARMED_NIGHT);
  } else if (command == "DISARM") {
    setState(AlarmState::DISARMED);
  } else {
    Serial.printf("[CMD   ] commande inconnue ignorée : \"%s\"\r\n", command.c_str());
  }
}

// Extrait la valeur texte d'une clé dans un JSON plat, ex. {"command":"ARM"}.
// Suffisant pour ce contrat de messages, sans dépendance supplémentaire.
bool extractJsonString(const String &json, const char *key, String &out) {
  const String pattern = String('"') + key + '"';
  const int keyPos = json.indexOf(pattern);
  if (keyPos < 0) return false;
  const int colon = json.indexOf(':', keyPos + pattern.length());
  if (colon < 0) return false;
  const int quoteStart = json.indexOf('"', colon + 1);
  if (quoteStart < 0) return false;
  const int quoteEnd = json.indexOf('"', quoteStart + 1);
  if (quoteEnd < 0) return false;
  out = json.substring(quoteStart + 1, quoteEnd);
  return true;
}

void onMqttMessage(char *topic, byte *payload, unsigned int length) {
  String message;
  message.reserve(length);
  for (unsigned int i = 0; i < length; i++) {
    message += static_cast<char>(payload[i]);
  }
  Serial.printf("[MQTT  ] reçu sur %s : %s\r\n", topic, message.c_str());

  if (TOPIC_COMMAND != topic) {
    return;
  }
  String command;
  if (!extractJsonString(message, "command", command)) {
    Serial.println("[CMD   ] payload invalide ignoré "
                   "(attendu {\"command\":\"ARM|ARM_NIGHT|DISARM\"})");
    return;
  }
  handleCommand(command);
}

// ── Entrées : série (débogage) et capteurs ──────────────────────────────────

// Lecture non bloquante d'une ligne sur le moniteur série.
void readSerialCommand() {
  while (Serial.available() > 0) {
    const char c = static_cast<char>(Serial.read());
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        Serial.printf("[CMD   ] reçu (série) : %s\r\n", serialBuffer.c_str());
        handleCommand(serialBuffer);
        serialBuffer = "";
      }
    } else if (serialBuffer.length() < 32) {
      serialBuffer += c;
    }
  }
}

// Détecte une NOUVELLE détection : uniquement sur le front montant
// (mouvement qui commence, porte ou fenêtre qui s'ouvre).
void handleSensor(Sensor &sensor) {
  const bool level = digitalRead(sensor.pin);
  if (level == sensor.lastLevel) {
    return;
  }
  sensor.lastLevel = level;
  Serial.printf("[SENSOR] %s %s\r\n", sensor.id, sensorLevelName(sensor, level));
  publishSensors();

  if (level != HIGH) {
    return;  // retour au repos : TRIGGERED reste actif
  }

  if (alarmState == AlarmState::TRIGGERED) {
    publishDetection(sensor, millis());  // nouvelle détection pendant l'alarme : historisée
  } else if (isMonitored(sensor)) {
    publishDetection(sensor, millis());
    setState(AlarmState::TRIGGERED);
  } else {
    Serial.printf("[SENSOR] %s ignoré (%s)\r\n", sensor.id,
                  alarmState == AlarmState::ARMED_NIGHT ? "mode nuit" : "alarme désactivée");
  }
}

void handleSensors() {
  for (Sensor &sensor : sensors) {
    handleSensor(sensor);
  }
}

// Animation non bloquante : LED verte lente en mode nuit ;
// LED rouge clignotante + sirène 2 tons en TRIGGERED.
void updateAlarmOutputs() {
  const uint32_t now = millis();

  if (alarmState == AlarmState::ARMED_NIGHT && now - lastNightBlinkMs >= NIGHT_BLINK_MS) {
    lastNightBlinkMs = now;
    greenLedOn = !greenLedOn;
    digitalWrite(PIN_LED_GREEN, greenLedOn ? HIGH : LOW);
  }

  if (alarmState != AlarmState::TRIGGERED) {
    return;
  }

  if (now - lastBlinkMs >= RED_BLINK_MS) {
    lastBlinkMs = now;
    redLedOn = !redLedOn;
    digitalWrite(PIN_LED_RED, redLedOn ? HIGH : LOW);
  }

  if (now - lastSirenMs >= SIREN_STEP_MS) {
    lastSirenMs = now;
    sirenHighTone = !sirenHighTone;
    sirenOn(sirenHighTone ? SIREN_FREQ_HIGH : SIREN_FREQ_LOW);
  }
}

// ── Connexions Wi-Fi / MQTT (non bloquantes) ────────────────────────────────

const char *mqttStateLabel(int state) {
  switch (state) {
    case MQTT_CONNECTION_TIMEOUT:      return "délai dépassé (broker muet)";
    case MQTT_CONNECTION_LOST:         return "connexion perdue";
    case MQTT_CONNECT_FAILED:          return "échec TCP/TLS";
    case MQTT_DISCONNECTED:            return "déconnecté";
    case MQTT_CONNECT_BAD_PROTOCOL:    return "protocole refusé";
    case MQTT_CONNECT_BAD_CLIENT_ID:   return "client ID refusé";
    case MQTT_CONNECT_UNAVAILABLE:     return "broker indisponible";
    case MQTT_CONNECT_BAD_CREDENTIALS: return "identifiants incorrects";
    case MQTT_CONNECT_UNAUTHORIZED:    return "non autorisé";
  }
  return "inconnu";
}

void startWifi() {
  Serial.printf("[WIFI  ] connexion à \"%s\" (canal %d)...\r\n", WIFI_SSID, WIFI_CHANNEL);
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD, WIFI_CHANNEL);
  lastWifiAttemptMs = millis();
}

bool connectMqtt() {
  Serial.printf("[MQTT  ] connexion TLS à %s:%d (client %s)...\r\n",
                MQTT_HOST, MQTT_PORT, MQTT_CLIENT_ID);

  // Last Will : si l'ESP32 disparaît sans prévenir, le broker publie
  // « offline » (retained, QoS 1) sur le topic availability.
  const bool ok = mqtt.connect(MQTT_CLIENT_ID, MQTT_USERNAME, MQTT_PASSWORD,
                               TOPIC_AVAILABILITY.c_str(), 1, true, "offline",
                               true /* cleanSession */);
  if (!ok) {
    const int rc = mqtt.state();
    Serial.printf("[MQTT  ] échec (rc=%d : %s), nouvel essai dans %lus\r\n",
                  rc, mqttStateLabel(rc), (unsigned long)(MQTT_RETRY_MS / 1000));
    // L'erreur TLS n'a de sens que si la connexion sécurisée elle-même a échoué
    // (sinon lastError() renvoie une ancienne erreur interne sans rapport).
    char tlsError[128];
    if (rc == MQTT_CONNECT_FAILED && tlsClient.lastError(tlsError, sizeof(tlsError)) != 0) {
      Serial.printf("[TLS   ] %s\r\n", tlsError);
    }
    return false;
  }

  Serial.println("[MQTT  ] connecté (TLS + authentification OK)");
  mqtt.publish(TOPIC_AVAILABILITY.c_str(), "online", true);  // retained
  Serial.printf("[MQTT  ] %s -> online\r\n", TOPIC_AVAILABILITY.c_str());

  const bool subscribed = mqtt.subscribe(TOPIC_COMMAND.c_str(), 1);
  Serial.printf("[MQTT  ] abonnement %s (QoS 1) %s\r\n", TOPIC_COMMAND.c_str(),
                subscribed ? "OK" : "ÉCHEC");

  publishState();    // resynchronise les clients sur l'état réel
  publishSensors();
  return true;
}

void maintainConnections() {
  const uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) {
    if (wifiConnected) {
      Serial.println("[WIFI  ] connexion perdue");
      wifiConnected = false;
      mqttConnected = false;
    }
    if (now - lastWifiAttemptMs >= WIFI_RETRY_MS) {
      startWifi();
    }
    return;
  }

  if (!wifiConnected) {
    wifiConnected = true;
    Serial.printf("[WIFI  ] connecté, IP %s\r\n", WiFi.localIP().toString().c_str());
    lastMqttAttemptMs = now - MQTT_RETRY_MS;  // tentative MQTT immédiate
  }

  if (mqtt.connected()) {
    mqtt.loop();
    return;
  }

  if (mqttConnected) {
    Serial.printf("[MQTT  ] connexion perdue (rc=%d : %s)\r\n", mqtt.state(),
                  mqttStateLabel(mqtt.state()));
    mqttConnected = false;
  }
  if (now - lastMqttAttemptMs >= MQTT_RETRY_MS) {
    lastMqttAttemptMs = now;
    mqttConnected = connectMqtt();
  }
}

// ── Programme principal ─────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  pinMode(PIN_PIR, INPUT);
  pinMode(PIN_DOOR, INPUT_PULLUP);
  pinMode(PIN_WINDOW, INPUT_PULLUP);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);

  Serial.println();
  Serial.println("=== SmartAlarm — ESP32 + MQTT ===");
  Serial.println("Débogage : ARM, ARM_NIGHT ou DISARM dans le moniteur série, puis Entrée.");

  // Sécurité de la démo : on démarre toujours désarmé.
  alarmState = AlarmState::DISARMED;
  for (Sensor &sensor : sensors) {
    sensor.lastLevel = digitalRead(sensor.pin);
  }
  applyOutputs();
  publishState();  // MQTT pas encore connecté : sera publié à la connexion

  // TLS avec validation du certificat du broker (jamais setInsecure()).
  tlsClient.setCACert(MQTT_ROOT_CA);

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMqttMessage);
  mqtt.setKeepAlive(MQTT_KEEPALIVE_S);
  mqtt.setBufferSize(MQTT_BUFFER_SIZE);

  WiFi.mode(WIFI_STA);
  startWifi();
}

void loop() {
  maintainConnections();
  readSerialCommand();
  handleSensors();
  updateAlarmOutputs();
  delay(10);  // court : laisse respirer le CPU sans perturber MQTT
}
