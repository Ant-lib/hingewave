package com.antlib.hingewave.core

import kotlin.math.max

fun smoothstep(x: Double): Double = when {
    x <= 0.0 -> 0.0
    x >= 1.0 -> 1.0
    else -> x * x * (3.0 - 2.0 * x)
}

/** Stateless angle to progress mapping for foldables (docs/design.md section 3.3). */
class PhoneMapping(private val cfg: EffectConfig = EffectConfig.DEFAULTS) {
    /** Inner panel: frosted at or below clearStart, clear at or above clearEnd. */
    fun inner(angle: Double): Double {
        val c = cfg.phone.inner
        return 1.0 - smoothstep((angle - c.clearStart) / (c.clearEnd - c.clearStart))
    }

    /** Cover panel: frosts as the phone opens past frostStart. */
    fun cover(angle: Double): Double {
        val c = cfg.phone.cover
        return smoothstep((angle - c.frostStart) / (c.frostEnd - c.frostStart))
    }

    /** Degrees the moving half has rotated away from flat. */
    fun tilt(angle: Double): Double = max(0.0, 180.0 - angle)

    fun isSettled(angle: Double): Boolean {
        val dz = cfg.phone.deadZone
        return angle <= dz || angle >= 180.0 - dz
    }
}
