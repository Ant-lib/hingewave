package com.antlib.hingewave.settings

import android.content.Context
import android.content.SharedPreferences
import com.antlib.hingewave.render.MovingSide

/** Which effect the wallpaper plays. AUTO picks Splash on detent-only sensors and Fold otherwise. */
enum class EffectMode { AUTO, FOLD, SPLASH }

/** Small SharedPreferences wrapper shared by the wallpaper engine and the settings screen. */
class Settings(context: Context) {
    val prefs: SharedPreferences = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    /** content:// URI of the picked picture, or null for the generated default. */
    var imageUri: String?
        get() = prefs.getString(KEY_IMAGE, null)
        set(value) = prefs.edit().putString(KEY_IMAGE, value).apply()

    var movingSide: MovingSide
        get() = if (prefs.getString(KEY_SIDE, MovingSide.RIGHT.name) == MovingSide.LEFT.name) MovingSide.LEFT else MovingSide.RIGHT
        set(value) = prefs.edit().putString(KEY_SIDE, value.name).apply()

    var effectMode: EffectMode
        get() = runCatching { EffectMode.valueOf(prefs.getString(KEY_EFFECT, EffectMode.AUTO.name)!!) }.getOrDefault(EffectMode.AUTO)
        set(value) = prefs.edit().putString(KEY_EFFECT, value.name).apply()

    /** Inner panel angle at which the picture is fully frosted; NaN means use effect.json. */
    var calibratedClearStart: Double
        get() = prefs.getFloat(KEY_CLEAR_START, Float.NaN).toDouble()
        set(value) = prefs.edit().putFloat(KEY_CLEAR_START, value.toFloat()).apply()

    /** Span observed by the wallpaper engine on the inner panel, written by the engine. */
    var observedMin: Double
        get() = prefs.getFloat(KEY_OBS_MIN, Float.NaN).toDouble()
        set(value) = prefs.edit().putFloat(KEY_OBS_MIN, value.toFloat()).apply()

    var observedMax: Double
        get() = prefs.getFloat(KEY_OBS_MAX, Float.NaN).toDouble()
        set(value) = prefs.edit().putFloat(KEY_OBS_MAX, value.toFloat()).apply()

    /** True once the engine decided the sensor is detent-only; null while undecided. */
    var detentOnly: Boolean?
        get() = if (prefs.contains(KEY_DETENT)) prefs.getBoolean(KEY_DETENT, false) else null
        set(value) = prefs.edit().apply { if (value == null) remove(KEY_DETENT) else putBoolean(KEY_DETENT, value) }.apply()

    var sensorAvailable: Boolean?
        get() = if (prefs.contains(KEY_SENSOR)) prefs.getBoolean(KEY_SENSOR, false) else null
        set(value) = prefs.edit().apply { if (value == null) remove(KEY_SENSOR) else putBoolean(KEY_SENSOR, value) }.apply()

    companion object {
        const val NAME = "hingewave"
        const val KEY_IMAGE = "imageUri"
        const val KEY_SIDE = "movingSide"
        const val KEY_EFFECT = "effectMode"
        const val KEY_CLEAR_START = "calibratedClearStart"
        const val KEY_OBS_MIN = "observedMin"
        const val KEY_OBS_MAX = "observedMax"
        const val KEY_DETENT = "detentOnly"
        const val KEY_SENSOR = "sensorAvailable"
    }
}
