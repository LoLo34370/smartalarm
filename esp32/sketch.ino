// ─────────────────────────────────────────────────────────────────────────────
// SmartAlarm — ESP32 (Wokwi)
// Étape 4 : Wi-Fi + MQTT sécurisé (TLS) vers HiveMQ Cloud.
//
// L'ESP32 est la SOURCE DE VÉRITÉ de l'état de l'alarme :
//   - il reçoit les commandes ARM / DISARM sur  <base>/command
//   - il publie son état (retained)          sur  <base>/state
//   - il publie chaque détection              sur  <base>/motion
//   - il publie online / offline (retained)   sur  <base>/availability (+ Last Will)
//
// Les commandes ARM / DISARM restent aussi utilisables depuis le moniteur série
// (débogage). Elles passent par la même fonction handleCommand().
// ─────────────────────────────────────────────────────────────────────────────
#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

#include "config.h"  // identifiants (non versionné) — voir config.example.h

// ── Brochage (voir docs/architecture.md) ────────────────────────────────────
constexpr uint8_t PIN_PIR       = 13;  // entrée : sortie OUT du capteur PIR
constexpr uint8_t PIN_BUZZER    = 25;  // sortie : sirène
constexpr uint8_t PIN_LED_GREEN = 26;  // sortie : alarme activée
constexpr uint8_t PIN_LED_RED   = 27;  // sortie : intrusion

// ── Réglages de la sirène et du clignotement ────────────────────────────────
constexpr uint32_t RED_BLINK_MS     = 250;   // demi-période de clignotement LED rouge
constexpr uint32_t SIREN_STEP_MS    = 400;   // alternance des deux tons de la sirène
constexpr uint16_t SIREN_FREQ_LOW   = 880;   // Hz
constexpr uint16_t SIREN_FREQ_HIGH  = 1320;  // Hz

// ── Réglages réseau ─────────────────────────────────────────────────────────
constexpr uint32_t WIFI_RETRY_MS     = 10000;  // nouvelle tentative Wi-Fi
constexpr uint32_t MQTT_RETRY_MS     = 5000;   // nouvelle tentative MQTT
constexpr uint16_t MQTT_KEEPALIVE_S  = 15;     // détection de coupure par le broker
constexpr uint16_t MQTT_BUFFER_SIZE  = 512;

const String TOPIC_COMMAND      = String(TOPIC_BASE) + "/command";
const String TOPIC_STATE        = String(TOPIC_BASE) + "/state";
const String TOPIC_MOTION       = String(TOPIC_BASE) + "/motion";
const String TOPIC_AVAILABILITY = String(TOPIC_BASE) + "/availability";

WiFiClientSecure tlsClient;
PubSubClient     mqtt(tlsClient);

bool     wifiConnected     = false;
bool     mqttConnected     = false;
uint32_t lastWifiAttemptMs = 0;
uint32_t lastMqttAttemptMs = 0;

// ── Machine à états ─────────────────────────────────────────────────────────
enum class AlarmState { DISARMED, ARMED, TRIGGERED };

AlarmState alarmState = AlarmState::DISARMED;

bool     lastPirLevel   = LOW;   // pour détecter le front montant LOW → HIGH
bool     redLedOn       = false;
bool     sirenHighTone  = false;
uint32_t lastBlinkMs    = 0;
uint32_t lastSirenMs    = 0;
String   serialBuffer;

const char *stateName(AlarmState state) {
  switch (state) {
    case AlarmState::DISARMED:  return "DISARMED";
    case AlarmState::ARMED:     return "ARMED";
    case AlarmState::TRIGGERED: return "TRIGGERED";
  }
  return "UNKNOWN";
}

// ── Publications MQTT ───────────────────────────────────────────────────────
// Remarque : PubSubClient ne publie qu'en QoS 0 (voir docs/mqtt-topics.md).

