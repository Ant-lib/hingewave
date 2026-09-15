package com.antlib.hingewave.wallpaper

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.net.Uri
import kotlin.math.max
import kotlin.math.roundToInt

/** Loads the picked picture centre-cropped to the surface, or draws the generated default. */
object WallpaperImage {
    fun load(context: Context, uri: String?, width: Int, height: Int): Bitmap {
        if (uri != null) {
            try {
                return decodeCropped(context, Uri.parse(uri), width, height)
            } catch (_: Exception) {
                // Fall through to the generated picture if the URI is gone or unreadable.
            }
        }
        return generated(width, height)
    }

    private fun decodeCropped(context: Context, uri: Uri, width: Int, height: Int): Bitmap {
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        val decoded = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false
            val scale = max(width.toDouble() / info.size.width, height.toDouble() / info.size.height)
            decoder.setTargetSize(
                max(1, (info.size.width * scale).roundToInt()),
                max(1, (info.size.height * scale).roundToInt()),
            )
        }
        val x = ((decoded.width - width) / 2).coerceAtLeast(0)
        val y = ((decoded.height - height) / 2).coerceAtLeast(0)
        val w = minOf(width, decoded.width - x)
        val h = minOf(height, decoded.height - y)
        val cropped = Bitmap.createBitmap(decoded, x, y, w, h)
        return if (cropped.config == Bitmap.Config.ARGB_8888) cropped else cropped.copy(Bitmap.Config.ARGB_8888, false)
    }

    /** A desktop-like gradient with two soft discs, the same look as the macOS demo picture. */
    fun generated(width: Int, height: Int): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, width.toFloat(), height.toFloat(),
            intArrayOf(Color.rgb(26, 38, 115), Color.rgb(64, 96, 150), Color.rgb(230, 150, 70)),
            floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

        paint.shader = RadialGradient(width * 0.3f, height * 0.3f, width * 0.22f,
            Color.argb(150, 255, 255, 255), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        c.drawCircle(width * 0.3f, height * 0.3f, width * 0.22f, paint)
        paint.shader = RadialGradient(width * 0.7f, height * 0.62f, width * 0.28f,
            Color.argb(110, 0, 230, 180), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        c.drawCircle(width * 0.7f, height * 0.62f, width * 0.28f, paint)

        paint.shader = null
        paint.color = Color.argb(40, 255, 255, 255)
        paint.strokeWidth = 1f
        val step = max(48, width / 12)
        var x = 0f
        while (x < width) { c.drawLine(x, 0f, x, height.toFloat(), paint); x += step }
        var y = 0f
        while (y < height) { c.drawLine(0f, y, width.toFloat(), y, paint); y += step }
        return bmp
    }
}
