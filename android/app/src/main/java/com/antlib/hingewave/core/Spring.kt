package com.antlib.hingewave.core

import kotlin.math.PI
import kotlin.math.exp

/**
 * Critically damped spring with an exact closed-form step.
 * Same formula as core/reference/hingewave_ref/spring.py.
 */
class Spring(hz: Double) {
    val omega = 2.0 * PI * hz
    var x = 0.0
        private set
    var v = 0.0
        private set

    fun reset(value: Double) {
        x = value
        v = 0.0
    }

    /** Advances toward [target] by [dt] seconds and returns the new position. */
    fun step(target: Double, dt: Double): Double {
        if (dt <= 0.0) return x
        val w = omega
        val d = x - target
        val e = exp(-w * dt)
        val xNew = target + (d + (v + w * d) * dt) * e
        val vNew = (v - w * (v + w * d) * dt) * e
        x = xNew
        v = vNew
        return x
    }
}
