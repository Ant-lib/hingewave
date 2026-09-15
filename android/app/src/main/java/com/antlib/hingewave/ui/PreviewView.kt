package com.antlib.hingewave.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.Choreographer
import com.antlib.hingewave.core.EffectConfig
import com.antlib.hingewave.core.PhoneMapping
import com.antlib.hingewave.core.SplashTimeline
import com.antlib.hingewave.render.SplashGeometry
import com.antlib.hingewave.render.SplashPainter
import com.antlib.hingewave.render.FoldGeometry
import com.antlib.hingewave.render.FoldPainter
import com.antlib.hingewave.render.MovingSide
import com.antlib.hingewave.render.Panel

/**
 * Hardware-accelerated view that draws the fold at a chosen angle, used by the
 * settings screen for a live preview. RuntimeShader needs a hardware canvas,
 * which a normal View gets when the window is hardware accelerated (the default).
 */
class PreviewView(context: Context) : View(context) {
    private val mapping = PhoneMapping(EffectConfig.DEFAULTS)
    private var painter: FoldPainter? = null
    private var splashPainter: SplashPainter? = null
    private var picture: Bitmap? = null
    private val splash = SplashTimeline()
    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            invalidate()
            if (splash.isActive) Choreographer.getInstance().postFrameCallback(this)
        }
    }

    /** When true the ripple is drawn instead of the fold. */
    var splashMode = false
        set(value) { field = value; invalidate() }

    /** Starts a ripple in the preview; a second call while draining restarts it. */
    fun playSplash() {
        splash.trigger(System.nanoTime() / 1e9)
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    /** Simulates reaching a detent: the water drains after the ripple finishes. */
    fun settleSplash() {
        splash.settle(System.nanoTime() / 1e9)
    }

    var angle = 180.0
        set(value) { field = value; invalidate() }
    var panel = Panel.INNER
        set(value) { field = value; invalidate() }
    var movingSide = MovingSide.RIGHT
        set(value) { field = value; invalidate() }
    /** Inner panel calibrated clear start, NaN for the default. */
    var clearStart = Double.NaN
        set(value) { field = value; invalidate() }

    fun setPicture(bitmap: Bitmap) {
        painter?.recycle()
        picture = bitmap
        painter = FoldPainter(bitmap)
        splashPainter = SplashPainter(bitmap)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (splashMode) {
            val sp = splashPainter ?: return
            sp.draw(canvas, width, height, SplashGeometry.hingeEdge(panel, movingSide), SplashGeometry.hingePosition(panel), splash.frame(System.nanoTime() / 1e9))
            return
        }
        val p = painter ?: return
        val geometry = FoldGeometry.forPanel(panel, movingSide)
        val progress = when (panel) {
            Panel.INNER -> if (clearStart.isNaN()) mapping.inner(angle)
                else 1.0 - com.antlib.hingewave.core.smoothstep((angle - clearStart) / (EffectConfig.DEFAULTS.phone.inner.clearEnd - clearStart))
            Panel.COVER -> mapping.cover(angle)
        }
        val perpendicular = if (panel == Panel.INNER) width / 2 else width
        p.draw(canvas, width, height, mapping.tilt(angle), progress, geometry, perpendicular)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        painter?.recycle()
        painter = null
        splashPainter = null
    }
}
