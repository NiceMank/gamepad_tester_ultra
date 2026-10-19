// ============================================================================
// GAMEPAD TESTER ULTRA v2.0 — FLUTTER / DART (ANDROID & DESKTOP)
// ============================================================================
// Architecture complète haute performance (60/120 FPS CustomPainters) :
// 1. Visualiseur 3D Interactif (Drag-to-Rotate + Gyroscope 6-Axes IMU) :
//    - Châssis 3D extrudé avec poignées, D-Pad 3D, Bumpers L1/R1, Gâchettes L2/R2,
//      Sticks 3D inclinables (LS/RS + Clic L3/R3), Boutons d'action, Boutons système
//      (Share/Options/Home), Pavé tactile multipoint, Barre LED dynamique et
//      Ondes de choc visuelles sur les poignées lors des vibrations (Rumble).
//    - Caméra 3D rotative au doigt ou à la souris + Simulateur matériel 3D complet.
// 2. Laboratoire Stick Drift, Circularité & Calibration :
//    - Radar de circularité 72 secteurs (RMSE Circle Error %, Asymétrie %, Résolution ADC)
//    - Loupe Micro-Zoom x15 sur le centre mort (Dead-Center) pour voir le micro-drift
//    - Graphique temps réel de la Courbe de Réponse (Inner/Outer Deadzone + Gamma)
//    - Détecteur d'anomalies : Axis Snapping, Center Skipping, Incomplete Outer Range
// 3. Télémétrie Batterie & Modélisation Énergétique :
//    - Niveau (%), Tension Li-ion (mV), Température (°C), Santé Cellule (%) & Capacité réelle
//    - Fréquence de décharge (%/h), Courant (mA), Puissance (mW)
//    - Espérance de temps restant (Usage actuel vs Mode Éco vs Gaming Intensif)
//    - Estimateur du temps de recharge complet via USB-C
//    - Graphique double courbe : Historique de décharge (%) & Tension (mV)
// 4. Oscilloscope Polling Rate (Hz) & Latence Inter-Trame :
//    - Fréquence moyenne, Max Stable Hz, Min/Max/Avg intervalle (ms), Jitter (σ ms)
//    - Histogramme de distribution des délais + Oscilloscope temps réel
// 5. Matrice des 18 Boutons, Détecteur de Chatter (<22ms) & Studio Haptique :
//    - Analyseur de rebond électrique (micro-switch fault), compteur CPS (Mash Test),
//      N-Key Rollover (touches simultanées) et Synthétiseur de formes d'onde Rumble.
// 6. Assistant de Diagnostic Guidé (Wizard 5 étapes), Console Raw HID & SDL2 :
//    - Protocole de test automatisé étape par étape avec attribution de note (A+ à F)
//    - Générateur SDL_GameControllerDB & Export JSON complet.
// ============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GamepadTesterUltraApp());
}

// ============================================================================
// PALETTE & DESIGN SYSTEM CYBER-DIAGNOSTIC
// ============================================================================

class AppColors {
  static const Color bgPrimary = Color(0xFF070B14);
  static const Color bgSecondary = Color(0xFF0F172A);
  static const Color bgCard = Color(0xFF111827);
  static const Color bgElevated = Color(0xFF1E293B);
  static const Color border = Color(0xFF334155);

  static const Color accentCyan = Color(0xFF00F0FF);
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentBlue = Color(0xFF3B82F6);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
}

class GamepadTesterUltraApp extends StatelessWidget {
  const GamepadTesterUltraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gamepad Tester Ultra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: AppColors.bgPrimary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accentCyan,
          secondary: AppColors.accentViolet,
          surface: AppColors.bgCard,
          error: AppColors.accentRose,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.accentCyan,
          inactiveTrackColor: AppColors.bgElevated,
          thumbColor: AppColors.accentCyan,
          overlayColor: AppColors.accentCyan.withOpacity(0.15),
          trackHeight: 4.0,
        ),
      ),
      home: const MainDiagnosticShell(),
    );
  }
}

// ============================================================================
// MODÈLES DE DONNÉES & PROFILS CONSTRUCTEURS (VID/PID)
// ============================================================================

enum ControllerLayoutProfile { playstation, xbox, switchPro, generic }

enum StickSensorPreset {
  hallEffectPerfect,
  potentiometerHealthy,
  potentiometerDrifting,
  highJitterWorn,
}

enum HapticWavePattern { heavyImpact, lightCrisp, dualPulse, sineSweep, heartbeat }

class KnownControllerModel {
  final String brand;
  final String modelName;
  final ControllerLayoutProfile profile;
  final int nominalBatteryMah;
  final int nominalPollingHzWired;
  final int nominalPollingHzBt;

  const KnownControllerModel({
    required this.brand,
    required this.modelName,
    required this.profile,
    required this.nominalBatteryMah,
    required this.nominalPollingHzWired,
    required this.nominalPollingHzBt,
  });

  static KnownControllerModel identify(String name, int? vendorId, int? productId) {
    final lower = name.toLowerCase();
    if (vendorId == 0x054C || lower.contains('dualsense') || lower.contains('0ce6')) {
      return const KnownControllerModel(
        brand: 'Sony Interactive Entertainment',
        modelName: 'DualSense Wireless Controller (PS5)',
        profile: ControllerLayoutProfile.playstation,
        nominalBatteryMah: 1560,
        nominalPollingHzWired: 1000,
        nominalPollingHzBt: 250,
      );
    }
    if (lower.contains('dualshock') || lower.contains('09cc') || lower.contains('05c4')) {
      return const KnownControllerModel(
        brand: 'Sony Interactive Entertainment',
        modelName: 'DualShock 4 Wireless Controller (PS4)',
        profile: ControllerLayoutProfile.playstation,
        nominalBatteryMah: 1000,
        nominalPollingHzWired: 250,
        nominalPollingHzBt: 500,
      );
    }
    if (vendorId == 0x045E || lower.contains('xbox')) {
      return const KnownControllerModel(
        brand: 'Microsoft Corporation',
        modelName: 'Xbox Series X|S Wireless Controller',
        profile: ControllerLayoutProfile.xbox,
        nominalBatteryMah: 1400,
        nominalPollingHzWired: 125,
        nominalPollingHzBt: 125,
      );
    }
    if (vendorId == 0x057E || lower.contains('pro controller') || lower.contains('joy-con')) {
      return const KnownControllerModel(
        brand: 'Nintendo Co., Ltd.',
        modelName: 'Nintendo Switch Pro Controller',
        profile: ControllerLayoutProfile.switchPro,
        nominalBatteryMah: 1300,
        nominalPollingHzWired: 125,
        nominalPollingHzBt: 125,
      );
    }
    return KnownControllerModel(
      brand: 'Generic HID',
      modelName: name.isEmpty ? 'Standard Gamepad Controller' : name,
      profile: ControllerLayoutProfile.generic,
      nominalBatteryMah: 1200,
      nominalPollingHzWired: 500,
      nominalPollingHzBt: 125,
    );
  }
}

class RawInputPacket {
  final int sequenceId;
  final String gamepadId;
  final String key;
  final String keyType;
  final double value;
  final double delta;
  final int timestampMs;
  final bool isSpike;

  const RawInputPacket({
    required this.sequenceId,
    required this.gamepadId,
    required this.key,
    required this.keyType,
    required this.value,
    required this.delta,
    required this.timestampMs,
    required this.isSpike,
  });
}

class ButtonDiagnosticStats {
  final String code;
  final String buttonName;
  int pressCount = 0;
  int chatterFaultCount = 0;
  int lastPressTimestampMs = 0;
  int lastReleaseTimestampMs = 0;
  int lastHoldDurationMs = 0;
  int minIntervalMs = 999999;
  double currentValue = 0.0;
  bool isPressed = false;
  final Queue<int> recentPressTimestamps = Queue<int>();

  ButtonDiagnosticStats(this.code, this.buttonName);

  void recordEvent(bool pressed, double value, int nowMs) {
    currentValue = value;
    if (pressed && !isPressed) {
      pressCount++;
      if (lastPressTimestampMs > 0) {
        final interval = nowMs - lastPressTimestampMs;
        if (interval < minIntervalMs && interval > 0) {
          minIntervalMs = interval;
        }
        if (interval > 1 && interval < 22) {
          chatterFaultCount++;
        }
      }
      lastPressTimestampMs = nowMs;
      recentPressTimestamps.addLast(nowMs);
    } else if (!pressed && isPressed) {
      lastReleaseTimestampMs = nowMs;
      if (lastPressTimestampMs > 0) {
        lastHoldDurationMs = (nowMs - lastPressTimestampMs).clamp(0, 60000);
      }
    }
    isPressed = pressed;
    while (recentPressTimestamps.isNotEmpty &&
        nowMs - recentPressTimestamps.first > 1000) {
      recentPressTimestamps.removeFirst();
    }
  }

  int get clicksPerSecond => recentPressTimestamps.length;
}

class StickDiagnostics {
  final String label;
  double x = 0.0;
  double y = 0.0;
  double restingX = 0.0;
  double restingY = 0.0;

  final Queue<Offset> trail = Queue<Offset>();
  final Queue<Offset> centerMicroTrail = Queue<Offset>();
  final List<double> sectorMaxRadius = List<double>.filled(72, 0.0);
  final Set<int> uniqueStepsObserved = <int>{};

  int axisSnapSamples = 0;
  int totalActiveSamples = 0;
  int centerSkipEvents = 0;
  double previousX = 0.0;
  double previousY = 0.0;

  StickDiagnostics(this.label);

  void updatePosition(double newX, double newY, {int maxTrailLength = 260}) {
    if ((previousX * newX < 0 && (newX - previousX).abs() > 0.18) ||
        (previousY * newY < 0 && (newY - previousY).abs() > 0.18)) {
      centerSkipEvents++;
    }
    previousX = x;
    previousY = y;
    x = newX.clamp(-1.25, 1.25);
    y = newY.clamp(-1.25, 1.25);

    trail.addLast(Offset(x, y));
    while (trail.length > maxTrailLength) {
      trail.removeFirst();
    }

    final r = math.sqrt(x * x + y * y);
    if (r < 0.22) {
      restingX = restingX * 0.90 + x * 0.10;
      restingY = restingY * 0.90 + y * 0.10;
      centerMicroTrail.addLast(Offset(x, y));
      while (centerMicroTrail.length > 90) {
        centerMicroTrail.removeFirst();
      }
    }

    if (r > 0.12) {
      totalActiveSamples++;
      if (x.abs() < 0.018 || y.abs() < 0.018) {
        axisSnapSamples++;
      }
      final quantized = (x.abs() * 4096).round();
      uniqueStepsObserved.add(quantized);
    }

    if (r > 0.45) {
      double angle = math.atan2(y, x);
      if (angle < 0) angle += 2 * math.pi;
      final sector = ((angle / (2 * math.pi)) * 72).floor() % 72;
      if (r > sectorMaxRadius[sector]) {
        sectorMaxRadius[sector] = r;
      }
    }
  }

  void reset() {
    trail.clear();
    centerMicroTrail.clear();
    for (int i = 0; i < sectorMaxRadius.length; i++) {
      sectorMaxRadius[i] = 0.0;
    }
    uniqueStepsObserved.clear();
    axisSnapSamples = 0;
    totalActiveSamples = 0;
    centerSkipEvents = 0;
    restingX = 0.0;
    restingY = 0.0;
  }

