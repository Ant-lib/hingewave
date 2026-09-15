package com.antlib.hingewave.render

/**
 * AGSL ripple shader for Splash mode (foldables that only report hinge detents).
 *
 * A ring leaves the hinge line and travels to the far edge, refracting the picture
 * through a Gaussian bump with a bright crest; behind it a slow swell keeps the
 * water alive; a few droplets trail the front. `wet` scales everything so the
 * timeline can drain it away. `hinge` is the hinge position along the fold axis
 * in 0..1 of the panel (0.5 for a book-style inner panel, 0 or 1 for a cover).
 */
object SplashShader {
    val source = """
        uniform shader picture;
        uniform float2 size;          // drawn rectangle in pixels
        uniform float2 picSize;       // picture size in pixels
        uniform int hingeEdge;        // 0 bottom, 1 left, 2 right, 3 top: which edge u = 0 is on
        uniform float hinge;          // hinge position along u, 0..1
        uniform float front;          // ripple front, 0 at the hinge, 1 at the far edge
        uniform float ring;           // ring amplitude 0..1
        uniform float wet;            // water presence 0..1
        uniform float age;            // seconds since the splash started
        uniform float swellHz;

        float gauss(float x, float w) { return exp(-(x * x) / (2.0 * w * w)); }

        float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

        half4 main(float2 frag) {
            float2 n = frag / size;
            float u; float v;
            if (hingeEdge == 0)      { u = 1.0 - n.y; v = n.x; }
            else if (hingeEdge == 1) { u = n.x;       v = n.y; }
            else if (hingeEdge == 2) { u = 1.0 - n.x; v = n.y; }
            else                     { u = n.y;       v = n.x; }

            // Distance from the hinge toward the nearest far edge, 0..1, and its sign.
            float span = max(hinge, 1.0 - hinge);
            float side = (u >= hinge) ? 1.0 : -1.0;
            float d = abs(u - hinge) / span;

            // Ripple ring: derivative-of-Gaussian refraction plus a bright crest.
            float w = 0.05;
            float x = d - front;
            float bump = gauss(x, w);
            float refract = ring * wet * 0.03 * (-x / (w * w)) * bump * w;
            float crest = ring * wet * bump;

            // Swell behind the front: slow standing wave that fades toward the far edge.
            float behind = wet * smoothstep(0.0, 0.08, front - d);
            float swell = behind * 0.006 * sin(d * 34.0 - age * 6.2831853 * swellHz) * (1.0 - d * 0.5);

            // Droplets trailing the front along random lanes.
            float drop = 0.0;
            for (int i = 0; i < 5; i++) {
                float fi = float(i);
                float dd = front - 0.06 - fi * 0.045;
                float dv = 0.15 + 0.7 * hash(fi + 1.0);
                float2 p = float2((d - dd) * 1.0, (v - dv) * 0.6);
                float r = 0.012 + 0.006 * hash(fi + 9.0);
                float m = gauss(length(p), r) * ring * wet * step(0.0, dd);
                drop += m;
                refract += m * 0.02 * (d - dd) / r;
            }

            float uShift = side * (refract + swell);
            float u2 = clamp(u + uShift, 0.0, 1.0);
            float v2 = v;

            float2 m2;
            if (hingeEdge == 0)      { m2 = float2(v2, 1.0 - u2); }
            else if (hingeEdge == 1) { m2 = float2(u2, v2); }
            else if (hingeEdge == 2) { m2 = float2(1.0 - u2, v2); }
            else                     { m2 = float2(v2, u2); }
            half4 c = picture.eval(m2 * picSize);

            // Wet tint behind the front, crest and droplet highlights.
            half3 tint = half3(0.86, 0.95, 1.08);
            c.rgb = mix(c.rgb, c.rgb * tint, half(0.35 * behind));
            c.rgb = c.rgb * half(1.0 - 0.10 * behind);
            c.rgb += half3(0.9, 0.97, 1.0) * half(0.45 * crest + 0.6 * drop);
            return half4(clamp(c.rgb, half3(0.0), half3(1.0)), 1.0);
        }
    """.trimIndent()
}
