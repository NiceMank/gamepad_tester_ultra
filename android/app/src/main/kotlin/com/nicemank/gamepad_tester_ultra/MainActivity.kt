package com.nicemank.gamepad_tester_ultra

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.input.InputManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

/**
 * Pont natif Android (Kotlin) combinant :
 * 1. GamepadsCompatibleActivity pour le plugin `gamepads` (KeyEvent & MotionEvent).
 * 2. MethodChannel & EventChannel bas niveau pour extraire :
 *    - L'état précis de la batterie de la manette (Android 12+ InputDevice.BatteryState)
 *    - Le type de bus matériel (USB-C OTG, Bluetooth Classic, Bluetooth LE, 2.4GHz)
 *    - La résolution matérielle des capteurs (MotionRange.resolution & flat/fuzz)
 *    - Le Gyroscope / Accéléromètre embarqué dans la manette (DualSense, DualShock 4, Switch Pro)
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {

    companion object {
        private const val HARDWARE_CHANNEL = "com.nicemank.gamepad_tester_ultra/hardware"
        private const val IMU_EVENT_CHANNEL = "com.nicemank.gamepad_tester_ultra/imu_stream"
    }

    private var keyListener: ((KeyEvent) -> Boolean)? = null
    private var motionListener: ((MotionEvent) -> Boolean)? = null
    private var imuEventSink: EventChannel.EventSink? = null
    private var activeSensorManager: SensorManager? = null
    private var activeGyroListener: SensorEventListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getControllerTelemetry" -> {
                        val deviceId = call.argument<Int>("deviceId")
                        result.success(readControllerTelemetry(deviceId))
                    }
                    "triggerAdvancedRumble" -> {
                        val deviceId = call.argument<Int>("deviceId")
                        val lowFreq = call.argument<Double>("lowFrequency") ?: 0.5
                        val highFreq = call.argument<Double>("highFrequency") ?: 0.5
                        val durationMs = call.argument<Int>("durationMs") ?: 300
                        val ok = triggerDeviceRumble(deviceId, lowFreq, highFreq, durationMs.toLong())
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, IMU_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    imuEventSink = events
                    val deviceId = (arguments as? Map<*, *>)?.get("deviceId") as? Int
                    startControllerImuStream(deviceId)
                }

                override fun onCancel(arguments: Any?) {
                    stopControllerImuStream()
                    imuEventSink = null
                }
            })
    }

    /**
     * Lit les métadonnées matérielles et l'état de la batterie d'une manette connectée.
     */
    private fun readControllerTelemetry(requestedDeviceId: Int?): Map<String, Any?> {
        val deviceIds = InputDevice.getDeviceIds()
        var targetDevice: InputDevice? = null

        for (id in deviceIds) {
            val dev = InputDevice.getDevice(id) ?: continue
            val sources = dev.sources
            val isGamepad = (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
                (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
            if (isGamepad) {
                if (requestedDeviceId == null || id == requestedDeviceId) {
                    targetDevice = dev
                    break
                }
            }
        }

        if (targetDevice == null) {
            return mapOf("connected" to false)
        }

        var batteryCapacityPercent = -1.0
        var batteryStatusCode = BatteryManager.BATTERY_STATUS_UNKNOWN
        var batteryPresent = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val batteryState = targetDevice.batteryState
            batteryPresent = batteryState.isPresent
            if (batteryPresent && !batteryState.capacity.isNaN()) {
                batteryCapacityPercent = (batteryState.capacity * 100.0).coerceIn(0.0, 100.0)
            }
            batteryStatusCode = batteryState.status
        }

        val statusLabel = when (batteryStatusCode) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "CHARGING"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "DISCHARGING"
            BatteryManager.BATTERY_STATUS_FULL -> "FULL"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "NOT_CHARGING"
            else -> "UNKNOWN"
        }

        val descriptor = targetDevice.descriptor ?: ""
        val isBluetooth = descriptor.contains(":") || targetDevice.name.contains("Wireless", ignoreCase = true)
        val connectionType = if (isBluetooth) "Bluetooth HID" else "USB-C / OTG Direct"

        val xRange = targetDevice.getMotionRange(MotionEvent.AXIS_X, InputDevice.SOURCE_JOYSTICK)
        val hardwareFlat = xRange?.flat ?: 0.0f
        val hardwareFuzz = xRange?.fuzz ?: 0.0f
        val hardwareResolution = xRange?.resolution ?: 0.0f

        var hasGyro = false
        var hasAccel = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val sm = targetDevice.sensorManager
            hasGyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null
            hasAccel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null
        }

        return mapOf(
            "connected" to true,
            "deviceId" to targetDevice.id,
            "name" to targetDevice.name,
            "vendorId" to targetDevice.vendorId,
            "productId" to targetDevice.productId,
            "descriptor" to descriptor,
            "connectionType" to connectionType,
            "batteryPresent" to batteryPresent,
            "batteryPercent" to batteryCapacityPercent,
            "batteryStatus" to statusLabel,
            "hardwareFlatDeadzone" to hardwareFlat.toDouble(),
            "hardwareFuzzNoise" to hardwareFuzz.toDouble(),
            "hardwareResolution" to hardwareResolution.toDouble(),
            "hasGyroscope" to hasGyro,
            "hasAccelerometer" to hasAccel
        )
    }

    /**
     * Écoute le gyroscope/accéléromètre intégré à la manette (API 31+ InputDevice.sensorManager).
     */
    private fun startControllerImuStream(requestedDeviceId: Int?) {
        stopControllerImuStream()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return

        val deviceIds = InputDevice.getDeviceIds()
        for (id in deviceIds) {
            val dev = InputDevice.getDevice(id) ?: continue
            val isGamepad = (dev.sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
                (dev.sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
            if (!isGamepad) continue
            if (requestedDeviceId != null && id != requestedDeviceId) continue

            val sm = dev.sensorManager
            val gyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE) ?: continue
            activeSensorManager = sm
            activeGyroListener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    imuEventSink?.success(
                        mapOf(
                            "gx" to event.values[0].toDouble(),
                            "gy" to event.values[1].toDouble(),
                            "gz" to event.values[2].toDouble(),
                            "timestampNs" to event.timestamp
                        )
                    )
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            sm.registerListener(activeGyroListener, gyro, SensorManager.SENSOR_DELAY_GAME)
            break
        }
    }

    private fun stopControllerImuStream() {
        activeGyroListener?.let { activeSensorManager?.unregisterListener(it) }
        activeGyroListener = null
        activeSensorManager = null
    }

    private fun triggerDeviceRumble(
        requestedDeviceId: Int?,
        lowFreq: Double,
        highFreq: Double,
        durationMs: Long
    ): Boolean {
        val deviceIds = InputDevice.getDeviceIds()
        for (id in deviceIds) {
            if (requestedDeviceId != null && id != requestedDeviceId) continue
            val dev = InputDevice.getDevice(id) ?: continue
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = dev.vibratorManager
                val vibratorIds = vm.vibratorIds
                if (vibratorIds.isNotEmpty()) {
                    val amp = ((lowFreq * 0.6 + highFreq * 0.4) * 255.0).toInt().coerceIn(1, 255)
                    vm.getVibrator(vibratorIds[0]).vibrate(
                        VibrationEffect.createOneShot(durationMs, amp)
                    )
                    return true
                }
            } else {
                @Suppress("DEPRECATION")
                val vib = dev.vibrator
                if (vib.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val amp = ((lowFreq * 0.6 + highFreq * 0.4) * 255.0).toInt().coerceIn(1, 255)
                        vib.vibrate(VibrationEffect.createOneShot(durationMs, amp))
                    } else {
                        @Suppress("DEPRECATION")
                        vib.vibrate(durationMs)
                    }
                    return true
                }
            }
        }
        return false
    }

    // --- Implémentation requise par GamepadsCompatibleActivity (plugin `gamepads`) ---

    override fun dispatchGenericMotionEvent(motionEvent: MotionEvent): Boolean {
        if (motionListener?.invoke(motionEvent) == true) {
            return true
        }
        return super.dispatchGenericMotionEvent(motionEvent)
    }

    override fun dispatchKeyEvent(keyEvent: KeyEvent): Boolean {
        if (keyListener?.invoke(keyEvent) == true) {
            return true
        }
        return super.dispatchKeyEvent(keyEvent)
    }

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?
    ) {
        val inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler ?: Handler(Looper.getMainLooper()))
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
    }
}