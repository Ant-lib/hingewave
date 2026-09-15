package com.antlib.hingewave.core

import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

/**
 * Splash timeline for foldables whose hinge sensor only reports detents.
 * Mirrors core/reference/hingewave_ref/splash.py and is verified by core/fixtures/splash-*.json.
 *
 * trigger(t): movement started (a panel lit up or a detent changed)
 * motion(t): the phone is still being handled (gyroscope above threshold)
 * settle(t): a fully open or fully closed detent was reached
 * frame(t): per-frame values for the ripple shader
 */
enum class SplashState { IDLE, SPLASHING, HOLDING, DRAINING }

data class SplashOutput(
    val state: SplashState,
    /** Seconds since the current splash started. */
    val age: Double,
    /** Ripple front position: 0 at the hinge, 1 at the far edge, keeps growing. */
    val front: Double,
    /** Ripple ring amplitude 0..1, fading once the front has passed the far edge. */
    val ring: Double,
    /** Overall water presence 0..1. */
    val wet: Double,
) {
    companion object {
        val IDLE = SplashOutput(SplashState.IDLE, 0.0, 0.0, 0.0, 0.0)
    }
}

class SplashTimeline(config: EffectConfig = EffectConfig.DEFAULTS) {
    private val cfg = config.splash
    var state = SplashState.IDLE
        private set
    private var t0: Double? = null
    private var lastMotion: Double? = null
    private var drainStart: Double? = null
    private var forcedDrainAt: Double? = null
    private var wetAtDrain = 1.0
    private var wetStart = 0.0

    val isActive: Boolean get() = state != SplashState.IDLE

    fun trigger(t: Double) {
        when (state) {
            SplashState.IDLE -> {
                state = SplashState.SPLASHING
                t0 = t
                wetStart = 0.0
            }
            SplashState.DRAINING -> {
                wetStart = wet(t)
                state = SplashState.SPLASHING
                t0 = t
            }
            else -> Unit
        }
        lastMotion = t
        drainStart = null
        forcedDrainAt = null
    }

    fun motion(t: Double) {
        if (state == SplashState.SPLASHING || state == SplashState.HOLDING) lastMotion = t
    }

    fun settle(t: Double) {
        val start = t0 ?: return
        if (state == SplashState.SPLASHING || state == SplashState.HOLDING) {
            forcedDrainAt = max(t, start + cfg.travelSeconds)
        }
    }

    fun frame(t: Double): SplashOutput {
        val start = t0
        if (state == SplashState.IDLE || start == null) return SplashOutput.IDLE
        val age = t - start
        val front = age / cfg.travelSeconds

        if (state == SplashState.SPLASHING && front >= 1.0) state = SplashState.HOLDING

        if (state == SplashState.SPLASHING || state == SplashState.HOLDING) {
            val stillFor = t - (lastMotion ?: start)
            val forced = forcedDrainAt?.let { t >= it } ?: false
            if (stillFor >= cfg.stillSeconds || forced) {
                state = SplashState.DRAINING
                drainStart = t
                wetAtDrain = rise(age)
            }
        }

        val wet = wet(t)
        if (state == SplashState.DRAINING && wet <= 0.0) {
            reset()
            return SplashOutput.IDLE
        }
        val ring = exp(-max(0.0, front - 1.0) * 2.0)
        return SplashOutput(state, age, front, ring, wet)
    }

    private fun rise(age: Double): Double {
        val r = min(1.0, age / cfg.riseSeconds)
        return wetStart + (1.0 - wetStart) * r
    }

    private fun wet(t: Double): Double {
        val start = t0 ?: return 0.0
        val ds = drainStart
        if (state == SplashState.DRAINING && ds != null) {
            val k = 1.0 - (t - ds) / cfg.drainSeconds
            return max(0.0, wetAtDrain * k)
        }
        return rise(t - start)
    }

    private fun reset() {
        state = SplashState.IDLE
        t0 = null
        lastMotion = null
        drainStart = null
        forcedDrainAt = null
        wetStart = 0.0
    }
}
