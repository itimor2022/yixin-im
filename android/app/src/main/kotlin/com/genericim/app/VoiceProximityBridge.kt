package com.genericim.ma100

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.PowerManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class VoiceProximityBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val proximitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        ?: sensorManager.getSensorList(Sensor.TYPE_ALL).firstOrNull { sensor ->
            val name = sensor.name.lowercase()
            name.contains("proximity") || name.contains("phonecall")
        }
    private val powerManager = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val eventChannel = EventChannel(messenger, "com.genericim/voice_proximity/events")
    private val methodChannel = MethodChannel(messenger, "com.genericim/voice_proximity/methods")

    private var eventSink: EventChannel.EventSink? = null
    private var lastNear: Boolean? = null
    private var proximityWakeLock: PowerManager.WakeLock? = null

    init {
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenOffEnabled" -> {
                    setScreenOffEnabled(call.arguments as? Boolean == true)
                    result.success(proximitySensor != null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        lastNear = null
        Log.i("VoiceProximity", "listen sensor=${proximitySensor?.name ?: "unavailable"}")
        proximitySensor?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        eventSink = null
        lastNear = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sensor = proximitySensor ?: return
        val value = event.values.firstOrNull() ?: return
        val near = if (sensor.maximumRange > 0f) {
            value < sensor.maximumRange
        } else {
            value == 0f
        }
        if (lastNear == near) return
        lastNear = near
        Log.i("VoiceProximity", "event sensor=${sensor.name} value=$value near=$near")
        activity.runOnUiThread { eventSink?.success(near) }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    @SuppressLint("WakelockTimeout")
    private fun setScreenOffEnabled(enabled: Boolean) {
        if (proximitySensor == null) return
        if (enabled) {
            if (proximityWakeLock == null) {
                proximityWakeLock = powerManager.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "${activity.packageName}:voice-proximity",
                ).apply { setReferenceCounted(false) }
            }
            if (proximityWakeLock?.isHeld != true) proximityWakeLock?.acquire()
        } else {
            releaseWakeLock()
        }
    }

    private fun releaseWakeLock() {
        if (proximityWakeLock?.isHeld == true) proximityWakeLock?.release()
    }

    fun dispose() {
        sensorManager.unregisterListener(this)
        releaseWakeLock()
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }
}
