package com.antlib.hingewave.ui

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.antlib.hingewave.render.MovingSide
import com.antlib.hingewave.render.Panel
import com.antlib.hingewave.settings.Settings
import com.antlib.hingewave.wallpaper.HingewaveWallpaperService
import com.antlib.hingewave.wallpaper.WallpaperImage

class SettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val settings = Settings(this)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    SettingsScreen(settings)
                }
            }
        }
    }

    private fun setAsWallpaper() {
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, ComponentName(this@SettingsActivity, HingewaveWallpaperService::class.java))
        }
        startActivity(intent)
    }

    @Composable
    private fun SettingsScreen(settings: Settings) {
        var imageUri by remember { mutableStateOf(settings.imageUri) }
        var side by remember { mutableStateOf(settings.movingSide) }
        var panel by remember { mutableStateOf(Panel.INNER) }
        var angle by remember { mutableStateOf(150f) }
        var clearStart by remember { mutableStateOf(settings.calibratedClearStart) }
        var preview by remember { mutableStateOf<PreviewView?>(null) }

        val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            if (uri != null) {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                settings.imageUri = uri.toString()
                imageUri = uri.toString()
                preview?.let { v -> v.setPicture(WallpaperImage.load(this, imageUri, v.width.coerceAtLeast(1), v.height.coerceAtLeast(1))) }
            }
        }

        Column(
            modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("Hingewave", style = MaterialTheme.typography.headlineMedium)
            Text(
                "The iPhone Duo fold effect on your wallpaper, driven by the hinge angle. " +
                    "Set it as your live wallpaper, then fold the phone slowly.",
                style = MaterialTheme.typography.bodyMedium,
            )

            StatusLine(settings)

            AndroidView(
                factory = { ctx ->
                    PreviewView(ctx).also { v ->
                        preview = v
                        v.angle = angle.toDouble()
                        v.panel = panel
                        v.movingSide = side
                        v.clearStart = clearStart
                        v.post {
                            v.setPicture(WallpaperImage.load(ctx, imageUri, v.width.coerceAtLeast(1), v.height.coerceAtLeast(1)))
                        }
                    }
                },
                update = { v ->
                    v.angle = angle.toDouble()
                    v.panel = panel
                    v.movingSide = side
                    v.clearStart = clearStart
                },
                modifier = Modifier.fillMaxWidth().aspectRatio(if (panel == Panel.INNER) 0.9f else 0.45f),
            )

            Text("Preview angle: ${angle.toInt()} degrees", style = MaterialTheme.typography.labelLarge)
            Slider(value = angle, onValueChange = { angle = it }, valueRange = 0f..180f)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = panel == Panel.INNER, onClick = { panel = Panel.INNER }, label = { Text("Inner screen") })
                FilterChip(selected = panel == Panel.COVER, onClick = { panel = Panel.COVER }, label = { Text("Cover screen") })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = side == MovingSide.RIGHT, onClick = { side = MovingSide.RIGHT; settings.movingSide = side }, label = { Text("Right half moves") })
                FilterChip(selected = side == MovingSide.LEFT, onClick = { side = MovingSide.LEFT; settings.movingSide = side }, label = { Text("Left half moves") })
            }

            Spacer(Modifier.height(4.dp))
            OutlinedButton(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Text(if (imageUri == null) "Pick a picture" else "Change picture")
            }
            if (imageUri != null) {
                OutlinedButton(onClick = {
                    settings.imageUri = null
                    imageUri = null
                    preview?.let { v -> v.setPicture(WallpaperImage.load(this@SettingsActivity, null, v.width.coerceAtLeast(1), v.height.coerceAtLeast(1))) }
                }) { Text("Use the built-in picture") }
            }

            CalibrationBlock(settings, clearStart) { value -> clearStart = value; settings.calibratedClearStart = value }

            Spacer(Modifier.height(4.dp))
            Button(onClick = { setAsWallpaper() }, modifier = Modifier.fillMaxWidth()) {
                Text("Set as live wallpaper")
            }
            Text(
                "No network, no analytics. The wallpaper only reads the hinge angle sensor and draws your picture.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }

    @Composable
    private fun StatusLine(settings: Settings) {
        val sensor = settings.sensorAvailable
        val detent = settings.detentOnly
        val text = when {
            sensor == false -> "No hinge angle sensor on this device. The wallpaper stays flat."
            detent == true -> "Detent-only sensor: this device reports only 0, 90 and 180 degrees to apps, so the fold plays as a timed transition."
            detent == false -> "Continuous hinge sensor detected."
            else -> "Sensor status appears after the wallpaper has run once."
        }
        Text(text, style = MaterialTheme.typography.bodySmall)
    }

    @Composable
    private fun CalibrationBlock(settings: Settings, clearStart: Double, onChange: (Double) -> Unit) {
        val min = settings.observedMin
        val max = settings.observedMax
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Inner screen calibration", style = MaterialTheme.typography.labelLarge)
            Text(
                if (min.isNaN()) "The inner screen lights part way through an unfold. After a few folds, the wallpaper knows the first angle it sees; use it so the effect starts from fully frosted."
                else "Observed while the inner screen was on: ${min.toInt()} to ${max.toInt()} degrees." +
                    (if (clearStart.isNaN()) " Using the default start of ${com.antlib.hingewave.core.EffectConfig.DEFAULTS.phone.inner.clearStart.toInt()} degrees." else " Frosted until ${clearStart.toInt()} degrees."),
                style = MaterialTheme.typography.bodySmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { if (!min.isNaN()) onChange(min) }, enabled = !min.isNaN()) { Text("Use observed span") }
                OutlinedButton(onClick = { onChange(Double.NaN) }, enabled = !clearStart.isNaN()) { Text("Reset") }
            }
        }
    }
}
