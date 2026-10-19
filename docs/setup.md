# Installation et configuration — SmartAlarm

> Ce guide est complété au fil des étapes du projet.

## Prérequis vérifiés (étape 1)

| Outil | Version constatée | Rôle |
|-------|-------------------|------|
| Flutter | 3.29.3 (stable) | Application mobile et web |
| Dart | 3.7.2 | Langage Flutter |
| Google Chrome | installé | Cible Flutter Web |
| Git | 2.42 | Versionnement |
| Android toolchain | SDK 36.1 présent, Android Studio non installé | Optionnel (adaptation Android ultérieure) |
| arduino-cli | **non installé** | Inutile : Wokwi compile le sketch en ligne |

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
prototype, à mentionner dans le README final.

### 3. Créer deux identifiants MQTT (un par client)

Onglet **Access Management**, section **Authentication**, zone **Credentials** :

| Username | Utilisé par | Permission |
|----------|-------------|------------|
| `smartalarm-esp32` | ESP32 / Wokwi | *Publish and Subscribe* |
| `smartalarm-flutter` | Flutter Web | *Publish and Subscribe* |

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
| PIR | VCC / OUT / GND | 3V3 / **D13** / GND |
| Buzzer | 2 (+) / 1 (−) | **D25** / GND |
| LED verte (« ARMED ») | A → résistance 220 Ω | **D26** ; C → GND |
| LED rouge (« ALERT ») | A → résistance 220 Ω | **D27** ; C → GND |

### Tester la logique locale (étape 3, sans MQTT)

1. Cliquer sur ▶ (**Start the simulation**). Le moniteur série s'ouvre en bas.
2. Au démarrage, attendu : `[STATE ] DISARMED`. Toutes les LEDs sont éteintes et le buzzer est muet.
3. Cliquer sur le **PIR**, puis sur **Simulate Motion** : `mouvement ignoré (alarme désactivée)`.
4. Cliquer dans la zone de saisie du moniteur série, taper `ARM`, puis Entrée : `DISARMED -> ARMED`, LED verte allumée.
5. **Simulate Motion** : `[MOTION] …`, puis `ARMED -> TRIGGERED`. La LED rouge clignote et la sirène sonne (activer le son du navigateur).
6. Attendre environ 5 s : le PIR repasse à `LOW` (`[PIR   ] signal LOW`), mais l'alarme **reste** TRIGGERED.
7. Taper `DISARM` : `TRIGGERED -> DISARMED`. Tout s'éteint et la sirène s'arrête.

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

### Connexion MQTT (étape 4)

1. Remplacer **sketch.ino** par la nouvelle version de `esp32/sketch.ino`.
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
| `rc=5 : non autorisé` | Permission de l'identifiant dans HiveMQ |
| `rc=-2 : échec TCP/TLS` + ligne `[TLS   ]` | Hôte mal recopié, port incorrect ou certificat racine. Le message mbedTLS précise la cause. |
| `rc=-4 : délai dépassé` | Broker injoignable ou réseau Wokwi lent : nouvel essai automatique |
| Boucle Wi-Fi | SSID ou canal modifiés dans `config.h` (`Wokwi-GUEST`, `""`, canal 6) |

### Tester avec le Web Client HiveMQ

Abonné à `smartalarm/demo01/#` :

| Action | Attendu dans le Web Client |
|--------|----------------------------|
| Démarrer la simulation | `availability` = `online`, `state` = `{"state":"DISARMED"}` |
| Publier `{"command":"ARM"}` sur `…/command` (retain décoché) | `state` = `{"state":"ARMED"}`, LED verte allumée |
| PIR → **Simulate Motion** | `motion` = `{"event":"MOTION_DETECTED","uptimeMs":…}`, puis `state` = `TRIGGERED` |
| Publier `{"command":"DISARM"}` | `state` = `{"state":"DISARMED"}`, sirène coupée |
| Publier `hello` sur `…/command` | Rien ne change. L'ESP32 affiche `payload invalide ignoré` |
| **Arrêter** la simulation (■) | Après environ 20 s (keep-alive × 1,5), `availability` = `offline` (Last Will) |
| Se réabonner | `state` et `availability` réapparaissent tout seuls (retained) |

## Application Flutter

*À compléter à l'étape 5.*

## Gestion des secrets

- ESP32 : `esp32/config.h` (ignoré par Git), créé à partir de `esp32/config.example.h`.
- Flutter : identifiants passés au lancement via `--dart-define`, jamais écrits en dur dans le code.

> ⚠️ **Flutter Web et identifiants** : tout paramètre compilé dans une
> application web (y compris via `--dart-define`) se retrouve dans le
> JavaScript téléchargé par le navigateur. N'importe quel utilisateur peut
> donc le lire. Cette approche est acceptable **uniquement pour une
> démonstration scolaire**, avec des identifiants MQTT dédiés et à privilèges
> limités (restreints à `smartalarm/#` si possible). En production, il
> faudrait une authentification par utilisateur, par exemple un backend qui
> délivre des jetons temporaires.
