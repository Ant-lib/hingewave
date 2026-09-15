package com.antlib.hingewave

import com.antlib.hingewave.core.DetentDetector
import com.antlib.hingewave.core.EffectConfig
import com.antlib.hingewave.core.PhoneMapping
import com.antlib.hingewave.core.SplashTimeline
import com.antlib.hingewave.core.Spring
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs

class EffectConfigParityTest {
    @Test
    fun kotlinDefaultsMatchEffectJson() {
        val fromFile = EffectConfig.fromJson(File(CorePaths.core, "effect.json").readText())
        assertEquals("core/effect.json and EffectConfig.DEFAULTS differ; update both together", EffectConfig.DEFAULTS, fromFile)
    }
}

class SpringTest {
    @Test
    fun settlesWithoutOvershoot() {
        val s = Spring(6.0)
        s.reset(0.0)
        var peak = 0.0
        var x = 0.0
        var t = 0.0
        while (t < 1.0) {
            x = s.step(100.0, 0.02)
            peak = maxOf(peak, x)
            t += 0.02
        }
        assertTrue(abs(x - 100.0) < 1.0)
        assertTrue(peak <= 100.0 + 1e-9)
    }

    @Test
    fun frameRateIndependent() {
        val fine = Spring(6.0).apply { reset(10.0) }
        val coarse = Spring(6.0).apply { reset(10.0) }
        var xFine = 0.0
        repeat(100) { xFine = fine.step(50.0, 0.01) }
        val xCoarse = coarse.step(50.0, 1.0)
        assertEquals(xFine, xCoarse, 1e-6)
    }
}

class PhoneFixtureTest {
    private fun fixtures(prefix: String) = File(CorePaths.core, "fixtures").listFiles()!!
        .filter { it.name.startsWith(prefix) && it.name.endsWith(".json") }
        .sortedBy { it.name }

    @Test
    fun phoneMappingFixturesReplay() {
        val pm = PhoneMapping(EffectConfig.DEFAULTS)
        val files = fixtures("phone-").filter { JSONObject(it.readText()).getString("platform") == "phone" }
        assertTrue("expected phone fixtures", files.size >= 2)
        for (file in files) {
            val fx = JSONObject(file.readText())
            val panel = fx.getString("panel")
            val tol = fx.getJSONObject("tolerance")
            val samples = fx.getJSONArray("samples")
            val byTime = HashMap<Double, Double>()
            for (i in 0 until samples.length()) {
                val s = samples.getJSONArray(i)
                byTime[s.getDouble(0)] = s.getDouble(1)
            }
            val expect = fx.getJSONArray("expect")
            for (i in 0 until expect.length()) {
                val e = expect.getJSONObject(i)
                val angle = byTime[e.getDouble("t")] ?: error("${file.name}: no sample at t=${e.getDouble("t")}")
                val progress = if (panel == "inner") pm.inner(angle) else pm.cover(angle)
                assertEquals("${file.name} t=${e.getDouble("t")} progress", e.getDouble("progress"), progress, tol.getDouble("progress"))
                assertEquals("${file.name} t=${e.getDouble("t")} tilt", e.getDouble("tilt"), pm.tilt(angle), tol.getDouble("deg"))
                assertEquals("${file.name} t=${e.getDouble("t")} settled", e.getBoolean("settled"), pm.isSettled(angle))
            }
        }
    }

    @Test
    fun detentFixturesReplay() {
        val files = fixtures("phone-").filter { JSONObject(it.readText()).getString("platform") == "phone-detent" }
        assertTrue("expected detent fixtures", files.size >= 2)
        for (file in files) {
            val fx = JSONObject(file.readText())
            val d = DetentDetector()
            val values = fx.getJSONArray("values")
            for (i in 0 until values.length()) d.feed(values.getDouble(i))
            assertEquals(file.name, fx.getBoolean("expectDetent"), d.isDetent)
        }
    }
}

class SplashFixtureTest {
    @Test
    fun splashTimelinesReplay() {
        val files = File(CorePaths.core, "fixtures").listFiles()!!
            .filter { it.name.startsWith("splash-") && it.name.endsWith(".json") }
            .sortedBy { it.name }
        assertTrue("expected splash fixtures", files.size >= 3)
        for (file in files) {
            val fx = JSONObject(file.readText())
            val tol = fx.getJSONObject("tolerance").getDouble("value")
            val events = fx.getJSONArray("events")
            val pending = ArrayList<Pair<Double, String>>()
            for (i in 0 until events.length()) {
                val e = events.getJSONObject(i)
                pending.add(e.getDouble("t") to e.getString("kind"))
            }
            pending.sortBy { it.first }
            val tl = SplashTimeline()
            val expect = fx.getJSONArray("expect")
            for (i in 0 until expect.length()) {
                val e = expect.getJSONObject(i)
                val t = e.getDouble("t")
                while (pending.isNotEmpty() && pending[0].first <= t) {
                    val (et, kind) = pending.removeAt(0)
                    when (kind) {
                        "trigger" -> tl.trigger(et)
                        "motion" -> tl.motion(et)
                        "settle" -> tl.settle(et)
                    }
                }
                val o = tl.frame(t)
                assertEquals("${file.name} t=$t state", e.getString("state"), o.state.name.lowercase())
                assertEquals("${file.name} t=$t front", e.getDouble("front"), o.front, tol)
                assertEquals("${file.name} t=$t ring", e.getDouble("ring"), o.ring, tol)
                assertEquals("${file.name} t=$t wet", e.getDouble("wet"), o.wet, tol)
            }
        }
    }
}
