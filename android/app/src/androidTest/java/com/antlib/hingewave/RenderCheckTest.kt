package com.antlib.hingewave

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.ImageReader
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.antlib.hingewave.render.FoldGeometry
import com.antlib.hingewave.render.FoldPainter
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.log10

/**
 * Renders core/test-card.png through the AGSL shader at every golden entry and
 * compares with core/golden by PSNR. The core files are pushed to the device by
 * the test runner script into /data/local/tmp/hingewave-core (see android/render-check.sh).
 */
@RunWith(AndroidJUnit4::class)
class RenderCheckTest {
    private val coreDir = File("/data/local/tmp/hingewave-core")

    @Test
    fun goldensMatchWithinTolerance() {
        val index = JSONObject(File(coreDir, "golden/index.json").readText())
        val width = index.getInt("width")
        val height = index.getInt("height")
        val minDb = index.getDouble("minPsnrDb")
        val card = BitmapFactory.decodeFile(File(coreDir, "test-card.png").path)
        val painter = FoldPainter(card)
        val outDir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "render-check").apply { mkdirs() }

        val entries = index.getJSONArray("entries")
        val report = StringBuilder()
        var failures = 0
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            val actual = renderHardware(width, height) { canvas ->
                painter.draw(canvas, width, height, e.getDouble("tilt"), e.getDouble("progress"), FoldGeometry(FoldGeometry.BOTTOM, 0f, 1f), height)
            }
            val golden = BitmapFactory.decodeFile(File(coreDir, "golden/" + e.getString("file")).path)
            val db = psnr(actual, golden)
            File(outDir, e.getString("file")).outputStream().use { actual.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val ok = db >= minDb
            if (!ok) failures++
            report.append(String.format("%-16s tilt %5.1f progress %.2f psnr %6.2f %s\n", e.getString("file"), e.getDouble("tilt"), e.getDouble("progress"), db, if (ok) "ok" else "FAIL"))
        }
        File(outDir, "report.txt").writeText(report.toString())
        assertTrue("render check failed:\n$report", failures == 0)
    }

    /** Draws through the real GPU pipeline so RuntimeShader is exercised as in the wallpaper. */
    private fun renderHardware(width: Int, height: Int, draw: (Canvas) -> Unit): Bitmap {
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 1,
            HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT)
        val renderer = HardwareRenderer()
        val node = RenderNode("fold").apply { setPosition(0, 0, width, height) }
        val canvas = node.beginRecording()
        draw(canvas)
        node.endRecording()
        renderer.setContentRoot(node)
        renderer.setSurface(reader.surface)
        renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
        val image = reader.acquireNextImage()
        val hb = image.hardwareBuffer!!
        val hw = Bitmap.wrapHardwareBuffer(hb, null)!!
        val result = hw.copy(Bitmap.Config.ARGB_8888, false)
        image.close()
        renderer.destroy()
        reader.close()
        return result
    }

    private fun psnr(a: Bitmap, b: Bitmap): Double {
        val w = a.width
        val h = a.height
        val pa = IntArray(w * h).also { a.getPixels(it, 0, w, 0, 0, w, h) }
        val pb = IntArray(w * h).also { b.getPixels(it, 0, w, 0, 0, w, h) }
        var sum = 0.0
        for (i in pa.indices) {
            for (shift in intArrayOf(16, 8, 0)) {
                val d = (((pa[i] shr shift) and 0xff) - ((pb[i] shr shift) and 0xff)) / 255.0
                sum += d * d
            }
        }
        val mse = sum / (pa.size * 3)
        return if (mse == 0.0) Double.POSITIVE_INFINITY else 10.0 * log10(1.0 / mse)
    }
}

/** Compiles both AGSL shaders on the device so a shader error shows up as a readable test failure. */
@RunWith(AndroidJUnit4::class)
class ShaderCompileTest {
    @Test
    fun foldShaderCompiles() {
        android.graphics.RuntimeShader(com.antlib.hingewave.render.FoldShader.source)
    }

    @Test
    fun splashShaderCompiles() {
        android.graphics.RuntimeShader(com.antlib.hingewave.render.SplashShader.source)
    }
}

/**
 * Renders the splash shader offscreen at fixed timeline values and checks that it
 * changes the picture: a travelling ring, and the wet state after the ring has
 * passed. Outputs are saved next to the fold renders for the CI artifact.
 */
@RunWith(AndroidJUnit4::class)
class SplashRenderTest {
    private val coreDir = File("/data/local/tmp/hingewave-core")

    @Test
    fun splashChangesThePicture() {
        val card = BitmapFactory.decodeFile(File(coreDir, "test-card.png").path)
        val width = card.width
        val height = card.height
        val outDir = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "render-check").apply { mkdirs() }
        val painter = com.antlib.hingewave.render.SplashPainter(card)
        val cases = listOf(
            "splash-ring.png" to com.antlib.hingewave.core.SplashOutput(com.antlib.hingewave.core.SplashState.SPLASHING, 0.5, 0.4, 1.0, 1.0),
            "splash-wet.png" to com.antlib.hingewave.core.SplashOutput(com.antlib.hingewave.core.SplashState.HOLDING, 2.4, 2.0, 0.13, 1.0),
        )
        val report = StringBuilder()
        var failures = 0
        for ((name, frame) in cases) {
            val out = renderHardware(width, height) { canvas ->
                painter.draw(canvas, width, height, com.antlib.hingewave.render.FoldGeometry.LEFT, 0.5f, frame)
            }
            File(outDir, name).outputStream().use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val diff = meanAbsDiff(out, card)
            val ok = diff > 2.0
            if (!ok) failures++
            report.append(String.format("%-16s front %.2f wet %.2f mean abs diff %6.2f %s\n", name, frame.front, frame.wet, diff, if (ok) "ok" else "FAIL"))
        }
        File(outDir, "splash-report.txt").writeText(report.toString())
        assertTrue("splash render check failed:\n$report", failures == 0)
    }

    private fun renderHardware(width: Int, height: Int, draw: (Canvas) -> Unit): Bitmap {
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 1,
            HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT)
        val renderer = HardwareRenderer()
        val node = RenderNode("splash").apply { setPosition(0, 0, width, height) }
        val canvas = node.beginRecording()
        draw(canvas)
        node.endRecording()
        renderer.setContentRoot(node)
        renderer.setSurface(reader.surface)
        renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
        val image = reader.acquireNextImage()
        val hw = Bitmap.wrapHardwareBuffer(image.hardwareBuffer!!, null)!!
        val result = hw.copy(Bitmap.Config.ARGB_8888, false)
        image.close()
        renderer.destroy()
        reader.close()
        return result
    }

    private fun meanAbsDiff(a: Bitmap, b: Bitmap): Double {
        val w = a.width
        val h = a.height
        val pa = IntArray(w * h).also { a.getPixels(it, 0, w, 0, 0, w, h) }
        val pb = IntArray(w * h).also { b.getPixels(it, 0, w, 0, 0, w, h) }
        var sum = 0.0
        for (i in pa.indices) {
            for (shift in intArrayOf(16, 8, 0)) {
                sum += Math.abs(((pa[i] shr shift) and 0xff) - ((pb[i] shr shift) and 0xff))
            }
        }
        return sum / (pa.size * 3)
    }
}
