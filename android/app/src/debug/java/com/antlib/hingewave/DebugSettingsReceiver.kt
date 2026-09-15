package com.antlib.hingewave

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.antlib.hingewave.render.MovingSide
import com.antlib.hingewave.settings.EffectMode
import com.antlib.hingewave.settings.Settings

/** Debug builds only: applies settings sent over adb so the emulator check can drive modes. */
class DebugSettingsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val settings = Settings(context)
        intent.getStringExtra("effect")?.let { value ->
            runCatching { EffectMode.valueOf(value.uppercase()) }.getOrNull()?.let { settings.effectMode = it }
        }
        intent.getStringExtra("side")?.let { value ->
            runCatching { MovingSide.valueOf(value.uppercase()) }.getOrNull()?.let { settings.movingSide = it }
        }
    }
}
