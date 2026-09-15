package com.antlib.hingewave.wallpaper

import android.content.SharedPreferences
import android.service.wallpaper.WallpaperService
import android.view.Choreographer
import android.view.SurfaceHolder
import com.antlib.hingewave.core.EffectConfig
import com.antlib.hingewave.core.PhoneMapping
import com.antlib.hingewave.core.Spring
import com.antlib.hingewave.core.smoothstep
import com.antlib.hingewave.render.FoldGeometry
import com.antlib.hingewave.render.FoldPainter
import com.antlib.hingewave.render.Panel
import com.antlib.hingewave.sensor.HingeAngleSource
import com.antlib.hingewave.settings.Settings
import kotlin.math.abs

/**
 * Live wallpaper engine. Reads the hinge angle while visible, smooths it with the
 * shared spring, maps it to progress for the panel it is drawn on, and redraws
 * through the AGSL shader only while the angle is moving.
 */
class HingewaveWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = FoldEngine()

    inner class FoldEngine : Engine(), Choreographer.FrameCallback, SharedPreferences.OnSharedPreferenceChangeListener {
        private val config = EffectConfig.DEFAULTS
        private val mapping = PhoneMapping(config)
        private val settings = Settings(this@HingewaveWallpaperService)
        private val choreographer = Choreographer.getInstance()

        private var spring = Spring(config.springHz)
        private var targetAngle = 180.0
        private var lastFrameNs = 0L
        private var frameScheduled = false

        private var width = 0
        private var height = 0
        private var panel = Panel.INNER
        private var geometry = FoldGeometry.forPanel(Panel.INNER, settings.movingSide)
        private var painter: FoldPainter? = null
        private var visible = false

        private val source = HingeAngleSource(this@HingewaveWallpaperService) { angle -> onAngle(angle) }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            settings.sensorAvailable = source.available
            settings.prefs.registerOnSharedPreferenceChangeListener(this)
            spring.reset(targetAngle)
        }

        override fun onDestroy() {
            settings.prefs.unregisterOnSharedPreferenceChangeListener(this)
            source.stop()
            choreographer.removeFrameCallback(this)
            painter?.recycle()
            painter = null
            super.onDestroy()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {
            super.onSurfaceChanged(holder, format, w, h)
            width = w
            height = h
            panel = Panel.fromSize(w, h)
            geometry = FoldGeometry.forPanel(panel, settings.movingSide)
            rebuildPainter()
            draw()
        }

        override fun onVisibilityChanged(isVisible: Boolean) {
            visible = isVisible
            if (isVisible) {
                source.start()
                requestFrame()
            } else {
                source.stop()
                choreographer.removeFrameCallback(this)
                frameScheduled = false
                lastFrameNs = 0L
            }
        }

        override fun onSharedPreferenceChanged(prefs: SharedPreferences, key: String?) {
            when (key) {
                Settings.KEY_IMAGE -> { rebuildPainter(); draw() }
                Settings.KEY_SIDE -> { geometry = FoldGeometry.forPanel(panel, settings.movingSide); draw() }
                Settings.KEY_CLEAR_START -> draw()
            }
        }

        // MARK: Sensor

        private fun onAngle(angle: Double) {
            targetAngle = angle
            if (panel == Panel.INNER) {
                if (!source.minSeen.isNaN()) settings.observedMin = source.minSeen
                if (!source.maxSeen.isNaN()) settings.observedMax = source.maxSeen
            }
            val detent = source.detent.isDetent
            if (detent != null && settings.detentOnly != detent) {
                settings.detentOnly = detent
                // Detent-only sensors jump 0/90/180; a slower spring turns each jump into a clearSeconds glide.
                val hz = if (detent) 1.0 / config.clearSeconds else config.springHz
                val keep = spring.x
                spring = Spring(hz).also { it.reset(keep) }
            }
            requestFrame()
        }

        // MARK: Frames

        private fun requestFrame() {
            if (!visible || frameScheduled) return
            frameScheduled = true
            choreographer.postFrameCallback(this)
        }

        override fun doFrame(frameTimeNanos: Long) {
            frameScheduled = false
            if (!visible) return
            val dt = if (lastFrameNs == 0L) 1.0 / 60.0 else (frameTimeNanos - lastFrameNs) / 1e9
            lastFrameNs = frameTimeNanos
            val x = spring.step(targetAngle, dt)
            draw(x)
            if (abs(x - targetAngle) > 0.05 || abs(spring.v) > 0.5) requestFrame() else lastFrameNs = 0L
        }

        private fun draw(angle: Double = spring.x) {
            val p = painter ?: return
            if (width == 0 || height == 0) return
            val holder = surfaceHolder
            val canvas = try { holder.lockHardwareCanvas() } catch (_: Exception) { null } ?: return
            try {
                val (tilt, progress) = shape(angle)
                val perpendicular = if (panel == Panel.INNER) width / 2 else width
                p.draw(canvas, width, height, tilt, progress, geometry, perpendicular)
            } finally {
                holder.unlockCanvasAndPost(canvas)
            }
        }

        /** (tilt, progress) for the current panel, honouring span calibration on the inner panel. */
        private fun shape(angle: Double): Pair<Double, Double> {
            if (isPreview) return 0.0 to 0.0
            val tilt = mapping.tilt(angle)
            val progress = when (panel) {
                Panel.INNER -> {
                    val cs = settings.calibratedClearStart
                    if (cs.isNaN()) mapping.inner(angle)
                    else 1.0 - smoothstep((angle - cs) / (config.phone.inner.clearEnd - cs))
                }
                Panel.COVER -> mapping.cover(angle)
            }
            return tilt to progress
        }

        private fun rebuildPainter() {
            if (width == 0 || height == 0) return
            painter?.recycle()
            painter = FoldPainter(WallpaperImage.load(this@HingewaveWallpaperService, settings.imageUri, width, height), config)
        }
    }
}
