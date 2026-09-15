package com.antlib.hingewave.render

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RuntimeShader
import android.graphics.Shader
import com.antlib.hingewave.core.EffectConfig
import kotlin.math.max

/**
 * Draws the folded picture into any Canvas. Holds the RuntimeShader and a
 * five-level pyramid of pre-scaled bitmaps for the blur.
 */
class FoldPainter(picture: Bitmap, private val config: EffectConfig = EffectConfig.DEFAULTS) {
    private val shader = RuntimeShader(FoldShader.source)
    private val paint = Paint().apply { isAntiAlias = false; isDither = true }
    private val levels: List<Bitmap>
    val picWidth = picture.width
    val picHeight = picture.height

    init {
        val list = ArrayList<Bitmap>(FoldShader.LEVELS)
        var current = picture
        list.add(current)
        for (i in 1 until FoldShader.LEVELS) {
            val w = max(1, current.width / 2)
            val h = max(1, current.height / 2)
            current = Bitmap.createScaledBitmap(current, w, h, true)
            list.add(current)
        }
        levels = list
        for ((i, bmp) in levels.withIndex()) {
            shader.setInputShader("level$i", BitmapShader(bmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                filterMode = BitmapShader.FILTER_MODE_LINEAR
            })
        }
        shader.setFloatUniform("picSize", picWidth.toFloat(), picHeight.toFloat())
        shader.setFloatUniform("eyeDistance", config.eyeDistance.toFloat())
        shader.setFloatUniform("darkenGain", config.darkenGain.toFloat())
        paint.shader = shader
    }

    /**
     * Draws the fold over the rectangle (0, 0, width, height).
     * [tiltDegrees] is the rotation of the moving half away from flat; [progress] 0 open, 1 folded.
     * [perpendicularPx] is the panel extent perpendicular to the hinge, which scales the blur.
     */
    fun draw(canvas: Canvas, width: Int, height: Int, tiltDegrees: Double, progress: Double, geometry: FoldGeometry, perpendicularPx: Int) {
        shader.setFloatUniform("size", width.toFloat(), height.toFloat())
        shader.setFloatUniform("tilt", Math.toRadians(tiltDegrees).toFloat())
        shader.setFloatUniform("progress", progress.toFloat())
        shader.setFloatUniform("maxBlurPx", (config.maxBlur * perpendicularPx).toFloat())
        shader.setIntUniform("hingeEdge", geometry.hingeEdge)
        shader.setFloatUniform("region", geometry.regionStart, geometry.regionEnd)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }

    fun recycle() {
        for (b in levels.drop(1)) b.recycle()
    }
}
