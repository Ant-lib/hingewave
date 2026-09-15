package com.antlib.hingewave.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import com.antlib.hingewave.core.EffectConfig
import com.antlib.hingewave.core.PhoneMapping
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
    private var picture: Bitmap? = null

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
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
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
        painter?.recycle()
        painter = null
    }
}
