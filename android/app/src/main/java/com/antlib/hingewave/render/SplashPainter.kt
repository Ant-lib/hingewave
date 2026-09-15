package com.antlib.hingewave.render

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RuntimeShader
import android.graphics.Shader
import com.antlib.hingewave.core.EffectConfig
import com.antlib.hingewave.core.SplashOutput

/** Draws the ripple over the picture for one frame of the splash timeline. */
class SplashPainter(picture: Bitmap, private val config: EffectConfig = EffectConfig.DEFAULTS) {
    private val shader = RuntimeShader(SplashShader.source)
    private val paint = Paint().apply { isAntiAlias = false; isDither = true }

    init {
        shader.setInputShader("picture", BitmapShader(picture, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            filterMode = BitmapShader.FILTER_MODE_LINEAR
        })
        shader.setFloatUniform("picSize", picture.width.toFloat(), picture.height.toFloat())
        shader.setFloatUniform("swellHz", config.splash.swellHz.toFloat())
        paint.shader = shader
    }

    /**
     * [hingeEdge] is the FoldGeometry edge code the u axis starts from; [hingePosition]
     * is where the hinge sits along u (0.5 for a book-style inner panel, 0 for a cover).
     */
    fun draw(canvas: Canvas, width: Int, height: Int, hingeEdge: Int, hingePosition: Float, frame: SplashOutput) {
        shader.setFloatUniform("size", width.toFloat(), height.toFloat())
        shader.setIntUniform("hingeEdge", hingeEdge)
        shader.setFloatUniform("hinge", hingePosition)
        shader.setFloatUniform("front", frame.front.toFloat())
        shader.setFloatUniform("ring", frame.ring.toFloat())
        shader.setFloatUniform("wet", frame.wet.toFloat())
        shader.setFloatUniform("age", frame.age.toFloat())
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}

/** Splash geometry per panel: the inner panel ripples from the centre crease both ways; the cover from its inner edge. */
object SplashGeometry {
    fun hingeEdge(panel: Panel, side: MovingSide): Int = when (side) {
        MovingSide.RIGHT -> FoldGeometry.LEFT
        MovingSide.LEFT -> FoldGeometry.RIGHT
    }

    fun hingePosition(panel: Panel): Float = if (panel == Panel.INNER) 0.5f else 0f
}
