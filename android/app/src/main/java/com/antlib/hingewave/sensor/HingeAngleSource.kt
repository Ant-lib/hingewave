package com.antlib.hingewave.sensor

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import com.antlib.hingewave.core.DetentDetector

/**
 * Delivers hinge angles from Sensor.TYPE_HINGE_ANGLE (0 closed, 180 flat) and
 * keeps two facts about the sensor: whether it only reports detents, and the
 * span of angles this process has actually observed (used for span calibration,
 * because a live wallpaper only receives events while its own panel is lit).
 */
class HingeAngleSource(context: Context, private val onAngle: (Double) -> Unit) : SensorEventListener {
    private val manager = context.getSystemService(SensorManager::class.java)
    val sensor: Sensor? = manager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
    val available: Boolean get() = sensor != null

    val detent = DetentDetector()
    var minSeen = Double.NaN
        private set
    var maxSeen = Double.NaN
        private set
    var lastAngle = Double.NaN
        private set

    private var registered = false

    fun start() {
        val s = sensor ?: return
        if (registered) return
        registered = manager.registerListener(this, s, SensorManager.SENSOR_DELAY_GAME)
    }

    fun stop() {
        if (!registered) return
        manager.unregisterListener(this)
        registered = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_HINGE_ANGLE) return
        val angle = event.values[0].toDouble().coerceIn(0.0, 180.0)
        detent.feed(angle)
        minSeen = if (minSeen.isNaN()) angle else minOf(minSeen, angle)
        maxSeen = if (maxSeen.isNaN()) angle else maxOf(maxSeen, angle)
        lastAngle = angle
        onAngle(angle)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