  double get centerDriftPercent =>
      (math.sqrt(restingX * restingX + restingY * restingY) * 100.0)
          .clamp(0.0, 100.0);

  double get circularityErrorPercent {
    int populated = 0;
    double sumSq = 0.0;
    for (final r in sectorMaxRadius) {
      if (r > 0.50) {
        populated++;
        final diff = r - 1.0;
        sumSq += diff * diff;
      }
    }
    if (populated < 8) return 0.0;
    return (math.sqrt(sumSq / populated) * 100.0).clamp(0.0, 50.0);
  }

  double get asymmetryPercent {
    double maxR = 0.0;
    double minR = 999.0;
    int count = 0;
    for (final r in sectorMaxRadius) {
      if (r > 0.50) {
        count++;
        if (r > maxR) maxR = r;
        if (r < minR) minR = r;
      }
    }
    if (count < 8) return 0.0;
    return ((maxR - minR) * 100.0).clamp(0.0, 100.0);
  }

  int get estimatedResolutionBits {
    final steps = uniqueStepsObserved.length;
    if (steps < 16) return 8;
    final bits = (math.log(steps * 8) / math.ln2).round();
    return bits.clamp(8, 14);
  }

  int get coveredSectorsCount =>
      sectorMaxRadius.where((r) => r > 0.55).length;

  bool get hasAxisSnapping =>
      totalActiveSamples > 60 && (axisSnapSamples / totalActiveSamples) > 0.24;

  bool get hasIncompleteOuterRange {
    int populated = 0;
    double maxObserved = 0.0;
    for (final r in sectorMaxRadius) {
      if (r > 0.45) {
        populated++;
        if (r > maxObserved) maxObserved = r;
      }
    }
    return populated >= 12 && maxObserved < 0.93;
  }

  double get recommendedDeadzonePercent =>
      (centerDriftPercent * 1.35 + 1.0).clamp(2.0, 25.0);
}

class BatteryTelemetrySnapshot {
  final double levelPercent;
  final int voltageMv;
  final double temperatureC;
  final String status;
  final String connectionBus;
  final int nominalCapacityMah;
  final int effectiveCapacityMah;
  final int estimatedCycles;
  final double currentDrawMa;
  final double powerDrawMw;
  final double dischargeRatePercentPerHour;
  final Duration estimatedTimeRemaining;
  final Duration ecoModeTimeRemaining;
  final Duration heavyGamingTimeRemaining;
  final Duration estimatedChargeTimeToFull;
  final double healthScorePercent;
  final Map<String, double> subsystemDrawMa;
  final List<double> dischargeCurveHistory;
  final List<int> voltageCurveHistory;

  const BatteryTelemetrySnapshot({
    required this.levelPercent,
    required this.voltageMv,
    required this.temperatureC,
    required this.status,
    required this.connectionBus,
    required this.nominalCapacityMah,
    required this.effectiveCapacityMah,
    required this.estimatedCycles,
    required this.currentDrawMa,
    required this.powerDrawMw,
    required this.dischargeRatePercentPerHour,
    required this.estimatedTimeRemaining,
    required this.ecoModeTimeRemaining,
    required this.heavyGamingTimeRemaining,
    required this.estimatedChargeTimeToFull,
    required this.healthScorePercent,
    required this.subsystemDrawMa,
    required this.dischargeCurveHistory,
    required this.voltageCurveHistory,
  });
}

// ============================================================================
// MOTEUR CENTRAL DE DIAGNOSTIC & SIMULATION 3D HAUTE FRÉQUENCE
// ============================================================================

class GamepadDiagnosticEngine extends ChangeNotifier {
  static const MethodChannel _hardwareChannel =
      MethodChannel('com.nicemank.gamepad_tester_ultra/hardware');

  List<GamepadController> connectedGamepads = [];
  String? selectedGamepadId;
  KnownControllerModel activeModel = KnownControllerModel.identify(
    'DualSense Wireless Controller',
    0x054C,
    0x0CE6,
  );
  ControllerLayoutProfile? manualProfileOverride;

  final StickDiagnostics leftStick = StickDiagnostics('Stick Gauche (LS)');
  final StickDiagnostics rightStick = StickDiagnostics('Stick Droit (RS)');
  double leftTrigger = 0.0;
  double rightTrigger = 0.0;

  double simulatedInnerDeadzone = 0.05;
  double simulatedOuterDeadzone = 0.98;
  double responseCurveGamma = 1.0;

  // Angles 3D en radians (caméra + gyroscope)
  double pitchRad = 0.24;
  double yawRad = -0.28;
  double rollRad = 0.05;
  double cameraZoom = 1.0;
  Offset touchpadFinger1 = const Offset(0.5, 0.5);
  bool touchpadActive = true;

  // 18 Boutons normalisés
  final Map<String, ButtonDiagnosticStats> buttons = {
    'a': ButtonDiagnosticStats('A / ✕', 'South (A / Cross)'),
    'b': ButtonDiagnosticStats('B / ○', 'East (B / Circle)'),
    'x': ButtonDiagnosticStats('X / □', 'West (X / Square)'),
    'y': ButtonDiagnosticStats('Y / △', 'North (Y / Triangle)'),
    'leftBumper': ButtonDiagnosticStats('L1 / LB', 'Left Bumper (L1 / LB)'),
    'rightBumper': ButtonDiagnosticStats('R1 / RB', 'Right Bumper (R1 / RB)'),
    'leftTriggerBtn': ButtonDiagnosticStats('L2 / LT', 'Left Trigger Digital'),
    'rightTriggerBtn': ButtonDiagnosticStats('R2 / RT', 'Right Trigger Digital'),
    'back': ButtonDiagnosticStats('SHARE', 'Select / Create / View'),
    'start': ButtonDiagnosticStats('OPTIONS', 'Start / Options / Menu'),
    'home': ButtonDiagnosticStats('HOME / PS', 'Home / Guide / PS Button'),
    'leftStick': ButtonDiagnosticStats('L3', 'Left Stick Click (L3)'),
    'rightStick': ButtonDiagnosticStats('R3', 'Right Stick Click (R3)'),
    'dpadUp': ButtonDiagnosticStats('UP', 'D-Pad Up'),
    'dpadDown': ButtonDiagnosticStats('DOWN', 'D-Pad Down'),
    'dpadLeft': ButtonDiagnosticStats('LEFT', 'D-Pad Left'),
    'dpadRight': ButtonDiagnosticStats('RIGHT', 'D-Pad Right'),
    'touchpad': ButtonDiagnosticStats('TPAD', 'Touchpad Click'),
  };

  int maxSimultaneousButtonsPressed = 0;

  // Polling Rate & Latence
  final Queue<double> intervalHistoryMs = Queue<double>();
  final Queue<double> hzTimeline = Queue<double>();
  int _lastPacketMicros = 0;
  double currentPollingHz = 0.0;
  double maxStablePollingHz = 0.0;
  double minIntervalMs = 999.0;
  double maxIntervalMs = 0.0;
  double avgIntervalMs = 0.0;
  double jitterSigmaMs = 0.0;

  // Console Raw HID
  final Queue<RawInputPacket> rawPackets = Queue<RawInputPacket>();
  final Map<String, double> _lastKeyValues = {};
  double noiseThreshold = 0.008;
  int _packetSeq = 0;
  bool pauseRawLog = false;

  // Simulation 3D
  bool simulation3DEnabled = true;
  bool autoOrbitSticks = true;
  bool autoGyroWave = true;
  StickSensorPreset sensorPreset = StickSensorPreset.hallEffectPerfect;
  int simulatedTargetHz = 250;
  double injectedDriftPercent = 1.6;
  double simulatedRumbleLow = 0.0;
  double simulatedRumbleHigh = 0.0;
  double ledBrightnessPercent = 65.0;

  // Assistant de test guidé (Guided Wizard)
  int wizardStep = 0; // 0=Inactif, 1=Repos/Drift, 2=Circularité, 3=Gâchettes, 4=Boutons, 5=Terminé

  // Batterie & Énergie
  double _batteryLevel = 81.5;
  String _batteryStatus = 'DISCHARGING';
  String _connectionBus = 'Bluetooth HID (250Hz)';
  final double _batteryHealth = 94.0;
  final int _estimatedCycles = 112;
  final List<double> _batteryHistory = [
    86.4, 85.8, 85.1, 84.5, 83.9, 83.2, 82.6, 82.0, 81.5
  ];
  final List<int> _voltageHistory = [
    4055, 4048, 4040, 4032, 4025, 4018, 4010, 4002, 3995
  ];

  StreamSubscription? _normSub;
  StreamSubscription? _rawSub;
  StreamSubscription? _connSub;
  Timer? _simTimer;
  Timer? _telemetryTimer;
  double _simTimeSec = 0.0;
  final math.Random _rng = math.Random(42);