void publishState() {
  char payload[40];
  snprintf(payload, sizeof(payload), "{\"state\":\"%s\"}", stateName(alarmState));

  if (mqtt.connected()) {
    const bool ok = mqtt.publish(TOPIC_STATE.c_str(), payload, true);  // retained
    Serial.printf("[STATE ] %s -> %s %s\n", stateName(alarmState), TOPIC_STATE.c_str(),
                  ok ? "(publié)" : "(ÉCHEC publication)");
  } else {
    Serial.printf("[STATE ] %s (MQTT hors ligne : publié à la reconnexion)\n",
                  stateName(alarmState));
  }
}

void publishMotion(uint32_t uptimeMs) {
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"event\":\"MOTION_DETECTED\",\"uptimeMs\":%lu}",
           (unsigned long)uptimeMs);

  if (mqtt.connected()) {
    const bool ok = mqtt.publish(TOPIC_MOTION.c_str(), payload, false);  // jamais retained
    Serial.printf("[MOTION] %s %s\n", payload, ok ? "(publié)" : "(ÉCHEC publication)");
  } else {
    Serial.printf("[MOTION] %s (MQTT hors ligne : événement non transmis)\n", payload);
  }
}

// ── Sorties physiques ───────────────────────────────────────────────────────

void sirenOff() {
  noTone(PIN_BUZZER);
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

    case AlarmState::TRIGGERED: {
      const uint32_t now = millis();
      digitalWrite(PIN_LED_GREEN, HIGH);
      redLedOn      = true;
      sirenHighTone = false;
      lastBlinkMs   = now;
      lastSirenMs   = now;
      digitalWrite(PIN_LED_RED, HIGH);
      tone(PIN_BUZZER, SIREN_FREQ_LOW);
      break;
    }
  }
}

void setState(AlarmState newState) {
  if (newState == alarmState) {
    publishState();  // commande sans effet : on reconfirme l'état courant
    return;
  }
  Serial.printf("[ALARM ] %s -> %s\n", stateName(alarmState), stateName(newState));
  alarmState = newState;
  applyOutputs();
  publishState();
}

// Traite une commande ARM / DISARM, quelle que soit sa provenance (MQTT ou série).
void handleCommand(String command) {
  command.trim();
  command.toUpperCase();

  if (command == "ARM") {
    // ARM pendant TRIGGERED ne doit pas couper la sirène.
    setState(alarmState == AlarmState::DISARMED ? AlarmState::ARMED : alarmState);
  } else if (command == "DISARM") {
    setState(AlarmState::DISARMED);
  } else {
    Serial.printf("[CMD   ] commande inconnue ignorée : \"%s\"\n", command.c_str());
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
  Serial.printf("[MQTT  ] reçu sur %s : %s\n", topic, message.c_str());

  if (TOPIC_COMMAND != topic) {
    return;
  }
  String command;
  if (!extractJsonString(message, "command", command)) {
    Serial.println("[CMD   ] payload invalide ignoré (attendu {\"command\":\"ARM|DISARM\"})");
    return;
  }
  handleCommand(command);
}

// ── Entrées : série (débogage) et PIR ───────────────────────────────────────

// Lecture non bloquante d'une ligne sur le moniteur série.
void readSerialCommand() {
  while (Serial.available() > 0) {
    const char c = static_cast<char>(Serial.read());
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        Serial.printf("[CMD   ] reçu (série) : %s\n", serialBuffer.c_str());
        handleCommand(serialBuffer);
        serialBuffer = "";
      }
    } else if (serialBuffer.length() < 32) {
      serialBuffer += c;
    }
  }
}

// Détecte un NOUVEAU mouvement : uniquement sur le front montant du PIR.
void handlePir() {
  const bool level = digitalRead(PIN_PIR);
  if (level == lastPirLevel) {
    return;
  }
  lastPirLevel = level;
  Serial.printf("[PIR   ] signal %s\n", level == HIGH ? "HIGH" : "LOW");

  if (level != HIGH) {
    return;  // retour à LOW : TRIGGERED reste actif
  }

  switch (alarmState) {
    case AlarmState::ARMED:
      publishMotion(millis());
      setState(AlarmState::TRIGGERED);
      break;
    case AlarmState::TRIGGERED:
      publishMotion(millis());  // nouvelle détection pendant l'alarme : historisée
      break;
    case AlarmState::DISARMED:
      Serial.println("[PIR   ] mouvement ignoré (alarme désactivée)");
      break;
  }
}

