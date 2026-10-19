# Gamepad Tester Ultra (Flutter — Android & Desktop)

Application de diagnostic matériel haute précision pour manettes de jeu (USB-C OTG, Bluetooth Classic/LE et Dongle 2.4GHz), conçue avec **Flutter / Dart** pour **Android**, **Windows**, **Linux** et **macOS**. Elle reproduit l'intégralité des fonctionnalités de [Gamepad Tester](https://play.google.com/store/apps/details?id=com.chimera.saturday.evogamepadtester&hl=en) et intègre les outils d'analyse de laboratoire de [Gamepadla Stick Tracer](https://gamepadla.com/test/), [HardwareTester Gamepad](https://hardwaretester.com/gamepad) et [ControllerTest.io](https://controllertest.io/).

## 1. Architecture des fichiers fournis

| Fichier | Emplacement cible dans le projet Flutter | Rôle | 
| ----- | ----- | ----- | 
| `pubspec.yaml` | `./pubspec.yaml` | Configuration des dépendances ([`gamepads`](https://pub.dev/packages/gamepads) `^0.1.12` et [`flutter_gamepads`](https://pub.dev/packages/flutter_gamepads) `^0.1.2`) | 
| `main.dart` | `./lib/main.dart` | Moteur de diagnostic temps réel, simulateur 3D projectif, télémétrie batterie et interface responsive (6 onglets) | 
| `MainActivity.kt` | `./android/app/src/main/kotlin/com/nicemank/gamepad_tester_ultra/MainActivity.kt` | Pont natif Android (`GamepadsCompatibleActivity` + `MethodChannel` / `EventChannel` pour batterie `InputDevice.BatteryState`, gyroscope et vibrations) | 

## 2. Fonctionnalités intégrées

* **Visualiseur Temps Réel & Simulateur 3D (`VisualizerAnd3DSimScreen`)** : Projection 3D perspective (matrice Pitch, Yaw, Roll) avec inclinaison dynamique des joysticks, enfoncement des gâchettes analogiques `L2/R2`, suivi du pavé tactile et injection d'anomalies matérielles (Stick Drift, bruit capteur Hall Effect vs Potentiomètre ALPS, Axis Snapping) pour tester l'application sans manette branchée.

* **Laboratoire Analogique (`StickLaboratoryScreen`)** : Tracé de circularité sur 72 secteurs angulaires, calcul du *Circle Error (%)*, de l'asymétrie, du *Center Drift (%)* au repos, estimation de la résolution ADC en bits (8-bit à 14-bit), détection automatique du *Center Skipping* / *Axis Snapping*, et simulateur interactif de *Deadzone* et courbe Gamma.

* **Télémétrie Batterie & Énergie (`BatteryPowerTelemetryScreen`)** : Lecture native de `InputDevice.batteryState` (Android 12+) combinée à un modèle énergétique temps réel calculant la tension (`mV`), la température estimée (`°C`), la fréquence de décharge (`% / heure`), la consommation instantanée (`mA` / `mW`), l'espérance de temps restant (usage actuel vs Mode Éco) et la répartition énergétique par composant (Moteurs Rumble, Radio Bluetooth/USB, Barre LED, Gyroscope 6-axes, MCU).

* **Oscilloscope Polling Rate (`PollingRateOscilloscopeScreen`)** : Mesure fréquentielle en temps réel (`Average Hz`, `Max Stable Hz`, latence inter-trame en `ms` et `Jitter σ` en `ms`) avec oscilloscope 120 FPS et profils de test `125 Hz`, `250 Hz`, `500 Hz` et `1000 Hz`.

* **Boutons, Détecteur de Chatter & Studio Haptique (`ButtonsChatterHapticsScreen`)** : Analyseur de rebond électrique (*Button Chatter* / double-clic involontaire `< 22 ms`), compteur de vitesse de clic (*CPS*), et contrôleur de vibrations Dual-Motor basse et haute fréquence.

* **Console Raw HID, SDL2 & Score Global (`RawConsoleAndReportScreen`)** : Flux d'événements bruts avec filtre de bruit matériel (`THR`), générateur de chaîne `SDL_GameControllerDB` multiplateforme et certificat de santé global noté de `A+` à `F` exportable en JSON.

## 3. Installation et exécution (Android & Desktop)

### Prérequis système

* **Flutter SDK** `>= 3.19.0` (Dart `>= 3.3.0`)

* **Android** : Android Studio / SDK API 21+ (API 31+ recommandé pour `InputDevice.BatteryState` et `InputDevice.SensorManager`)

* **Windows** : Visual Studio 2022 avec le composant *Desktop development with C++* (requis par [`gamepads`](https://pub.dev/packages/gamepads) pour l'API native `GameInput`)

* **Linux** : Paquets `libevdev-dev` et `libgtk-3-dev` (`sudo apt install libevdev-dev libgtk-3-dev`)

### Commandes de démarrage rapide

```
# 1. Créer le squelette du projet Flutter avec le bon package name Android
flutter create --org com.nicemank --project-name gamepad_tester_ultra .

# 2. Copier pubspec.yaml à la racine, main.dart dans lib/main.dart,
#    et MainActivity.kt dans android/app/src/main/kotlin/com/nicemank/gamepad_tester_ultra/MainActivity.kt

# 3. Installer les dépendances
flutter pub get

# 4. Lancer sur Android ou Desktop (Windows / Linux / macOS)
flutter run -d android
flutter run -d windows
flutter run -d linux

```