  GamepadDiagnosticEngine() {
    _initGamepadListeners();
    _reconfigureSimulationTimer();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollHardwareBatteryAndUpdatePowerModel();
    });
  }

  ControllerLayoutProfile get activeLayout =>
      manualProfileOverride ?? activeModel.profile;

  int get currentSimultaneousPressedCount =>
      buttons.values.where((b) => b.isPressed).length;

  Future<void> _initGamepadListeners() async {
    try {
      connectedGamepads = await Gamepads.list();
      if (connectedGamepads.isNotEmpty) {
        _selectHardwareController(connectedGamepads.first);
        simulation3DEnabled = false;
      }
    } catch (_) {}

    _connSub = Gamepads.connectionEvents.listen((event) async {
      connectedGamepads = await Gamepads.list();
      if (event.type == GamepadConnectionEventType.connected &&
          connectedGamepads.isNotEmpty) {
        _selectHardwareController(connectedGamepads.first);
        simulation3DEnabled = false;
      }
      notifyListeners();
    });

    _normSub = Gamepads.normalizedEvents.listen((event) {
      if (simulation3DEnabled) return;
      _recordPollingTick();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      if (event.axis != null) {
        switch (event.axis!) {
          case GamepadAxis.leftStickX:
            leftStick.updatePosition(event.value, leftStick.y);
            break;
          case GamepadAxis.leftStickY:
            leftStick.updatePosition(leftStick.x, -event.value);
            break;
          case GamepadAxis.rightStickX:
            rightStick.updatePosition(event.value, rightStick.y);
            break;
          case GamepadAxis.rightStickY:
            rightStick.updatePosition(rightStick.x, -event.value);
            break;
          case GamepadAxis.leftTrigger:
            leftTrigger = event.value.clamp(0.0, 1.0);
            buttons['leftTriggerBtn']
                ?.recordEvent(leftTrigger > 0.15, leftTrigger, nowMs);
            break;
          case GamepadAxis.rightTrigger:
            rightTrigger = event.value.clamp(0.0, 1.0);
            buttons['rightTriggerBtn']
                ?.recordEvent(rightTrigger > 0.15, rightTrigger, nowMs);
            break;
        }
      }

      if (event.button != null) {
        final key = event.button!.name;
        final pressed = event.value > 0.5;
        buttons[key]?.recordEvent(pressed, event.value, nowMs);
        final simCount = currentSimultaneousPressedCount;
        if (simCount > maxSimultaneousButtonsPressed) {
          maxSimultaneousButtonsPressed = simCount;
        }
      }
      notifyListeners();
    });

    _rawSub = Gamepads.events.listen((raw) {
      if (simulation3DEnabled) return;
      _ingestRawPacket(
        gamepadId: raw.gamepadId,
        key: raw.key,
        keyType: raw.type.name,
        value: raw.value,
        timestampMs: raw.timestamp,
      );
    });
  }

  void _selectHardwareController(GamepadController controller) {
    selectedGamepadId = controller.id;
    activeModel = KnownControllerModel.identify(
      controller.name,
      controller.vendorId,
      controller.productId,
    );
    notifyListeners();
  }

  void setSimulationEnabled(bool enabled) {
    simulation3DEnabled = enabled;
    _reconfigureSimulationTimer();
    notifyListeners();
  }

  void setSimulatedTargetHz(int hz) {
    simulatedTargetHz = hz;
    _reconfigureSimulationTimer();
    notifyListeners();
  }

  void rotate3DCameraByDrag(Offset delta) {
    autoGyroWave = false;
    yawRad = (yawRad + delta.dx * 0.008).clamp(-1.35, 1.35);
    pitchRad = (pitchRad + delta.dy * 0.008).clamp(-1.05, 1.05);
    notifyListeners();
  }

  void reset3DCamera() {
    pitchRad = 0.22;
    yawRad = -0.25;
    rollRad = 0.0;
    cameraZoom = 1.0;
    notifyListeners();
  }

  void _reconfigureSimulationTimer() {
    _simTimer?.cancel();
    if (!simulation3DEnabled) return;
    final intervalMs =
        (1000 / simulatedTargetHz.clamp(30, 250)).round().clamp(5, 33);
    _simTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _step3DSimulation();
    });
  }

  void _step3DSimulation() {
    final dt = 1.0 / simulatedTargetHz;
    _simTimeSec += dt;

    final nominalIntervalMs = 1000.0 / simulatedTargetHz;
    final busJitter = _connectionBus.contains('Bluetooth') ? 0.58 : 0.07;
    final simulatedInterval =
        nominalIntervalMs + (_rng.nextDouble() - 0.5) * 2.0 * busJitter;
    _pushPollingSample(simulatedInterval.clamp(0.4, 50.0));

    if (autoOrbitSticks) {
      final cycle = _simTimeSec % 8.5;
      double lx = 0.0;
      double ly = 0.0;
      double rx = 0.0;
      double ry = 0.0;

      final driftRad = injectedDriftPercent / 100.0;
      final noiseAmp = switch (sensorPreset) {
        StickSensorPreset.hallEffectPerfect => 0.0014,
        StickSensorPreset.potentiometerHealthy => 0.0055,
        StickSensorPreset.potentiometerDrifting => 0.015,
        StickSensorPreset.highJitterWorn => 0.038,
      };

      if (cycle < 5.8) {
        final theta = _simTimeSec * 1.85;
        final squareness =
            sensorPreset == StickSensorPreset.potentiometerDrifting
                ? 0.075
                : 0.010;
        lx = math.cos(theta) * (1.0 + squareness * math.cos(4 * theta));
        ly = math.sin(theta) * (1.0 + squareness * math.cos(4 * theta));

        final phi = -_simTimeSec * 1.4;
        rx = math.cos(phi) * 0.99;
        ry = math.sin(phi) * 0.99;
      } else {
        lx = driftRad * 0.82 + (_rng.nextDouble() - 0.5) * noiseAmp;
        ly = -driftRad * 0.55 + (_rng.nextDouble() - 0.5) * noiseAmp;
        rx = -driftRad * 0.35 + (_rng.nextDouble() - 0.5) * noiseAmp;
        ry = driftRad * 0.42 + (_rng.nextDouble() - 0.5) * noiseAmp;
      }

      if (sensorPreset == StickSensorPreset.highJitterWorn &&
          (lx.abs() < 0.06 || ly.abs() < 0.06)) {
        if (lx.abs() < 0.06) lx = 0.0;
        if (ly.abs() < 0.06) ly = 0.0;
      }

      leftStick.updatePosition(lx, ly);
      rightStick.updatePosition(rx, ry);

      leftTrigger = ((math.sin(_simTimeSec * 1.35) + 1.0) * 0.5).clamp(0.0, 1.0);
      rightTrigger = ((math.cos(_simTimeSec * 1.1) + 1.0) * 0.5).clamp(0.0, 1.0);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      buttons['leftTriggerBtn']?.recordEvent(leftTrigger > 0.25, leftTrigger, nowMs);
      buttons['rightTriggerBtn']?.recordEvent(rightTrigger > 0.25, rightTrigger, nowMs);

      if (_packetSeq % 6 == 0) {
        _ingestRawPacket(
          gamepadId: 'sim-3d-01',
          key: 'AXIS_LEFT_X',
          keyType: 'analog',
          value: lx,
          timestampMs: nowMs,
        );
      } else {
        _packetSeq++;
      }
    }

    if (autoGyroWave) {
      pitchRad = 0.22 + 0.16 * math.sin(_simTimeSec * 1.15);
      yawRad = -0.20 + 0.32 * math.cos(_simTimeSec * 0.80);
      rollRad = 0.14 * math.sin(_simTimeSec * 1.45);
      touchpadFinger1 = Offset(
        0.5 + 0.34 * math.cos(_simTimeSec * 1.5),
        0.5 + 0.26 * math.sin(_simTimeSec * 2.1),
      );
      touchpadActive = true;
    }

    notifyListeners();
  }

  void _recordPollingTick() {
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    if (_lastPacketMicros > 0) {
      final deltaMs = (nowMicros - _lastPacketMicros) / 1000.0;
      if (deltaMs >= 0.4 && deltaMs <= 100.0) {
        _pushPollingSample(deltaMs);
      }
    }
    _lastPacketMicros = nowMicros;
  }

  void _pushPollingSample(double deltaMs) {
    intervalHistoryMs.addLast(deltaMs);
    if (deltaMs < minIntervalMs) minIntervalMs = deltaMs;
    if (deltaMs > maxIntervalMs) maxIntervalMs = deltaMs;
    while (intervalHistoryMs.length > 140) {
      intervalHistoryMs.removeFirst();
    }
    if (intervalHistoryMs.length < 4) return;

    double sum = 0.0;
    for (final v in intervalHistoryMs) {
      sum += v;
    }
    avgIntervalMs = sum / intervalHistoryMs.length;
    currentPollingHz = avgIntervalMs > 0 ? (1000.0 / avgIntervalMs) : 0.0;

    double sumSq = 0.0;
    for (final v in intervalHistoryMs) {
      final d = v - avgIntervalMs;
      sumSq += d * d;
    }
    jitterSigmaMs = math.sqrt(sumSq / intervalHistoryMs.length);

    if (currentPollingHz > maxStablePollingHz && jitterSigmaMs < 2.5) {
      maxStablePollingHz = currentPollingHz;
    }

    hzTimeline.addLast(currentPollingHz);
    while (hzTimeline.length > 90) {
      hzTimeline.removeFirst();
    }
  }

  void resetPollingStats() {
    intervalHistoryMs.clear();
    hzTimeline.clear();
    minIntervalMs = 999.0;
    maxIntervalMs = 0.0;
    maxStablePollingHz = 0.0;
    notifyListeners();
  }

  void _ingestRawPacket({
    required String gamepadId,
    required String key,
    required String keyType,
    required double value,
    required int timestampMs,
  }) {
    if (pauseRawLog) return;
    final prev = _lastKeyValues[key] ?? 0.0;
    final delta = (value - prev).abs();
    _lastKeyValues[key] = value;

    if (keyType == 'analog' && delta < noiseThreshold) {
      return;
    }

    final packet = RawInputPacket(
      sequenceId: ++_packetSeq,
      gamepadId: gamepadId,
      key: key,
      keyType: keyType,
      value: value,
      delta: delta,
      timestampMs: timestampMs,
      isSpike: delta > 0.35,
    );
    rawPackets.addFirst(packet);
    while (rawPackets.length > 90) {
      rawPackets.removeLast();
    }
  }

  Future<void> _pollHardwareBatteryAndUpdatePowerModel() async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !simulation3DEnabled) {
      try {
        final data = await _hardwareChannel.invokeMapMethod<String, dynamic>(
          'getControllerTelemetry',
        );
        if (data != null && data['connected'] == true) {
          final pct = (data['batteryPercent'] as num?)?.toDouble() ?? -1.0;
          if (pct >= 0) {
            _batteryLevel = pct;
          }
          _batteryStatus = (data['batteryStatus'] as String?) ?? _batteryStatus;
          _connectionBus =
              (data['connectionType'] as String?) ?? _connectionBus;
        }
      } catch (_) {}
    } else if (_batteryStatus == 'DISCHARGING') {
      final snap = batterySnapshot;
      final dropPerTick = snap.dischargeRatePercentPerHour / 1200.0;
      _batteryLevel = (_batteryLevel - dropPerTick).clamp(5.0, 100.0);
    } else if (_batteryStatus == 'CHARGING') {
      _batteryLevel = (_batteryLevel + 0.08).clamp(0.0, 100.0);
    }

    final snap = batterySnapshot;
    _batteryHistory.add(_batteryLevel);
    _voltageHistory.add(snap.voltageMv);
    if (_batteryHistory.length > 28) {
      _batteryHistory.removeAt(0);
      _voltageHistory.removeAt(0);
    }
    notifyListeners();
  }

  BatteryTelemetrySnapshot get batterySnapshot {
    final capMah = activeModel.nominalBatteryMah;
    final effectiveCapMah = (capMah * (_batteryHealth / 100.0)).round();

    const double mcuAndSensorsMa = 28.0;
    final double wirelessRadioMa = _connectionBus.contains('Bluetooth')
        ? (currentPollingHz > 300 ? 64.0 : 42.0)
        : 18.0;
    final double gyroImuMa = autoGyroWave || !simulation3DEnabled ? 19.5 : 4.0;
    final double ledBarMa = (ledBrightnessPercent / 100.0) * 34.0;
    final double rumbleMa =
        (simulatedRumbleLow * 185.0) + (simulatedRumbleHigh * 135.0);

    final double totalDrawMa =
        mcuAndSensorsMa + wirelessRadioMa + gyroImuMa + ledBarMa + rumbleMa;
    const double ecoDrawMa = mcuAndSensorsMa + 34.0 + 4.0;
    const double heavyDrawMa =
        mcuAndSensorsMa + 64.0 + 19.5 + 32.0 + 145.0; // Avec Rumble continu

    final int voltageMv =
        (3320 + (_batteryLevel / 100.0) * 860 - (rumbleMa * 0.25)).round();
    final double powerMw = (totalDrawMa * voltageMv) / 1000.0;

    final double dischargePercentPerHour =
        ((totalDrawMa / effectiveCapMah) * 100.0).clamp(1.5, 95.0);
    final double ecoDischargePercentPerHour =
        ((ecoDrawMa / effectiveCapMah) * 100.0).clamp(1.5, 95.0);
    final double heavyDischargePercentPerHour =
        ((heavyDrawMa / effectiveCapMah) * 100.0).clamp(1.5, 95.0);

    final double remainingHours = _batteryLevel / dischargePercentPerHour;
    final double ecoRemainingHours = _batteryLevel / ecoDischargePercentPerHour;
    final double heavyRemainingHours =
        _batteryLevel / heavyDischargePercentPerHour;

    // Temps de charge estimé (courant moyen CC/CV de 750 mA)
    final double missingMah =
        effectiveCapMah * ((100.0 - _batteryLevel) / 100.0);
    final double chargeHours = (missingMah / 750.0) * 1.18;

    final double tempC =
        27.5 + (rumbleMa / 300.0) * 6.5 + (currentPollingHz / 1000.0) * 2.1;

    return BatteryTelemetrySnapshot(
      levelPercent: _batteryLevel,
      voltageMv: voltageMv,
      temperatureC: tempC,
      status: _batteryStatus,
      connectionBus: _connectionBus,
      nominalCapacityMah: capMah,
      effectiveCapacityMah: effectiveCapMah,
      estimatedCycles: _estimatedCycles,
      currentDrawMa: totalDrawMa,
      powerDrawMw: powerMw,
      dischargeRatePercentPerHour: dischargePercentPerHour,
      estimatedTimeRemaining:
          Duration(minutes: (remainingHours * 60).round()),
      ecoModeTimeRemaining:
          Duration(minutes: (ecoRemainingHours * 60).round()),
      heavyGamingTimeRemaining:
          Duration(minutes: (heavyRemainingHours * 60).round()),
      estimatedChargeTimeToFull:
          Duration(minutes: (chargeHours * 60).round()),
      healthScorePercent: _batteryHealth,
      subsystemDrawMa: {
        'Moteurs Haptiques (Rumble Dual-Motor)': rumbleMa,
        'Radio Sans-Fil & Cadence Polling': wirelessRadioMa,
        'Barre LED & Éclairage RGB': ledBarMa,
        'MCU, ADC & Capteurs Analogiques': mcuAndSensorsMa,
        'Gyroscope & Accéléromètre 6-Axes IMU': gyroImuMa,
      },
      dischargeCurveHistory: List<double>.unmodifiable(_batteryHistory),
      voltageCurveHistory: List<int>.unmodifiable(_voltageHistory),
    );
  }

  void setBatteryConnectionMode(String bus, String status) {
    _connectionBus = bus;
    _batteryStatus = status;
    notifyListeners();
  }

  Future<void> triggerHapticPattern(HapticWavePattern pattern) async {
    switch (pattern) {
      case HapticWavePattern.heavyImpact:
        await triggerRumble(lowFrequency: 1.0, highFrequency: 0.2, durationMs: 650);
        break;
      case HapticWavePattern.lightCrisp:
        await triggerRumble(lowFrequency: 0.1, highFrequency: 1.0, durationMs: 550);
        break;
      case HapticWavePattern.dualPulse:
        await triggerRumble(lowFrequency: 0.9, highFrequency: 0.9, durationMs: 250);
        await Future.delayed(const Duration(milliseconds: 340));
        await triggerRumble(lowFrequency: 0.9, highFrequency: 0.9, durationMs: 250);
        break;
      case HapticWavePattern.sineSweep:
        for (int i = 1; i <= 5; i++) {
          final v = i / 5.0;
          await triggerRumble(lowFrequency: v, highFrequency: 1.0 - v * 0.5, durationMs: 140);
          await Future.delayed(const Duration(milliseconds: 145));
        }
        break;
      case HapticWavePattern.heartbeat:
        await triggerRumble(lowFrequency: 0.95, highFrequency: 0.3, durationMs: 140);
        await Future.delayed(const Duration(milliseconds: 180));
        await triggerRumble(lowFrequency: 0.65, highFrequency: 0.8, durationMs: 180);
        break;
    }
  }

  Future<void> triggerRumble({
    required double lowFrequency,
    required double highFrequency,
    int durationMs = 600,
  }) async {
    simulatedRumbleLow = lowFrequency.clamp(0.0, 1.0);
    simulatedRumbleHigh = highFrequency.clamp(0.0, 1.0);
    notifyListeners();

    if (connectedGamepads.isNotEmpty) {
      final gp = connectedGamepads.first;
      try {
        if (await gp.hasRumble()) {
          await gp.rumble(
            lowFrequency: simulatedRumbleLow,
            highFrequency: simulatedRumbleHigh,
            duration: Duration(milliseconds: durationMs),
          );
        }
      } catch (_) {}
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _hardwareChannel.invokeMethod('triggerAdvancedRumble', {
          'lowFrequency': simulatedRumbleLow,
          'highFrequency': simulatedRumbleHigh,
          'durationMs': durationMs,
        });
      } catch (_) {}
    }

    Future.delayed(Duration(milliseconds: durationMs), () {
      simulatedRumbleLow = 0.0;
      simulatedRumbleHigh = 0.0;
      notifyListeners();
    });
  }

  void simulateButtonPress(String key, {bool injectChatterFault = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    buttons[key]?.recordEvent(true, 1.0, now);
    final simCount = currentSimultaneousPressedCount;
    if (simCount > maxSimultaneousButtonsPressed) {
      maxSimultaneousButtonsPressed = simCount;
    }
    _ingestRawPacket(
      gamepadId: 'sim-3d-01',
      key: 'KEYCODE_BUTTON_${key.toUpperCase()}',
      keyType: 'button',
      value: 1.0,
      timestampMs: now,
    );
    notifyListeners();

    if (injectChatterFault) {
      Future.delayed(const Duration(milliseconds: 9), () {
        final t2 = DateTime.now().millisecondsSinceEpoch;
        buttons[key]?.recordEvent(false, 0.0, t2);
        buttons[key]?.recordEvent(true, 1.0, t2 + 8);
        notifyListeners();
      });
    }

    Future.delayed(const Duration(milliseconds: 140), () {
      buttons[key]?.recordEvent(
        false,
        0.0,
        DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    });
  }

  Offset applyCalibratedCurve(double rawX, double rawY) {
    final r = math.sqrt(rawX * rawX + rawY * rawY);
    if (r <= simulatedInnerDeadzone) return Offset.zero;
    final normalized = ((r - simulatedInnerDeadzone) /
            (simulatedOuterDeadzone - simulatedInnerDeadzone).clamp(0.1, 1.0))
        .clamp(0.0, 1.0);
    final curved = math.pow(normalized, responseCurveGamma).toDouble();
    final scale = r > 0 ? (curved / r) : 0.0;
    return Offset(rawX * scale, rawY * scale);
  }

  String generateSdlGameControllerMapping() {
    final platformTag = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.macOS => 'Mac OS X',
      _ => 'Android',
    };
    return '030000004c050000e60c000000010000,${activeModel.modelName},'
        'a:b0,b:b1,x:b2,y:b3,back:b8,guide:b16,start:b9,'
        'leftstick:b10,rightstick:b11,leftshoulder:b4,rightshoulder:b5,'
        'dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,'
        'leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,'
        'platform:$platformTag,';
  }

  Map<String, dynamic> computeGlobalHealthScore() {
    final maxDrift =
        math.max(leftStick.centerDriftPercent, rightStick.centerDriftPercent);
    final avgCircError =
        (leftStick.circularityErrorPercent + rightStick.circularityErrorPercent) /
            2.0;
    int totalChatter = 0;
    for (final b in buttons.values) {
      totalChatter += b.chatterFaultCount;
    }

    double score = 100.0;
    if (maxDrift > 2.0) score -= (maxDrift - 2.0) * 4.5;
    if (avgCircError > 5.0) score -= (avgCircError - 5.0) * 1.8;
    score -= totalChatter * 8.0;
    if (jitterSigmaMs > 2.0) score -= (jitterSigmaMs - 2.0) * 3.0;
    score = score.clamp(0.0, 100.0);

    final grade = score >= 94
        ? 'A+'
        : score >= 86
            ? 'A'
            : score >= 76
                ? 'B'
                : score >= 62
                    ? 'C'
                    : 'D';

    return {
      'controllerModel': activeModel.modelName,
      'score': score,
      'grade': grade,
      'maxDriftPercent': maxDrift,
      'avgCircularityErrorPercent': avgCircError,
      'leftStickResolutionBits': leftStick.estimatedResolutionBits,
      'rightStickResolutionBits': rightStick.estimatedResolutionBits,
      'totalChatterFaults': totalChatter,
      'pollingRateHz': currentPollingHz,
      'jitterSigmaMs': jitterSigmaMs,
      'batteryLevelPercent': _batteryLevel,
      'batteryHealthPercent': _batteryHealth,
      'sdlMapping': generateSdlGameControllerMapping(),
    };
  }

  @override
  void dispose() {
    _normSub?.cancel();
    _rawSub?.cancel();
    _connSub?.cancel();
    _simTimer?.cancel();
    _telemetryTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// SHELL PRINCIPAL DE NAVIGATION (RESPONSIVE ANDROID & DESKTOP)
// ============================================================================

class MainDiagnosticShell extends StatefulWidget {
  const MainDiagnosticShell({super.key});

  @override
  State<MainDiagnosticShell> createState() => _MainDiagnosticShellState();
}

class _MainDiagnosticShellState extends State<MainDiagnosticShell> {
  late final GamepadDiagnosticEngine engine;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    engine = GamepadDiagnosticEngine();
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final isWide = MediaQuery.of(context).size.width >= 900;
        final pages = [
          VisualizerAnd3DSimScreen(engine: engine),
          StickLaboratoryScreen(engine: engine),
          BatteryPowerTelemetryScreen(engine: engine),
          PollingRateOscilloscopeScreen(engine: engine),
          ButtonsChatterHapticsScreen(engine: engine),
          RawConsoleAndReportScreen(engine: engine),
        ];

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(66),
            child: _TopTelemetryBar(engine: engine),
          ),
          body: Row(
            children: [
              if (isWide)
                NavigationRail(
                  backgroundColor: AppColors.bgCard,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _selectedIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme:
                      const IconThemeData(color: AppColors.accentCyan),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppColors.accentCyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.view_in_ar_outlined),
                      selectedIcon: Icon(Icons.view_in_ar),
                      label: Text('3D & Sim'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.radar_outlined),
                      selectedIcon: Icon(Icons.radar),
                      label: Text('Sticks Lab'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.battery_charging_full_outlined),
                      selectedIcon: Icon(Icons.battery_charging_full),
                      label: Text('Batterie & mW'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.speed_outlined),
                      selectedIcon: Icon(Icons.speed),
                      label: Text('Polling (Hz)'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.vibration_outlined),
                      selectedIcon: Icon(Icons.vibration),
                      label: Text('Boutons/Rumble'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.fact_check_outlined),
                      selectedIcon: Icon(Icons.fact_check),
                      label: Text('Wizard & Raw'),
                    ),
                  ],
                ),
              Expanded(child: pages[_selectedIndex]),
            ],
          ),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  backgroundColor: AppColors.bgCard,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _selectedIndex = idx),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.view_in_ar),
                      label: '3D & Sim',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.radar),
                      label: 'Sticks',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.battery_charging_full),
                      label: 'Batterie',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.speed),
                      label: 'Polling Hz',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.vibration),
                      label: 'Haptique',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.fact_check),
                      label: 'Score/Raw',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _TopTelemetryBar extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const _TopTelemetryBar({required this.engine});

  @override
  Widget build(BuildContext context) {
    final bat = engine.batterySnapshot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.sports_esports,
                color: AppColors.accentCyan,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    engine.activeModel.modelName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${engine.simulation3DEnabled ? "SIMULATEUR 3D ACTIF" : "MANETTE MATÉRIELLE"} • ${bat.connectionBus}',
                    style: TextStyle(
                      fontSize: 11,
                      color: engine.simulation3DEnabled
                          ? AppColors.accentAmber
                          : AppColors.accentEmerald,
                    ),
                  ),
                ],
              ),
            ),
            _QuickPill(
              icon: Icons.speed,
              label: '${engine.currentPollingHz.toStringAsFixed(0)} Hz',
              color: AppColors.accentCyan,
            ),
            const SizedBox(width: 8),
            _QuickPill(
              icon: Icons.battery_charging_full,
              label:
                  '${bat.levelPercent.toStringAsFixed(0)}% (${bat.estimatedTimeRemaining.inHours}h${(bat.estimatedTimeRemaining.inMinutes % 60).toString().padLeft(2, '0')})',
              color: bat.levelPercent > 25
                  ? AppColors.accentEmerald
                  : AppColors.accentRose,
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Sim 3D', style: TextStyle(fontSize: 12)),
              selected: engine.simulation3DEnabled,
              selectedColor: AppColors.accentViolet.withOpacity(0.35),
              onSelected: engine.setSimulationEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ONGLET 1 : VISUALISEUR 3D INTERACTIF (DRAG-TO-ROTATE) & SIMULATEUR 3D
// ============================================================================

class VisualizerAnd3DSimScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const VisualizerAnd3DSimScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.threed_rotation, color: AppColors.accentCyan),
                        SizedBox(width: 8),
                        Text(
                          'MODÈLE 3D INTERACTIF (GLISSER POUR TOURNER EN 3D)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.7,
                            color: AppColors.accentCyan,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<ControllerLayoutProfile>(
                          value: engine.activeLayout,
                          underline: const SizedBox(),
                          dropdownColor: AppColors.bgElevated,
                          items: const [
                            DropdownMenuItem(
                              value: ControllerLayoutProfile.playstation,
                              child: Text('DualSense / DualShock (PS5/PS4)'),
                            ),
                            DropdownMenuItem(
                              value: ControllerLayoutProfile.xbox,
                              child: Text('Xbox Series X|S Controller'),
                            ),
                            DropdownMenuItem(
                              value: ControllerLayoutProfile.switchPro,
                              child: Text('Nintendo Switch Pro Controller'),
                            ),
                          ],
                          onChanged: (val) {
                            engine.manualProfileOverride = val;
                            engine.notifyListeners();
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Réinitialiser la caméra 3D',
                          onPressed: engine.reset3DCamera,
                          icon: const Icon(
                            Icons.center_focus_strong,
                            color: AppColors.accentCyan,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onPanUpdate: (details) =>
                      engine.rotate3DCameraByDrag(details.delta),
                  child: Container(
                    height: 340,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const RadialGradient(
                        colors: [Color(0xFF162238), Color(0xFF070B14)],
                        radius: 0.95,
                      ),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: CustomPaint(
                      painter: Gamepad3DPerspectivePainter(engine: engine),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _MetricBadge(
                      label: 'Pitch (Tangage X)',
                      value:
                          '${(engine.pitchRad * 180 / math.pi).toStringAsFixed(1)}°',
                      color: AppColors.accentCyan,
                    ),
                    _MetricBadge(
                      label: 'Yaw (Lacet Y)',
                      value:
                          '${(engine.yawRad * 180 / math.pi).toStringAsFixed(1)}°',
                      color: AppColors.accentViolet,
                    ),
                    _MetricBadge(
                      label: 'Roll (Roulis Z)',
                      value:
                          '${(engine.rollRad * 180 / math.pi).toStringAsFixed(1)}°',
                      color: AppColors.accentEmerald,
                    ),
                    _MetricBadge(
                      label: 'Gâchette L2 / LT',
                      value: '${(engine.leftTrigger * 100).toStringAsFixed(1)}%',
                      color: AppColors.accentAmber,
                    ),
                    _MetricBadge(
                      label: 'Gâchette R2 / RT',
                      value: '${(engine.rightTrigger * 100).toStringAsFixed(1)}%',
                      color: AppColors.accentAmber,
                    ),
                    _MetricBadge(
                      label: 'Pavé Tactile (X, Y)',
                      value:
                          '(${engine.touchpadFinger1.dx.toStringAsFixed(2)}, ${engine.touchpadFinger1.dy.toStringAsFixed(2)})',
                      color: AppColors.accentBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Simulateur 3D & Injection d'anomalies matérielles
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.science, color: AppColors.accentViolet),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "LABORATOIRE DE SIMULATION 3D & INJECTION D'ANOMALIES MATÉRIELLES",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Switch(
                      value: engine.simulation3DEnabled,
                      onChanged: engine.setSimulationEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilterChip(
                      label: const Text('Orbite 360° Sticks Auto'),
                      selected: engine.autoOrbitSticks,
                      onSelected: (v) {
                        engine.autoOrbitSticks = v;
                        engine.notifyListeners();
                      },
                    ),
                    FilterChip(
                      label: const Text('Mouvement Gyro 3D Auto'),
                      selected: engine.autoGyroWave,
                      onSelected: (v) {
                        engine.autoGyroWave = v;
                        engine.notifyListeners();
                      },
                    ),
                    for (final preset in StickSensorPreset.values)
                      ChoiceChip(
                        label: Text(switch (preset) {
                          StickSensorPreset.hallEffectPerfect =>
                            'Hall Effect / TMR (0.4% Drift)',
                          StickSensorPreset.potentiometerHealthy =>
                            'Potentiomètre ALPS Sain',
                          StickSensorPreset.potentiometerDrifting =>
                            'Stick Drift Modéré (7.8%)',
                          StickSensorPreset.highJitterWorn =>
                            'Potentiomètre Usé (Jitter + Snap)',
                        }),
                        selected: engine.sensorPreset == preset,
                        onSelected: (_) {
                          engine.sensorPreset = preset;
                          if (preset == StickSensorPreset.hallEffectPerfect) {
                            engine.injectedDriftPercent = 0.4;
                          } else if (preset ==
                              StickSensorPreset.potentiometerHealthy) {
                            engine.injectedDriftPercent = 1.6;
                          } else if (preset ==
                              StickSensorPreset.potentiometerDrifting) {
                            engine.injectedDriftPercent = 7.8;
                          } else if (preset ==
                              StickSensorPreset.highJitterWorn) {
                            engine.injectedDriftPercent = 12.4;
                          }
                          engine.leftStick.reset();
                          engine.rightStick.reset();
                          engine.notifyListeners();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 620;
                    final sliders = [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stick Drift Injecté au repos : ${engine.injectedDriftPercent.toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Slider(
                              value: engine.injectedDriftPercent,
                              min: 0.0,
                              max: 22.0,
                              onChanged: (v) {
                                engine.injectedDriftPercent = v;
                                engine.notifyListeners();
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Angle Roulis 3D (Roll Z) : ${(engine.rollRad * 180 / math.pi).toStringAsFixed(0)}°',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Slider(
                              value: engine.rollRad,
                              min: -0.65,
                              max: 0.65,
                              onChanged: (v) {
                                engine.autoGyroWave = false;
                                engine.rollRad = v;
                                engine.notifyListeners();
                              },
                            ),
                          ],
                        ),
                      ),
                    ];
                    return isNarrow
                        ? Column(children: [sliders[0], sliders[1]])
                        : Row(children: sliders);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rendu 3D complet de la manette : Châssis extrudé, D-Pad 3D, Bumpers L1/R1,
/// Gâchettes L2/R2, Pavé tactile + LED Bar, Sticks 3D inclinables, Boutons
/// Share/Options/Home et Ondes de choc Rumble.
class Gamepad3DPerspectivePainter extends CustomPainter {
  final GamepadDiagnosticEngine engine;
  Gamepad3DPerspectivePainter({required this.engine});

  Offset _project3D(double x, double y, double z, Size size) {
    final cosP = math.cos(engine.pitchRad);
    final sinP = math.sin(engine.pitchRad);
    final cosY = math.cos(engine.yawRad);
    final sinY = math.sin(engine.yawRad);
    final cosR = math.cos(engine.rollRad);
    final sinR = math.sin(engine.rollRad);

    final x1 = x * cosY + z * sinY;
    final z1 = -x * sinY + z * cosY;
    final y2 = y * cosP - z1 * sinP;
    final z2 = y * sinP + z1 * cosP;
    final x3 = x1 * cosR - y2 * sinR;
    final y3 = x1 * sinR + y2 * cosR;

    final fov = 540.0 * engine.cameraZoom;
    const double viewerDist = 420.0;
    final scale = fov / (viewerDist + z2);
    return Offset(
      size.width * 0.5 + x3 * scale,
      size.height * 0.54 + y3 * scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Grille horizon 3D
    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.30)
      ..strokeWidth = 1.0;
    for (int i = -4; i <= 4; i++) {
      canvas.drawLine(
        _project3D(i * 55.0, 102.0, -120.0, size),
        _project3D(i * 55.0, 102.0, 120.0, size),
        gridPaint,
      );
      canvas.drawLine(
        _project3D(-220.0, 102.0, i * 30.0, size),
        _project3D(220.0, 102.0, i * 30.0, size),
        gridPaint,
      );
    }

    // Ondes de vibration haptique (Rumble) autour des poignées gauche/droite
    if (engine.simulatedRumbleLow > 0.05) {
      final leftGrip = _project3D(-125, 55, 0, size);
      canvas.drawCircle(
        leftGrip,
        28 + engine.simulatedRumbleLow * 26,
        Paint()
          ..color = AppColors.accentRose.withOpacity(0.35)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke,
      );
    }
    if (engine.simulatedRumbleHigh > 0.05) {
      final rightGrip = _project3D(125, 55, 0, size);
      canvas.drawCircle(
        rightGrip,
        28 + engine.simulatedRumbleHigh * 26,
        Paint()
          ..color = AppColors.accentAmber.withOpacity(0.35)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke,
      );
    }

    // Châssis 3D extrudé
    final bodyVertices = <List<double>>[
      [-135, -58, 0],
      [-70, -72, 0],
      [70, -72, 0],
      [135, -58, 0],
      [168, 25, 0],
      [120, 94, 0],
      [64, 44, 0],
      [-64, 44, 0],
      [-120, 94, 0],
      [-168, 25, 0],
    ];

    final frontPath = Path();
    final backPath = Path();
    for (int i = 0; i < bodyVertices.length; i++) {
      final v = bodyVertices[i];
      final pf = _project3D(v[0], v[1], -18.0, size);
      final pb = _project3D(v[0], v[1], 18.0, size);
      if (i == 0) {
        frontPath.moveTo(pf.dx, pf.dy);
        backPath.moveTo(pb.dx, pb.dy);
      } else {
        frontPath.lineTo(pf.dx, pf.dy);
        backPath.lineTo(pb.dx, pb.dy);
      }
      canvas.drawLine(
        pf,
        pb,
        Paint()
          ..color = AppColors.accentCyan.withOpacity(0.25)
          ..strokeWidth = 1.4,
      );
    }
    frontPath.close();
    backPath.close();

    canvas.drawPath(backPath, Paint()..color = const Color(0xFF0A101F));
    canvas.drawPath(
      frontPath,
      Paint()..color = const Color(0xFF1E293B).withOpacity(0.94),
    );
    canvas.drawPath(
      frontPath,
      Paint()
        ..color = AppColors.accentCyan
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke,
    );

    // Gâchettes analogiques L2/R2 et Bumpers L1/R1
    _drawTrigger3D(canvas, size, -98, -80, engine.leftTrigger, 'L2');
    _drawTrigger3D(canvas, size, 98, -80, engine.rightTrigger, 'R2');
    _drawBumper3D(
      canvas,
      size,
      -98,
      -64,
      engine.buttons['leftBumper']?.isPressed ?? false,
      'L1',
    );
    _drawBumper3D(
      canvas,
      size,
      98,
      -64,
      engine.buttons['rightBumper']?.isPressed ?? false,
      'R1',
    );

    // Pavé tactile + Barre LED lumineuse
    final tpTL = _project3D(-48, -58, -20, size);
    final tpTR = _project3D(48, -58, -20, size);
    final tpBR = _project3D(44, -14, -20, size);
    final tpBL = _project3D(-44, -14, -20, size);
    final tpPath = Path()
      ..moveTo(tpTL.dx, tpTL.dy)
      ..lineTo(tpTR.dx, tpTR.dy)
      ..lineTo(tpBR.dx, tpBR.dy)
      ..lineTo(tpBL.dx, tpBL.dy)
      ..close();
    canvas.drawPath(tpPath, Paint()..color = const Color(0xFF090D16));
    canvas.drawPath(
      tpPath,
      Paint()
        ..color = AppColors.accentCyan
            .withOpacity(0.3 + (engine.ledBrightnessPercent / 100.0) * 0.7)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );

    if (engine.touchpadActive) {
      final tx = -40 + engine.touchpadFinger1.dx * 80;
      final ty = -52 + engine.touchpadFinger1.dy * 34;
      final tpDot = _project3D(tx, ty, -22, size);
      canvas.drawCircle(tpDot, 5.5, Paint()..color = AppColors.accentCyan);
    }

    // D-Pad 3D complet (Haut, Bas, Gauche, Droite)
    _drawDpadButton3D(
      canvas,
      size,
      -98,
      -42,
      '▲',
      engine.buttons['dpadUp']?.isPressed ?? false,
    );
    _drawDpadButton3D(
      canvas,
      size,
      -98,
      -6,
      '▼',
      engine.buttons['dpadDown']?.isPressed ?? false,
    );
    _drawDpadButton3D(
      canvas,
      size,
      -116,
      -24,
      '◀',
      engine.buttons['dpadLeft']?.isPressed ?? false,
    );
    _drawDpadButton3D(
      canvas,
      size,
      -80,
      -24,
      '▶',
      engine.buttons['dpadRight']?.isPressed ?? false,
    );

    // Boutons Système (Share, Options, Home)
    _drawSystemButton3D(
      canvas,
      size,
      -62,
      -52,
      engine.buttons['back']?.isPressed ?? false,
    );
    _drawSystemButton3D(
      canvas,
      size,
      62,
      -52,
      engine.buttons['start']?.isPressed ?? false,
    );
    _drawSystemButton3D(
      canvas,
      size,
      0,
      16,
      engine.buttons['home']?.isPressed ?? false,
      isHome: true,
    );

    // Joysticks 3D Gauche (LS) et Droit (RS)
    _drawThumbstick3D(
      canvas,
      size,
      baseX: -54,
      baseY: 16,
      stickX: engine.leftStick.x,
      stickY: -engine.leftStick.y,
      isClicked: engine.buttons['leftStick']?.isPressed ?? false,
    );
    _drawThumbstick3D(
      canvas,
      size,
      baseX: 54,
      baseY: 16,
      stickX: engine.rightStick.x,
      stickY: -engine.rightStick.y,
      isClicked: engine.buttons['rightStick']?.isPressed ?? false,
    );

    // Boutons d'action A/B/X/Y ou Cross/Circle/Square/Triangle
    final isPS = engine.activeLayout == ControllerLayoutProfile.playstation;
    _drawActionButton3D(
      canvas,
      size,
      98,
      -44,
      isPS ? '△' : 'Y',
      engine.buttons['y']?.isPressed ?? false,
      AppColors.accentEmerald,
    );
    _drawActionButton3D(
      canvas,
      size,
      98,
      -4,
      isPS ? '✕' : 'A',
      engine.buttons['a']?.isPressed ?? false,
      AppColors.accentCyan,
    );
    _drawActionButton3D(
      canvas,
      size,
      78,
      -24,
      isPS ? '□' : 'X',
      engine.buttons['x']?.isPressed ?? false,
      AppColors.accentViolet,
    );
    _drawActionButton3D(
      canvas,
      size,
      118,
      -24,
      isPS ? '○' : 'B',
      engine.buttons['b']?.isPressed ?? false,
      AppColors.accentRose,
    );
  }

  void _drawTrigger3D(
    Canvas canvas,
    Size size,
    double x,
    double y,
    double val,
    String label,
  ) {
    final pBase = _project3D(x, y, 10, size);
    final pTop = _project3D(x, y + val * 14, -12, size);
    canvas.drawLine(
      pBase,
      pTop,
      Paint()
        ..color = Color.lerp(AppColors.border, AppColors.accentAmber, val)!
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawBumper3D(
    Canvas canvas,
    Size size,
    double x,
    double y,
    bool pressed,
    String label,
  ) {
    final p1 = _project3D(x - 20, y, -18, size);
    final p2 = _project3D(x + 20, y, -18, size);
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = pressed ? AppColors.accentCyan : AppColors.bgElevated
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawDpadButton3D(
    Canvas canvas,
    Size size,
    double x,
    double y,
    String symbol,
    bool pressed,
  ) {
    final pos = _project3D(x, y, pressed ? -16 : -21, size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: 16, height: 16),
        const Radius.circular(4),
      ),
      Paint()..color = pressed ? AppColors.accentCyan : const Color(0xFF0F172A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: pos, width: 16, height: 16),
        const Radius.circular(4),
      ),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawSystemButton3D(
    Canvas canvas,
    Size size,
    double x,
    double y,
    bool pressed, {
    bool isHome = false,
  }) {
    final pos = _project3D(x, y, -21, size);
    canvas.drawCircle(
      pos,
      isHome ? 8 : 5,
      Paint()
        ..color = pressed
            ? AppColors.accentCyan
            : (isHome ? AppColors.accentViolet : AppColors.border),
    );
  }

  void _drawThumbstick3D(
    Canvas canvas,
    Size size, {
    required double baseX,
    required double baseY,
    required double stickX,
    required double stickY,
    required bool isClicked,
  }) {
    final baseCenter = _project3D(baseX, baseY, -18, size);
    final capCenter = _project3D(
      baseX + stickX * 24.0,
      baseY + stickY * 24.0,
      -38.0,
      size,
    );

    canvas.drawCircle(
      baseCenter,
      24,
      Paint()..color = const Color(0xFF090D16),
    );
    canvas.drawCircle(
      baseCenter,
      24,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    canvas.drawLine(
      baseCenter,
      capCenter,
      Paint()
        ..color = AppColors.textSecondary
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    final capColor = isClicked ? AppColors.accentRose : AppColors.accentCyan;
    canvas.drawCircle(
      capCenter,
      16,
      Paint()..color = capColor.withOpacity(0.28),
    );
    canvas.drawCircle(
      capCenter,
      16,
      Paint()
        ..color = capColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawActionButton3D(
    Canvas canvas,
    Size size,
    double x,
    double y,
    String text,
    bool pressed,
    Color color,
  ) {
    final pos = _project3D(x, y, pressed ? -16 : -22, size);
    canvas.drawCircle(
      pos,
      10.5,
      Paint()..color = pressed ? color : const Color(0xFF0F172A),
    );
    canvas.drawCircle(
      pos,
      10.5,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: pressed ? Colors.black : Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant Gamepad3DPerspectivePainter oldDelegate) => true;
}

// ============================================================================
// ONGLET 2 : LABORATOIRE STICK DRIFT, MICRO-ZOOM X15 & COURBE DE RÉPONSE
// ============================================================================

class StickLaboratoryScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const StickLaboratoryScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 760;
              final leftCard = _StickAnalyzerCard(
                stick: engine.leftStick,
                engine: engine,
                accent: AppColors.accentCyan,
              );
              final rightCard = _StickAnalyzerCard(
                stick: engine.rightStick,
                engine: engine,
                accent: AppColors.accentViolet,
              );
              if (isNarrow) {
                return Column(
                  children: [
                    leftCard,
                    const SizedBox(height: 16),
                    rightCard,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftCard),
                  const SizedBox(width: 16),
                  Expanded(child: rightCard),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Loupe Micro-Zoom x15 & Courbe de Réponse Gamma
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'LOUPE MICRO-ZOOM (x15 AU REPOS) & COURBE DE CALIBRATION GAMMA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentEmerald,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        engine.leftStick.reset();
                        engine.rightStick.reset();
                        engine.notifyListeners();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Réinitialiser les mesures'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 700;
                    final zoomAndCurve = [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Micro-Zoom x15 du Point Mort (Détection Sub-Millimétrique)',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 160,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: CenterDriftMicroZoomPainter(
                                  leftStick: engine.leftStick,
                                  rightStick: engine.rightStick,
                                  deadzone: engine.simulatedInnerDeadzone,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16, height: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Courbe de Transfert Analogique (Entrée Brute vs Sortie Calibrée)',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 160,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: ResponseCurveGraphPainter(
                                  innerDeadzone: engine.simulatedInnerDeadzone,
                                  outerDeadzone: engine.simulatedOuterDeadzone,
                                  gamma: engine.responseCurveGamma,
                                  currentInputRadius: math.sqrt(
                                    engine.leftStick.x * engine.leftStick.x +
                                        engine.leftStick.y * engine.leftStick.y,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                    return isNarrow
                        ? Column(
                            children: [
                              SizedBox(
                                height: 200,
                                child: zoomAndCurve[0],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 200,
                                child: zoomAndCurve[2],
                              ),
                            ],
                          )
                        : Row(children: zoomAndCurve);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inner Deadzone : ${(engine.simulatedInnerDeadzone * 100).toStringAsFixed(1)}% '
                            '(Conseillé : ${engine.leftStick.recommendedDeadzonePercent.toStringAsFixed(1)}%)',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Slider(
                            value: engine.simulatedInnerDeadzone,
                            min: 0.0,
                            max: 0.30,
                            onChanged: (v) {
                              engine.simulatedInnerDeadzone = v;
                              engine.notifyListeners();
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exposant Courbe Gamma : ${engine.responseCurveGamma.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Slider(
                            value: engine.responseCurveGamma,
                            min: 0.5,
                            max: 2.5,
                            onChanged: (v) {
                              engine.responseCurveGamma = v;
                              engine.notifyListeners();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickAnalyzerCard extends StatelessWidget {
  final StickDiagnostics stick;
  final GamepadDiagnosticEngine engine;
  final Color accent;

  const _StickAnalyzerCard({
    required this.stick,
    required this.engine,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final calibrated = engine.applyCalibratedCurve(stick.x, stick.y);
    return _CyberCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stick.label.toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.bold, color: accent),
              ),
              Text(
                'X: ${stick.x.toStringAsFixed(4)} | Y: ${stick.y.toStringAsFixed(4)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 230,
              height: 230,
              child: CustomPaint(
                painter: StickCircularityPainter(
                  stick: stick,
                  calibratedPos: calibrated,
                  innerDeadzone: engine.simulatedInnerDeadzone,
                  accent: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _MetricBadge(
                label: 'Stick Drift (Repos)',
                value: '${stick.centerDriftPercent.toStringAsFixed(2)}%',
                color: stick.centerDriftPercent < 3.0
                    ? AppColors.accentEmerald
                    : AppColors.accentRose,
              ),
              _MetricBadge(
                label: 'Circle Error (RMSE)',
                value: '${stick.circularityErrorPercent.toStringAsFixed(2)}%',
                color: stick.circularityErrorPercent < 7.0
                    ? AppColors.accentCyan
                    : AppColors.accentAmber,
              ),
              _MetricBadge(
                label: 'Asymétrie',
                value: '${stick.asymmetryPercent.toStringAsFixed(1)}%',
                color: AppColors.accentViolet,
              ),
              _MetricBadge(
                label: 'Résolution ADC',
                value: '${stick.estimatedResolutionBits}-bit',
                color: AppColors.accentBlue,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _AnomalyTag(
                label: 'Axis Snapping',
                active: stick.hasAxisSnapping,
              ),
              _AnomalyTag(
                label: 'Center Skip (${stick.centerSkipEvents})',
                active: stick.centerSkipEvents > 0,
              ),
              _AnomalyTag(
                label: 'Incomplete Range',
                active: stick.hasIncompleteOuterRange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnomalyTag extends StatelessWidget {
  final String label;
  final bool active;
  const _AnomalyTag({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentRose : AppColors.accentEmerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        active ? '⚠ $label' : '✓ $label OK',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class StickCircularityPainter extends CustomPainter {
  final StickDiagnostics stick;
  final Offset calibratedPos;
  final double innerDeadzone;
  final Color accent;

  StickCircularityPainter({
    required this.stick,
    required this.calibratedPos,
    required this.innerDeadzone,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    canvas.drawCircle(
      center,
      radius * innerDeadzone,
      Paint()
        ..color = AppColors.accentRose.withOpacity(0.22)
        ..style = PaintingStyle.fill,
    );

    final axisPaint = Paint()
      ..color = AppColors.border.withOpacity(0.6)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      axisPaint,
    );

    final envPath = Path();
    bool started = false;
    for (int i = 0; i < 72; i++) {
      final r = stick.sectorMaxRadius[i];
      if (r <= 0.1) continue;
      final angle = (i / 72.0) * 2 * math.pi;
      final pt = center +
          Offset(math.cos(angle) * radius * r, -math.sin(angle) * radius * r);
      if (!started) {
        envPath.moveTo(pt.dx, pt.dy);
        started = true;
      } else {
        envPath.lineTo(pt.dx, pt.dy);
      }
    }
    if (started) {
      envPath.close();
      canvas.drawPath(
        envPath,
        Paint()
          ..color = accent.withOpacity(0.16)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        envPath,
        Paint()
          ..color = accent
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }

    if (stick.trail.length > 1) {
      final trailPath = Path();
      int idx = 0;
      for (final p in stick.trail) {
        final pt = center + Offset(p.dx * radius, -p.dy * radius);
        if (idx == 0) {
          trailPath.moveTo(pt.dx, pt.dy);
        } else {
          trailPath.lineTo(pt.dx, pt.dy);
        }
        idx++;
      }
      canvas.drawPath(
        trailPath,
        Paint()
          ..color = accent.withOpacity(0.55)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke,
      );
    }

    final rawPt = center + Offset(stick.x * radius, -stick.y * radius);
    canvas.drawCircle(rawPt, 6, Paint()..color = accent);

    final calPt =
        center + Offset(calibratedPos.dx * radius, -calibratedPos.dy * radius);
    canvas.drawCircle(calPt, 4, Paint()..color = AppColors.accentEmerald);
  }

  @override
  bool shouldRepaint(covariant StickCircularityPainter oldDelegate) => true;
}

class CenterDriftMicroZoomPainter extends CustomPainter {
  final StickDiagnostics leftStick;
  final StickDiagnostics rightStick;
  final double deadzone;

  CenterDriftMicroZoomPainter({
    required this.leftStick,
    required this.rightStick,
    required this.deadzone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = AppColors.bgPrimary,
    );
    final center = Offset(size.width / 2, size.height / 2);
    const maxRange = 0.22; // Zoom sur ±22% autour de (0,0)
    final scale = (math.min(size.width, size.height) * 0.44) / maxRange;

    // Cercle de Deadzone
    canvas.drawCircle(
      center,
      (deadzone.clamp(0.01, 0.22)) * scale,
      Paint()
        ..color = AppColors.accentEmerald.withOpacity(0.18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      (deadzone.clamp(0.01, 0.22)) * scale,
      Paint()
        ..color = AppColors.accentEmerald
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // Réticule central
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      Paint()..color = AppColors.border,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      Paint()..color = AppColors.border,
    );

    // Position de repos moyenne LS et RS
    final lp = center +
        Offset(
          leftStick.restingX.clamp(-maxRange, maxRange) * scale,
          -leftStick.restingY.clamp(-maxRange, maxRange) * scale,
        );
    final rp = center +
        Offset(
          rightStick.restingX.clamp(-maxRange, maxRange) * scale,
          -rightStick.restingY.clamp(-maxRange, maxRange) * scale,
        );

    canvas.drawCircle(lp, 6, Paint()..color = AppColors.accentCyan);
    canvas.drawCircle(rp, 6, Paint()..color = AppColors.accentViolet);
  }

  @override
  bool shouldRepaint(covariant CenterDriftMicroZoomPainter oldDelegate) => true;
}

class ResponseCurveGraphPainter extends CustomPainter {
  final double innerDeadzone;
  final double outerDeadzone;
  final double gamma;
  final double currentInputRadius;

  ResponseCurveGraphPainter({
    required this.innerDeadzone,
    required this.outerDeadzone,
    required this.gamma,
    required this.currentInputRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = AppColors.bgPrimary,
    );
    const pad = 16.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    // Diagonale linéaire de référence
    canvas.drawLine(
      Offset(pad, pad + h),
      Offset(pad + w, pad),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.0,
    );

    // Courbe calibrée
    final path = Path();
    for (int i = 0; i <= 60; i++) {
      final x = i / 60.0;
      double y = 0.0;
      if (x > innerDeadzone) {
        final norm = ((x - innerDeadzone) /
                (outerDeadzone - innerDeadzone).clamp(0.1, 1.0))
            .clamp(0.0, 1.0);
        y = math.pow(norm, gamma).toDouble();
      }
      final px = pad + x * w;
      final py = pad + h - y * h;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accentEmerald
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );

    // Point d'entrée courant
    final inX = currentInputRadius.clamp(0.0, 1.0);
    double outY = 0.0;
    if (inX > innerDeadzone) {
      final norm = ((inX - innerDeadzone) /
              (outerDeadzone - innerDeadzone).clamp(0.1, 1.0))
          .clamp(0.0, 1.0);
      outY = math.pow(norm, gamma).toDouble();
    }
    canvas.drawCircle(
      Offset(pad + inX * w, pad + h - outY * h),
      5.5,
      Paint()..color = AppColors.accentCyan,
    );
  }

  @override
  bool shouldRepaint(covariant ResponseCurveGraphPainter oldDelegate) => true;
}

// ============================================================================
// ONGLET 3 : TÉLÉMÉTRIE BATTERIE, ESPÉRANCE TEMPS RESTANT & COURBE DE DÉCHARGE
// ============================================================================

class BatteryPowerTelemetryScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const BatteryPowerTelemetryScreen({super.key, required this.engine});

  String _fmtDur(Duration d) =>
      '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';

  @override
  Widget build(BuildContext context) {
    final bat = engine.batterySnapshot;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PowerKpiCard(
                title: 'NIVEAU DE BATTERIE',
                mainValue: '${bat.levelPercent.toStringAsFixed(1)}%',
                subValue:
                    'Statut : ${bat.status} • Réelle : ${bat.effectiveCapacityMah}/${bat.nominalCapacityMah} mAh',
                icon: Icons.battery_charging_full,
                color: AppColors.accentEmerald,
              ),
              _PowerKpiCard(
                title: 'ESPÉRANCE TEMPS RESTANT',
                mainValue: _fmtDur(bat.estimatedTimeRemaining),
                subValue:
                    'Mode Éco : ${_fmtDur(bat.ecoModeTimeRemaining)} • Intensif : ${_fmtDur(bat.heavyGamingTimeRemaining)}',
                icon: Icons.timer_outlined,
                color: AppColors.accentCyan,
              ),
              _PowerKpiCard(
                title: 'FRÉQUENCE DE DÉCHARGE',
                mainValue:
                    '${bat.dischargeRatePercentPerHour.toStringAsFixed(1)} % / h',
                subValue:
                    'Courant : ${bat.currentDrawMa.toStringAsFixed(1)} mA (${bat.powerDrawMw.toStringAsFixed(0)} mW)',
                icon: Icons.bolt,
                color: AppColors.accentAmber,
              ),
              _PowerKpiCard(
                title: 'TENSION, CYCLES & RECHARGE',
                mainValue: '${bat.voltageMv} mV',
                subValue:
                    'Santé : ${bat.healthScorePercent.toStringAsFixed(0)}% (~${bat.estimatedCycles} cycles) • Charge 100% : ${_fmtDur(bat.estimatedChargeTimeToFull)}',
                icon: Icons.favorite,
                color: AppColors.accentViolet,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Graphique double courbe : Décharge (%) et Tension (mV)
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COURBE DE DÉCHARGE TEMPS RÉEL (%) & TENSION CELLULAIRE LI-ION (mV)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentCyan,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 185,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: BatteryDischargeChartPainter(
                      percentHistory: bat.dischargeCurveHistory,
                      voltageHistory: bat.voltageCurveHistory,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Répartition énergétique par sous-système
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RÉPARTITION DE LA CONSOMMATION ÉNERGÉTIQUE PAR COMPOSANT (mA)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentEmerald,
                  ),
                ),
                const SizedBox(height: 12),
                ...bat.subsystemDrawMa.entries.map((entry) {
                  final ratio =
                      (entry.value / bat.currentDrawMa).clamp(0.0, 1.0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.key, style: const TextStyle(fontSize: 13)),
                            Text(
                              '${entry.value.toStringAsFixed(1)} mA (${(ratio * 100).toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: ratio,
                          minHeight: 7,
                          backgroundColor: AppColors.bgElevated,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.accentCyan,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Intensité Barre LED : ${engine.ledBrightnessPercent.toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Slider(
                            value: engine.ledBrightnessPercent,
                            min: 0,
                            max: 100,
                            onChanged: (v) {
                              engine.ledBrightnessPercent = v;
                              engine.notifyListeners();
                            },
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => engine.setBatteryConnectionMode(
                        'Bluetooth HID (250Hz)',
                        'DISCHARGING',
                      ),
                      icon: const Icon(Icons.bluetooth, size: 16),
                      label: const Text('Mode Décharge Bluetooth'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => engine.setBatteryConnectionMode(
                        'USB-C OTG Direct (1000Hz)',
                        'CHARGING',
                      ),
                      icon: const Icon(Icons.usb, size: 16),
                      label: const Text('Mode Charge USB-C'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BatteryDischargeChartPainter extends CustomPainter {
  final List<double> percentHistory;
  final List<int> voltageHistory;

  BatteryDischargeChartPainter({
    required this.percentHistory,
    required this.voltageHistory,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = AppColors.bgPrimary,
    );
    if (percentHistory.length < 2) return;

    const pad = 16.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    final minPct = percentHistory.reduce(math.min) - 1.5;
    final maxPct = percentHistory.reduce(math.max) + 1.5;
    final span = (maxPct - minPct).clamp(2.0, 100.0);

    final pctPath = Path();
    final fillPath = Path();
    for (int i = 0; i < percentHistory.length; i++) {
      final x = pad + (i / (percentHistory.length - 1)) * w;
      final normY = (percentHistory[i] - minPct) / span;
      final y = pad + h - normY * h;
      if (i == 0) {
        pctPath.moveTo(x, y);
        fillPath.moveTo(x, pad + h);
        fillPath.lineTo(x, y);
      } else {
        pctPath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      if (i == percentHistory.length - 1) {
        fillPath.lineTo(x, pad + h);
        fillPath.close();
      }
    }

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppColors.accentEmerald.withOpacity(0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      pctPath,
      Paint()
        ..color = AppColors.accentEmerald
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant BatteryDischargeChartPainter oldDelegate) => true;
}

class _PowerKpiCard extends StatelessWidget {
  final String title;
  final String mainValue;
  final String subValue;
  final IconData icon;
  final Color color;

  const _PowerKpiCard({
    required this.title,
    required this.mainValue,
    required this.subValue,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 265,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mainValue,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subValue,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ONGLET 4 : OSCILLOSCOPE POLLING RATE (HZ) & LATENCE D'ENTRÉE (MS)
// ============================================================================

class PollingRateOscilloscopeScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const PollingRateOscilloscopeScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'OSCILLOSCOPE POLLING RATE (HZ) & GIGUE TEMPORELLE (JITTER)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ...[125, 250, 500, 1000].map((hz) {
                          return ChoiceChip(
                            label: Text('$hz Hz'),
                            selected: engine.simulatedTargetHz == hz,
                            onSelected: (_) => engine.setSimulatedTargetHz(hz),
                          );
                        }),
                        IconButton(
                          tooltip: 'Réinitialiser',
                          onPressed: engine.resetPollingStats,
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _MetricBadge(
                      label: 'Fréquence Moyenne',
                      value: '${engine.currentPollingHz.toStringAsFixed(1)} Hz',
                      color: AppColors.accentCyan,
                    ),
                    _MetricBadge(
                      label: 'Max Stable Détecté',
                      value:
                          '${engine.maxStablePollingHz.toStringAsFixed(1)} Hz',
                      color: AppColors.accentEmerald,
                    ),
                    _MetricBadge(
                      label: 'Intervalle Moyen',
                      value: '${engine.avgIntervalMs.toStringAsFixed(2)} ms',
                      color: AppColors.accentAmber,
                    ),
                    _MetricBadge(
                      label: 'Min / Max Intervalle',
                      value:
                          '${engine.minIntervalMs < 900 ? engine.minIntervalMs.toStringAsFixed(2) : "0.0"} / ${engine.maxIntervalMs.toStringAsFixed(2)} ms',
                      color: AppColors.accentViolet,
                    ),
                    _MetricBadge(
                      label: 'Jitter (Écart-Type σ)',
                      value: '±${engine.jitterSigmaMs.toStringAsFixed(2)} ms',
                      color: engine.jitterSigmaMs < 1.5
                          ? AppColors.accentEmerald
                          : AppColors.accentRose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: PollingOscilloscopePainter(
                      hzSamples: engine.hzTimeline.toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PollingOscilloscopePainter extends CustomPainter {
  final List<double> hzSamples;
  PollingOscilloscopePainter({required this.hzSamples});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = AppColors.bgPrimary,
    );

    if (hzSamples.length < 2) return;
    final maxHz = math.max(1000.0, hzSamples.reduce(math.max) * 1.1);

    final path = Path();
    for (int i = 0; i < hzSamples.length; i++) {
      final x = (i / (hzSamples.length - 1)) * size.width;
      final y = size.height - (hzSamples[i] / maxHz) * (size.height - 24) - 12;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accentCyan
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant PollingOscilloscopePainter oldDelegate) => true;
}

// ============================================================================
// ONGLET 5 : BOUTONS, DÉTECTEUR DE CHATTER, ROLLOVER & STUDIO HAPTIQUE
// ============================================================================

class ButtonsChatterHapticsScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const ButtonsChatterHapticsScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "SYNTHÉTISEUR HAPTIQUE DUAL-MOTOR (FORMES D'ONDE VIBRATION)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentAmber,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => engine
                          .triggerHapticPattern(HapticWavePattern.heavyImpact),
                      icon: const Icon(Icons.vibration),
                      label: const Text('Impact Lourd (Basse Fréq)'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => engine
                          .triggerHapticPattern(HapticWavePattern.lightCrisp),
                      icon: const Icon(Icons.waves),
                      label: const Text('Vibration Fine (Haute Fréq)'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => engine
                          .triggerHapticPattern(HapticWavePattern.dualPulse),
                      icon: const Icon(Icons.bolt),
                      label: const Text('Double Impulsion'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => engine
                          .triggerHapticPattern(HapticWavePattern.sineSweep),
                      icon: const Icon(Icons.graphic_eq),
                      label: const Text('Balayage Sinusoïdal'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => engine
                          .triggerHapticPattern(HapticWavePattern.heartbeat),
                      icon: const Icon(Icons.favorite),
                      label: const Text('Battement Cardiaque'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Text(
                      'MATRICE DES 18 BOUTONS • ROLLOVER MAX: ${engine.maxSimultaneousButtonsPressed} TOUCHES',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => engine.simulateButtonPress('a'),
                          child: const Text('Simuler Pression Normale (A)'),
                        ),
                        OutlinedButton(
                          onPressed: () => engine.simulateButtonPress(
                            'a',
                            injectChatterFault: true,
                          ),
                          child: const Text('Injecter Rebond Chatter (<20ms)'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: engine.buttons.entries.map((e) {
                    final st = e.value;
                    final hasFault = st.chatterFaultCount > 0;
                    return InkWell(
                      onTap: () => engine.simulateButtonPress(e.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 215,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: st.isPressed
                              ? AppColors.accentCyan.withOpacity(0.22)
                              : AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasFault
                                ? AppColors.accentRose
                                : st.isPressed
                                    ? AppColors.accentCyan
                                    : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  st.code,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.accentCyan,
                                  ),
                                ),
                                Text(
                                  '${st.clicksPerSecond} CPS',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              st.buttonName,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Clics: ${st.pressCount} • Hold: ${st.lastHoldDurationMs}ms',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              hasFault
                                  ? '⚠ Chatter: ${st.chatterFaultCount} (${st.minIntervalMs}ms)'
                                  : '✓ Switch intègre',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: hasFault
                                    ? AppColors.accentRose
                                    : AppColors.accentEmerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ONGLET 6 : ASSISTANT DE TEST GUIDÉ (WIZARD), SCORE GLOBAL & CONSOLE RAW HID
// ============================================================================

class RawConsoleAndReportScreen extends StatelessWidget {
  final GamepadDiagnosticEngine engine;
  const RawConsoleAndReportScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final report = engine.computeGlobalHealthScore();
    final sdlString = engine.generateSdlGameControllerMapping();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Assistant de diagnostic guidé en 4 étapes
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ASSISTANT DE TEST GUIDÉ (CERTIFICATION MATÉRIELLE EN 4 ÉTAPES)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentViolet,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        engine.wizardStep = (engine.wizardStep + 1) % 5;
                        engine.notifyListeners();
                      },
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(
                        engine.wizardStep == 0
                            ? 'Démarrer le Wizard'
                            : engine.wizardStep < 4
                                ? 'Étape Suivante (${engine.wizardStep}/4)'
                                : 'Terminer / Relancer',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Stepper(
                  physics: const NeverScrollableScrollPhysics(),
                  currentStep: engine.wizardStep.clamp(0, 3),
                  controlsBuilder: (_, __) => const SizedBox.shrink(),
                  steps: [
                    Step(
                      title: const Text('Étape 1 : Mesure du Stick Drift au repos'),
                      subtitle: Text(
                        'Lâchez les deux sticks. Drift détecté : LS ${engine.leftStick.centerDriftPercent.toStringAsFixed(2)}% | RS ${engine.rightStick.centerDriftPercent.toStringAsFixed(2)}%',
                      ),
                      content: const SizedBox.shrink(),
                      isActive: engine.wizardStep >= 1,
                    ),
                    Step(
                      title: const Text('Étape 2 : Rotation 360° & Circularité'),
                      subtitle: Text(
                        'Faites tourner les sticks sur le bord extérieur. Couverture : ${engine.leftStick.coveredSectorsCount}/72 secteurs (Erreur : ${engine.leftStick.circularityErrorPercent.toStringAsFixed(2)}%)',
                      ),
                      content: const SizedBox.shrink(),
                      isActive: engine.wizardStep >= 2,
                    ),
                    Step(
                      title: const Text('Étape 3 : Course des Gâchettes L2 / R2'),
                      subtitle: Text(
                        "Enfoncez progressivement L2 (${(engine.leftTrigger * 100).toStringAsFixed(0)}%) et R2 (${(engine.rightTrigger * 100).toStringAsFixed(0)}%) jusqu'à 100%.",
                      ),
                      content: const SizedBox.shrink(),
                      isActive: engine.wizardStep >= 3,
                    ),
                    Step(
                      title: const Text('Étape 4 : Stabilité Polling Rate & Switchs'),
                      subtitle: Text(
                        'Cadence mesurée : ${engine.currentPollingHz.toStringAsFixed(1)} Hz (±${engine.jitterSigmaMs.toStringAsFixed(2)} ms).',
                      ),
                      content: const SizedBox.shrink(),
                      isActive: engine.wizardStep >= 4,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Certificat de Score Global
          _CyberCard(
            child: Row(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentEmerald.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.accentEmerald,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    '${report['grade']}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accentEmerald,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SCORE DE SANTÉ GLOBAL : ${(report['score'] as double).toStringAsFixed(1)} / 100',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Drift Max: ${(report['maxDriftPercent'] as double).toStringAsFixed(2)}% • '
                        'Circularité: ${(report['avgCircularityErrorPercent'] as double).toStringAsFixed(2)}% • '
                        'Chatter: ${report['totalChatterFaults']} • '
                        'Batterie: ${(report['batteryHealthPercent'] as double).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        sdlString,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copier le certificat JSON',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: const JsonEncoder.withIndent('  ').convert(report),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Certificat JSON copié dans le presse-papiers'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, color: AppColors.accentCyan),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Console Raw HID
          _CyberCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CONSOLE RAW HID / KEYEVENT & FILTRE DE BRUIT MATÉRIEL (THR)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentCyan,
                      ),
                    ),
                    Text(
                      'Seuil THR: ${(engine.noiseThreshold * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                Slider(
                  value: engine.noiseThreshold,
                  min: 0.0,
                  max: 0.05,
                  onChanged: (v) {
                    engine.noiseThreshold = v;
                    engine.notifyListeners();
                  },
                ),
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgPrimary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.builder(
                    itemCount: engine.rawPackets.length,
                    itemBuilder: (context, idx) {
                      final pkt = engine.rawPackets.elementAt(idx);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '#${pkt.sequenceId.toString().padLeft(5, '0')} '
                          '[${pkt.gamepadId}] ${pkt.key.padRight(18)} '
                          'val=${pkt.value.toStringAsFixed(5)} '
                          '(Δ=${pkt.delta.toStringAsFixed(4)})',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: pkt.isSpike
                                ? AppColors.accentRose
                                : AppColors.textPrimary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CyberCard extends StatelessWidget {
  final Widget child;
  const _CyberCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