// Animation non bloquante de TRIGGERED : LED rouge clignotante + sirène 2 tons.
void updateAlarmOutputs() {
  if (alarmState != AlarmState::TRIGGERED) {
    return;
  }
  const uint32_t now = millis();

  if (now - lastBlinkMs >= RED_BLINK_MS) {
    lastBlinkMs = now;
    redLedOn = !redLedOn;
    digitalWrite(PIN_LED_RED, redLedOn ? HIGH : LOW);
  }

  if (now - lastSirenMs >= SIREN_STEP_MS) {
    lastSirenMs = now;
    sirenHighTone = !sirenHighTone;
    tone(PIN_BUZZER, sirenHighTone ? SIREN_FREQ_HIGH : SIREN_FREQ_LOW);
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
  Serial.printf("[WIFI  ] connexion à \"%s\" (canal %d)...\n", WIFI_SSID, WIFI_CHANNEL);
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD, WIFI_CHANNEL);
  lastWifiAttemptMs = millis();
}

bool connectMqtt() {
  Serial.printf("[MQTT  ] connexion TLS à %s:%d (client %s)...\n",
                MQTT_HOST, MQTT_PORT, MQTT_CLIENT_ID);

  // Last Will : si l'ESP32 disparaît sans prévenir, le broker publie
  // « offline » (retained, QoS 1) sur le topic availability.
  const bool ok = mqtt.connect(MQTT_CLIENT_ID, MQTT_USERNAME, MQTT_PASSWORD,
                               TOPIC_AVAILABILITY.c_str(), 1, true, "offline",
                               true /* cleanSession */);
  if (!ok) {
    const int rc = mqtt.state();
    Serial.printf("[MQTT  ] échec (rc=%d : %s), nouvel essai dans %lus\n",
                  rc, mqttStateLabel(rc), (unsigned long)(MQTT_RETRY_MS / 1000));
    char tlsError[128];
    if (tlsClient.lastError(tlsError, sizeof(tlsError)) != 0) {
      Serial.printf("[TLS   ] %s\n", tlsError);
    }
    return false;
  }

  Serial.println("[MQTT  ] connecté (TLS + authentification OK)");
  mqtt.publish(TOPIC_AVAILABILITY.c_str(), "online", true);  // retained
  Serial.printf("[MQTT  ] %s -> online\n", TOPIC_AVAILABILITY.c_str());

  const bool subscribed = mqtt.subscribe(TOPIC_COMMAND.c_str(), 1);
  Serial.printf("[MQTT  ] abonnement %s (QoS 1) %s\n", TOPIC_COMMAND.c_str(),
                subscribed ? "OK" : "ÉCHEC");

  publishState();  // resynchronise les clients sur l'état réel
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
    Serial.printf("[WIFI  ] connecté, IP %s\n", WiFi.localIP().toString().c_str());
    lastMqttAttemptMs = now - MQTT_RETRY_MS;  // tentative MQTT immédiate
  }

  if (mqtt.connected()) {
    mqtt.loop();
    return;
  }

  if (mqttConnected) {
    Serial.printf("[MQTT  ] connexion perdue (rc=%d : %s)\n", mqtt.state(),
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
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);

  Serial.println();
  Serial.println("=== SmartAlarm — ESP32 + MQTT ===");
  Serial.println("Débogage : ARM ou DISARM dans le moniteur série, puis Entrée.");

  // Sécurité de la démo : on démarre toujours désarmé.
  alarmState   = AlarmState::DISARMED;
  lastPirLevel = digitalRead(PIN_PIR);
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
  handlePir();
  updateAlarmOutputs();
  delay(10);  // court : laisse respirer le CPU sans perturber MQTT
}
