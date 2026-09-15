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
        android.util.Log.d("Hingewave", "debug settings broadcast pid=${android.os.Process.myPid()} extras=${intent.extras?.keySet()?.joinToString()}")
        intent.getStringExtra("effect")?.let { value ->
            runCatching { EffectMode.valueOf(value.uppercase()) }.getOrNull()?.let {
                settings.effectMode = it
                android.util.Log.d("Hingewave", "effect mode set to $it")
            }
        }
        intent.getStringExtra("side")?.let { value ->
            runCatching { MovingSide.valueOf(value.uppercase()) }.getOrNull()?.let { settings.movingSide = it }
        }
    }
}
