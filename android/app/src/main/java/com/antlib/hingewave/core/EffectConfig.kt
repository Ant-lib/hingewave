package com.antlib.hingewave.core

import org.json.JSONObject

/** Tuned effect parameters. Mirrors core/effect.json; a unit test proves the two are identical. */
data class LaptopConfig(val armDelta: Double, val restSeconds: Double, val endAngle: Double, val armVelocity: Double)

data class InnerConfig(val clearStart: Double, val clearEnd: Double)

data class CoverConfig(val frostStart: Double, val frostEnd: Double)

data class PhoneConfig(val deadZone: Double, val inner: InnerConfig, val cover: CoverConfig)

data class SplashConfig(
    val travelSeconds: Double,
    val riseSeconds: Double,
    val stillSeconds: Double,
    val drainSeconds: Double,
    val swellHz: Double,
    val motionThreshold: Double,
)

data class EffectConfig(
    val eyeDistance: Double,
    val maxBlur: Double,
    val darkenGain: Double,
    val springHz: Double,
    val stillSeconds: Double,
    val clearSeconds: Double,
    val laptop: LaptopConfig,
    val phone: PhoneConfig,
    val splash: SplashConfig,
) {
    companion object {
        /** Values copied from core/effect.json. Change them there first, then here. */
        val DEFAULTS = EffectConfig(
            eyeDistance = 2.0,
            maxBlur = 0.036,
            darkenGain = 2.0,
            springHz = 6.0,
            stillSeconds = 2.0,
            clearSeconds = 0.6,
            laptop = LaptopConfig(armDelta = 5.0, restSeconds = 0.3, endAngle = 8.0, armVelocity = 15.0),
            phone = PhoneConfig(
                deadZone = 6.0,
                inner = InnerConfig(clearStart = 100.0, clearEnd = 174.0),
                cover = CoverConfig(frostStart = 6.0, frostEnd = 26.0),
            ),
            splash = SplashConfig(
                travelSeconds = 1.2,
                riseSeconds = 0.25,
                stillSeconds = 5.0,
                drainSeconds = 1.5,
                swellHz = 0.4,
                motionThreshold = 0.3,
            ),
        )

        fun fromJson(text: String): EffectConfig {
            val o = JSONObject(text)
            val lp = o.getJSONObject("laptop")
            val ph = o.getJSONObject("phone")
            val inner = ph.getJSONObject("inner")
            val cover = ph.getJSONObject("cover")
            val sp = o.getJSONObject("splash")
            return EffectConfig(
                eyeDistance = o.getDouble("eyeDistance"),
                maxBlur = o.getDouble("maxBlur"),
                darkenGain = o.getDouble("darkenGain"),
                springHz = o.getDouble("springHz"),
                stillSeconds = o.getDouble("stillSeconds"),
                clearSeconds = o.getDouble("clearSeconds"),
                laptop = LaptopConfig(lp.getDouble("armDelta"), lp.getDouble("restSeconds"), lp.getDouble("endAngle"), lp.getDouble("armVelocity")),
                phone = PhoneConfig(
                    deadZone = ph.getDouble("deadZone"),
                    inner = InnerConfig(inner.getDouble("clearStart"), inner.getDouble("clearEnd")),
                    cover = CoverConfig(cover.getDouble("frostStart"), cover.getDouble("frostEnd")),
                ),
                splash = SplashConfig(
                    travelSeconds = sp.getDouble("travelSeconds"),
                    riseSeconds = sp.getDouble("riseSeconds"),
                    stillSeconds = sp.getDouble("stillSeconds"),
                    drainSeconds = sp.getDouble("drainSeconds"),
                    swellHz = sp.getDouble("swellHz"),
                    motionThreshold = sp.getDouble("motionThreshold"),
                ),
            )
        }
    }
}
