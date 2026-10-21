# Installation et configuration — SmartAlarm

## Prérequis

| Outil | Version constatée | Rôle |
|-------|-------------------|------|
| Flutter | 3.29.3 (stable) | Application mobile et web |
| Dart | 3.7.2 | Langage Flutter |
| Google Chrome | installé | Cible Flutter Web |
| Git | 2.42 | Versionnement |
| Xcode + CocoaPods | installés | Version iOS |
| Android toolchain | SDK 36.1 | Version Android |
| PlatformIO | extension VS Code | Compilation locale du firmware (option recommandée) |

Comptes nécessaires :
- Un compte [Wokwi](https://wokwi.com) (gratuit) pour sauvegarder le projet de simulation.
- Un compte [HiveMQ Cloud](https://console.hivemq.cloud) (gratuit, offre Serverless).

## Configuration HiveMQ Cloud

> ⚠️ **Fin de l'offre Serverless** : HiveMQ ne permet plus de créer de
> cluster Serverless depuis le 30/09/2026. Les clusters existants refusent les
> connexions MQTT après le **31/12/2026** et sont supprimés le 07/01/2027. Ce
> projet utilise un cluster Serverless déjà existant. Après cette date, il
> faudra migrer, par exemple vers un cluster Starter : seuls l'hôte et les
> identifiants changeraient.

### 1. Accéder au cluster

1. Se connecter à <https://console.hivemq.cloud>.
2. Dans **Clusters Overview**, cliquer sur **Manage Cluster** pour le cluster Serverless.
3. Onglet **Overview** : noter les informations suivantes.

| Information | Où la trouver | Valeur attendue |
|-------------|---------------|-----------------|
| Hôte | champ **URL** | `xxxxxxxx.s1.eu.hivemq.cloud`, à recopier **sans** `mqtts://` ni port |
| Port MQTT TLS | **Port** | `8883` (ESP32) |
| Port WebSocket TLS | **Websocket Port** | `8884` (Flutter Web) |
| Chemin WebSocket | (convention HiveMQ) | `/mqtt` |

### 2. Permissions

Sur le cluster gratuit, la console ne propose **pas** de permission par
filtre de topics. Le champ **Permission** n'offre que *Subscribe Only*,
*Publish Only* ou *Publish and Subscribe*, et ces choix s'appliquent à
**tous** les topics (`#`). On choisit donc **Publish and Subscribe** : chaque
client doit pouvoir publier et s'abonner. C'est une limite connue du
prototype.

### 3. Créer deux identifiants MQTT (un par client)

Onglet **Access Management**, section **Authentication**, zone **Credentials** :

| Username | Utilisé par | Permission |
|----------|-------------|------------|
| `smartalarm-esp32` | ESP32 / Wokwi | *Publish and Subscribe* |
| `smartalarm-flutter` | Application Flutter | *Publish and Subscribe* |

Saisir le username (lettres, chiffres, `-`, `+`, `.`, `_` uniquement), un mot
de passe fort et sa confirmation, choisir la permission, puis cliquer sur
**Save**. Il faut **noter le mot de passe** tout de suite :
la console ne le réaffiche plus.

> Ces identifiants servent uniquement au protocole MQTT : ce ne sont pas ceux
> du compte de la console. Deux identifiants séparés permettent de révoquer
> celui de Flutter, qui est exposé dans le navigateur, sans toucher à l'ESP32.

### 4. Reporter la configuration (fichiers locaux, ignorés par Git)

```bash
cp esp32/config.example.h esp32/config.h
cp flutter_app/config/dart_defines.example.json flutter_app/config/dart_defines.json
```

Puis remplacer les `<...>` :
- `esp32/config.h` : `MQTT_HOST`, `MQTT_USERNAME`, `MQTT_PASSWORD` (identifiants ESP32).
- `flutter_app/config/dart_defines.json` : `MQTT_HOST`, `MQTT_USERNAME`, `MQTT_PASSWORD` (identifiants Flutter).

### 5. Vérifier la chaîne TLS du broker (optionnel, en local)

```bash
openssl s_client -connect <votre-cluster>.hivemq.cloud:8883 \
  -servername <votre-cluster>.hivemq.cloud -showcerts </dev/null 2>/dev/null \
  | grep -E "^ *[0-9] s:|i:"
```

La dernière ligne `i:` doit mentionner `ISRG Root X1` ou `ISRG Root X2`. Ce
sont les deux certificats racines embarqués dans `config.example.h`, qui
permettent à l'ESP32 de vérifier l'identité du broker. Depuis 2025, Let's
Encrypt utilise une nouvelle hiérarchie (`YE`/`YR`, puis `Root YE`/`Root YR`),
dont les racines sont signées par X2 et X1 (certificats croisés). Une chaîne
qui affiche par exemple `YE2 → Root YE → X2 → X1` est donc normale.

Résultat constaté le 19/10/2026 sur le cluster du projet (ports 8883 et 8884) :
`*.s1.eu.hivemq.cloud → YR1 → Root YR → ISRG Root X1`, TLS 1.2, clé RSA
2048 bits. La vérification avec le bundle de `config.example.h` aboutit à
`Verify return code: 0 (ok)`.

### 6. Tester Publish / Subscribe avec le Web Client HiveMQ

1. Dans le cluster, ouvrir l'onglet **Web Client**.
2. Se connecter avec l'identifiant `smartalarm-flutter`, puis cliquer sur **Connect Client**.
3. **Topic Subscriptions** : topic `smartalarm/demo01/#`, QoS `1`, puis **Subscribe**.
4. **Send Message** : topic `smartalarm/demo01/command`, payload `{"command":"ARM"}`,
   QoS `1`, **Retain décoché**, puis **Send Message**. Le message doit apparaître dans la liste.
5. **Test du retained** : envoyer sur `smartalarm/demo01/state` le payload
   `{"state":"DISARMED"}` avec **Retain coché**. Se désabonner, puis se
   réabonner à `smartalarm/demo01/#` : le message `state` doit réapparaître
   immédiatement. C'est ce mécanisme qui resynchronisera Flutter.
6. **Nettoyage** : envoyer un payload **vide** avec **Retain coché** sur
   `smartalarm/demo01/state` pour effacer ce retained de test.

## Simulation Wokwi

### Créer le projet

1. Ouvrir <https://wokwi.com/projects/new/esp32>. Se connecter permet de sauvegarder le projet.
2. Onglet **diagram.json** : tout remplacer par le contenu de `esp32/diagram.json`.
3. Onglet **sketch.ino** : tout remplacer par le contenu de `esp32/sketch.ino`.
4. Menu **▾** (à droite des onglets) → **New file…** → `libraries.txt` : coller le contenu de `esp32/libraries.txt`.
5. **Save** (Ctrl/Cmd + S).

### Câblage

| Composant | Broche composant | ESP32 DevKit V1 |
|-----------|------------------|-----------------|
| PIR salon (de droite) | VCC / OUT / GND | 3V3 / **D13** / GND |
| PIR chambre (de gauche) | VCC / OUT / GND | 3V3 / **D33** / GND |
| Buzzer | 2 (+) / 1 (−) | **D25** / GND |
| LED verte (« ARMED ») | A → résistance 220 Ω | **D26** ; C → GND |
| LED rouge (« ALERT ») | A → résistance 220 Ω | **D27** ; C → GND |
| Contact porte (interrupteur de gauche) | 2 (commun) / 1 | **D14** / GND |
| Contact fenêtre (interrupteur de droite) | 2 (commun) / 1 | **D32** / GND |

### Tester la logique locale (sans MQTT)

1. Cliquer sur ▶ (**Start the simulation**). Le moniteur série s'ouvre en bas.
2. Au démarrage, attendu : `[STATE ] DISARMED`. Toutes les LEDs sont éteintes et le buzzer est muet.
3. Cliquer sur le **PIR du salon** (celui de droite), puis sur **Simulate Motion** : `pir_salon ignoré (alarme désactivée)`.
4. Cliquer dans la zone de saisie du moniteur série, taper `ARM`, puis Entrée : `DISARMED -> ARMED`, LED verte allumée.
5. **Simulate Motion** : `[MOTION] …`, puis `ARMED -> TRIGGERED`. La LED rouge clignote et la sirène sonne (activer le son du navigateur).
6. Attendre environ 5 s : le PIR repasse au repos (`[SENSOR] pir_salon IDLE`), mais l'alarme **reste** TRIGGERED.
7. Taper `DISARM` : `TRIGGERED -> DISARMED`. Tout s'éteint et la sirène s'arrête.

### Tester le mode nuit

Les deux interrupteurs à glissière simulent les contacts : position reliée
à GND = fermé. Basculer un interrupteur affiche `[SENSOR] door OPEN` ou
`door CLOSED`. Si une porte apparaît ouverte au repos, la remettre en position
fermée avant de commencer.

1. Taper `ARM_NIGHT` : `DISARMED -> ARMED_NIGHT`, la LED verte clignote lentement.
2. **Simulate Motion** sur chaque PIR : `pir_salon ignoré (mode nuit)`, puis `pir_chambre ignoré (mode nuit)`. Rien ne se déclenche.
3. Basculer l'interrupteur de la **porte** : `[MOTION] {"event":"OPENING_DETECTED","sensor":"door",…}`,
   puis `ARMED_NIGHT -> TRIGGERED`.
4. Taper `DISARM`. Refermer la porte.

### Tester la détection par pièce

1. Taper `ARM`.
2. **Simulate Motion** sur le **PIR de la chambre** (celui de gauche) :
   `[ALARM ] intrusion dans : chambre (pir_chambre)`, puis
   `[MOTION] {"event":"MOTION_DETECTED","sensor":"pir_chambre","room":"chambre",…}`
   et `ARMED -> TRIGGERED`.
3. Dans l'application : bandeau « Intrusion dans la chambre ! ». La pièce
   Chambre passe en rouge, le Salon et l'Entrée restent « Surveillé ».
4. Taper `DISARM`, puis recommencer avec le PIR du salon : c'est cette fois
   le Salon qui passe en rouge.

> Le PIR de Wokwi reste à HIGH pendant `delayTime` = 5 s, puis ignore les
> mouvements pendant `inhibitTime` = 1,2 s. Il faut donc attendre environ 6 s
> entre deux « Simulate Motion » pour obtenir une nouvelle détection.

### Option recommandée : simulateur Wokwi dans VS Code

Le firmware est compilé **en local** avec PlatformIO, puis exécuté dans le
simulateur Wokwi intégré à VS Code. Avantages : `config.h` reste sur la
machine (aucun projet Wokwi public) et aucun copier-coller n'est nécessaire.

Prérequis : extensions VS Code **PlatformIO IDE** et **Wokwi Simulator**.

1. VS Code → **File → Open Folder…** → ouvrir le dossier `smartalarm/esp32`.
   `platformio.ini` et `wokwi.toml` doivent être à la racine de l'espace de
   travail.
2. Première fois seulement : `F1` → **Wokwi: Request a New License**. Une page
   web s'ouvre ; se connecter puis valider. La licence gratuite est à
   renouveler tous les 30 jours.
3. Compiler : icône ✓ **PlatformIO: Build** dans la barre du bas, ou
   `pio run` dans le terminal. Le résultat doit être `[SUCCESS]`.
4. Ouvrir `diagram.json`, puis `F1` → **Wokwi: Start Simulator**.
5. Le moniteur série s'affiche dans le panneau du bas de VS Code.

> **À refaire après chaque modification du sketch :** recompiler (étape 3),
> puis relancer le simulateur.

| Fichier | Rôle |
|---------|------|
| `platformio.ini` | Carte `esp32doit-devkit-v1`, framework Arduino, bibliothèque PubSubClient |
| `wokwi.toml` | Indique au simulateur le firmware compilé (`.pio/build/esp32dev/firmware.bin` et `.elf`) |
| `diagram.json` | Le circuit (identique à celui de wokwi.com) |

### Connexion MQTT

1. Vérifier que **sketch.ino** est à jour avec `esp32/sketch.ino`.
2. Menu **▾** → **New file…** → `config.h` : coller le contenu de votre
   `esp32/config.h` **local** (hôte, identifiants ESP32 et certificats racines).
3. Lancer la simulation. Logs attendus, dans l'ordre :
   ```text
   [STATE ] DISARMED (MQTT hors ligne : publié à la reconnexion)
   [WIFI  ] connexion à "Wokwi-GUEST" (canal 6)...
   [WIFI  ] connecté, IP 10.10.0.2
   [MQTT  ] connexion TLS à xxxx.s1.eu.hivemq.cloud:8883 (client smartalarm-esp32-demo01)...
   [MQTT  ] connecté (TLS + authentification OK)
   [MQTT  ] smartalarm/demo01/availability -> online
   [MQTT  ] abonnement smartalarm/demo01/command (QoS 1) OK
   [STATE ] DISARMED -> smartalarm/demo01/state (publié)
   [SENSOR] {"pir_salon":"IDLE","pir_chambre":"IDLE","door":"CLOSED","window":"CLOSED"} (publié)
   ```

> ⚠️ **Visibilité Wokwi** : avec un compte gratuit, un projet Wokwi
> sauvegardé est **public**. Le fichier `config.h` qu'il contient, avec les
> identifiants, est donc lisible par toute personne qui trouve le projet. Il
> faut utiliser un identifiant MQTT dédié à l'ESP32 avec un mot de passe fort,
> ne pas diffuser le lien, et changer le mot de passe après la soutenance.
> Sinon, ne pas sauvegarder le projet et recoller `config.h` à chaque session.

### Diagnostic de connexion

| Log | Cause probable |
|-----|----------------|
| `rc=4 : identifiants incorrects` | Username ou mot de passe dans `config.h` |
| `rc=5 : non autorisé` | HiveMQ Cloud renvoie ce code pour un **mot de passe ou username incorrect**. Vérifier `config.h`, puis **recompiler** (les identifiants sont intégrés au firmware). |
| `rc=-2 : échec TCP/TLS` + ligne `[TLS   ]` | Hôte mal recopié, port incorrect ou certificat racine. Le message mbedTLS précise la cause. |
| `rc=-4 : délai dépassé` | Broker injoignable ou réseau Wokwi lent : nouvel essai automatique |
| Boucle Wi-Fi | SSID ou canal modifiés dans `config.h` (`Wokwi-GUEST`, `""`, canal 6) |

### Tester avec le Web Client HiveMQ

Abonné à `smartalarm/demo01/#` :

| Action | Attendu dans le Web Client |
|--------|----------------------------|
| Démarrer la simulation | `availability` = `online`, `state` = `{"state":"DISARMED"}`, `sensors` = état des quatre capteurs |
| Publier `{"command":"ARM"}` sur `…/command` (retain décoché) | `state` = `{"state":"ARMED"}`, LED verte allumée |
| PIR salon → **Simulate Motion** | `motion` = `{"event":"MOTION_DETECTED","sensor":"pir_salon","room":"salon","uptimeMs":…}`, puis `state` = `TRIGGERED` |
| Publier `{"command":"ARM_NIGHT"}`, puis basculer la porte | `state` = `ARMED_NIGHT`, puis `motion` = `{"event":"OPENING_DETECTED","sensor":"door","room":"entree",…}` et `state` = `TRIGGERED` |
| Publier `{"command":"DISARM"}` | `state` = `{"state":"DISARMED"}`, sirène coupée |
| Publier `hello` sur `…/command` | Rien ne change. L'ESP32 affiche `payload invalide ignoré` |
| **Arrêter** la simulation (■) | Après environ 90 s (keep-alive de 60 s × 1,5), `availability` = `offline` (Last Will) |
| Se réabonner | `state` et `availability` réapparaissent tout seuls (retained) |

## Application Flutter

### Lancement (Chrome)

```bash
cd flutter_app
cp config/dart_defines.example.json config/dart_defines.json   # une seule fois, puis remplir
flutter pub get
flutter run -d chrome --dart-define-from-file=config/dart_defines.json
```

Sans `--dart-define-from-file`, l'application affiche « Configuration MQTT
incomplète » au lieu de se connecter. On peut aussi saisir le broker
directement dans l'écran **Réglages** (icône ⚙︎ en haut à droite).

### Lancement (iOS)

Prérequis : Xcode et CocoaPods (`pod --version`).

```bash
cd flutter_app
open -a Simulator                     # ou brancher un iPhone
flutter run -d ios --dart-define-from-file=config/dart_defines.json
```

- Sur iOS, l'application utilise `MqttServerClient` en **TLS sur le port 8883**,
  comme Android. Le certificat du broker est validé par le magasin iOS.
- **Face ID sur le simulateur** : menu *Features → Face ID → Enrolled*, puis,
  quand la demande s'affiche, *Features → Face ID → Matching Face* (ou
  *Non-matching Face* pour tester un refus).
- **Sur un iPhone réel** : ouvrir `ios/Runner.xcworkspace` dans Xcode, choisir
  une équipe dans *Signing & Capabilities* (un compte Apple gratuit suffit).
- Limite connue : iOS suspend les connexions réseau d'une application en
  arrière-plan. Les alertes ne sont reçues que lorsque l'application est
  ouverte. Une vraie notification à application fermée exigerait des
  notifications push (APNs) émises par un serveur, hors périmètre.

### Choix techniques

| Élément | Choix |
|---------|-------|
| Package | `mqtt_client` **10.8.0** : dernière version compatible avec Dart 3.7 (Flutter 3.29). Les versions ≥ 10.8.1 exigent Dart 3.8. |
| Web | `MqttBrowserClient` en **WSS** sur `wss://<host>:8884/mqtt`. Le navigateur valide lui-même le certificat. |
| Android | `MqttServerClient` en **TLS** sur le port 8883 (`secure = true`, magasin de certificats du système) |
| Choix de la plateforme | Import conditionnel (`services/mqtt_client_factory.dart`) : le code `dart:io` n'est jamais compilé pour le web |
| Protocole | MQTT 3.1.1 (`setProtocolV311()`), keep-alive 20 s (désactivé par défaut dans `mqtt_client`) |
| Client ID | `smartalarm-flutter-<aléatoire>` : unique par onglet et distinct de l'ESP32 |
| Reconnexion | Tentatives initiales gérées par le service (2 s, 4 s, 8 s… jusqu'à 30 s), puis `autoReconnect` de la bibliothèque, avec réabonnement automatique |
| Resynchronisation | À chaque (ré)abonnement, le broker renvoie les messages retained `state`, `sensors` et `availability` |
| Commandes | QoS 1, jamais retained. L'état affiché ne change qu'à la réception du `state` publié par l'ESP32. |
| Journal | `shared_preferences` : 200 dernières entrées, horodatées à la réception. Seules les vraies transitions sont journalisées (pas l'état retained reçu à chaque connexion). |
| Réglages | Broker saisi dans l'app prioritaire sur `--dart-define`, stocké avec `flutter_secure_storage` (Trousseau iOS, Keystore Android). Un changement relance une connexion neuve. |
| Face ID | `local_auth`, repli sur le code de l'appareil. Exigé uniquement pour DISARM, jamais pour ARM. Indisponible sur le web. |

### Organisation du code

```text
lib/
├── main.dart                       # charge les réglages, crée MqttService + AlarmController,
│                                   # recrée la connexion si le broker change
├── config/   mqtt_config.dart      # paramètres --dart-define
│             app_theme.dart        # Material 3, couleurs vert / bleu / rouge / gris
├── models/   alarm_models.dart     # AlarmState, AlarmCommand, DeviceAvailability, Detection
│             sensor.dart           # capteurs, zones, état publié sur <base>/sensors
│             alarm_event.dart      # entrée du journal d'activité
│             mqtt_topics.dart
├── services/ alarm_connection.dart # interface (remplacée par un faux dans les tests)
│             mqtt_service.dart     # connexion, reconnexion, abonnements, commandes
│             mqtt_client_factory*  # client WSS (web) / TLS (iOS, Android)
│             journal_store.dart    # persistance du journal
│             settings_store.dart   # persistance des réglages (stockage chiffré)
│             device_authenticator.dart # Face ID / Touch ID / code
├── controllers/ alarm_controller.dart    # état affiché, attente de confirmation, journal
│                settings_controller.dart # broker effectif, protection du désarmement
├── screens/  dashboard_screen.dart # mise en page responsive (1 ou 2 colonnes)
│             journal_screen.dart   # journal complet, filtres, regroupé par jour
│             settings_screen.dart  # broker MQTT, sécurité, données
└── widgets/                        # en-tête, bandeaux, carte d'état, boutons, capteurs, sirène, journal
```

Règles du dashboard :
- L'état affiché ne vient **que** des messages MQTT. Le bouton envoie une
  commande, affiche « En attente de confirmation de l'ESP32… » et un
  avertissement si rien n'arrive sous 10 s.
- Commandes désactivées si le broker est déconnecté ou si l'ESP32 est `offline`.
  L'état reste affiché avec le badge « Dernier état connu ».
- Désarmé, deux boutons : « Activer l'alarme » (tous les capteurs) et « Mode nuit »
  (porte et fenêtre). Un avertissement s'affiche si une porte ou une fenêtre est ouverte.
- Journal : la carte « Activité récente » montre les 6 dernières entrées,
  « Tout voir » ouvre le journal complet.
- Désactivation protégée (si activée dans les réglages) : le bouton affiche
  « Confirmation de votre identité… » ; en cas de refus, rien n'est envoyé.

### Vérifications

```bash
flutter analyze                         # analyse statique
flutter test --exclude-tags live        # tests unitaires et widgets (45 tests)
flutter build ios --simulator --debug   # vérifie la compilation iOS
# Test réel dans Chrome (client WSS) — ESP32 simulé démarré :
flutter test --platform chrome --tags live \
  --dart-define-from-file=config/dart_defines.json test/mqtt_live_test.dart
```

> Sur macOS récent, le premier lancement d'un outil Flutter (`impellerc`)
> peut être tué pendant que macOS vérifie le binaire (`ShaderCompilerException`).
> Il suffit de relancer la commande.

## Gestion des secrets

- ESP32 : `esp32/config.h` (ignoré par Git), créé à partir de `esp32/config.example.h`.
- Flutter : identifiants passés au lancement via `--dart-define`, jamais écrits en dur dans le code.
  Ou saisis dans l'écran Réglages : ils sont alors stockés chiffrés sur l'appareil
  (Trousseau iOS, Keystore Android), et non compilés dans l'application.

> ⚠️ **Flutter Web et identifiants** : tout paramètre compilé dans une
> application web (y compris via `--dart-define`) se retrouve dans le
> JavaScript téléchargé par le navigateur. N'importe quel utilisateur peut
> donc le lire. Cette approche est acceptable **uniquement pour une
> démonstration scolaire**, avec des identifiants MQTT dédiés et à privilèges
> limités (restreints à `smartalarm/#` si possible). En production, il
> faudrait une authentification par utilisateur, par exemple un backend qui
> délivre des jetons temporaires.
