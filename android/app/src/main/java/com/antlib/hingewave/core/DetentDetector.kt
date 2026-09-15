package com.antlib.hingewave.core

/**
 * Decides whether a hinge sensor only reports 0, 90 and 180 (Galaxy Z Fold 7 and
 * earlier for third-party apps) or sweeps continuously (Fold 8, Pixel Fold).
 * Twelve detent-only events decide true; any other value decides false at once.
 */
class DetentDetector {
    var isDetent: Boolean? = null
        private set
    private var count = 0

    fun feed(value: Double) {
        if (isDetent != null) return
        if (value !in DETENT_VALUES) {
            isDetent = false
            return
        }
        count += 1
        if (count >= SAMPLES) isDetent = true
    }

    companion object {
        const val SAMPLES = 12
        val DETENT_VALUES = setOf(0.0, 90.0, 180.0)
    }
}
