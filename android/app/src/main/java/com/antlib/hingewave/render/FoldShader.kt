package com.antlib.hingewave.render

/**
 * AGSL port of core/shader/hingewave.glsl (docs/design.md section 2).
 *
 * Blur uses a pyramid of five pre-scaled copies of the picture bound as child
 * shaders; the level is chosen by blur radius and neighbouring levels are mixed,
 * which is the same mip-chain approach as the Metal port.
 *
 * Coordinates: `hingeEdge` says where the hinge is on the drawn rectangle
 * (0 bottom, 1 left, 2 right, 3 top). `region` limits the effect to a band of u
 * (0 at the hinge, 1 at the far edge) so a book-style inner panel can fold only
 * its moving half while the other half stays sharp.
 */
object FoldShader {
    const val LEVELS = 5

    val source = """
        uniform shader level0;
        uniform shader level1;
        uniform shader level2;
        uniform shader level3;
        uniform shader level4;
        uniform float2 size;          // drawn rectangle in pixels
        uniform float2 picSize;       // level0 picture size in pixels
        uniform float tilt;           // radians
        uniform float progress;       // 0 open, 1 folded
        uniform float eyeDistance;    // panel heights
        uniform float maxBlurPx;      // maxBlur * panel extent perpendicular to the hinge
        uniform float blurFloor;      // blur kept at the hinge, 0..1
        uniform float darkenGain;
        uniform int hingeEdge;        // 0 bottom, 1 left, 2 right, 3 top
        uniform float2 region;        // [start, end] of the folding band along the hinge axis, in 0..1 of size

        half4 samplePyramid(float2 p, float lod) {
            // p in picture pixels at level0 scale
            float l = clamp(lod, 0.0, float(${LEVELS - 1}));
            int lo = int(floor(l));
            float f = l - float(lo);
            half4 a; half4 b;
            if (lo == 0)      { a = level0.eval(p);        b = level1.eval(p * 0.5); }
            else if (lo == 1) { a = level1.eval(p * 0.5);  b = level2.eval(p * 0.25); }
            else if (lo == 2) { a = level2.eval(p * 0.25); b = level3.eval(p * 0.125); }
            else if (lo == 3) { a = level3.eval(p * 0.125); b = level4.eval(p * 0.0625); }
            else              { a = level4.eval(p * 0.0625); b = a; }
            return mix(a, b, half(f));
        }

        half4 main(float2 frag) {
            // Normalised position on the drawn rectangle, then (u, v) with the hinge at u = 0.
            float2 n = frag / size;
            float u; float v;
            if (hingeEdge == 0)      { u = 1.0 - n.y; v = n.x; }
            else if (hingeEdge == 1) { u = n.x;       v = n.y; }
            else if (hingeEdge == 2) { u = 1.0 - n.x; v = n.y; }
            else                     { u = n.y;       v = n.x; }

            // Outside the folding band: draw the picture untouched.
            float span = region.y - region.x;
            if (span <= 0.0 || u < region.x || u > region.y) {
                return level0.eval(n * picSize);
            }
            float ub = (u - region.x) / span;   // 0 at the hinge side of the band, 1 at its far edge

            float dz = ub * sin(tilt);
            float t = eyeDistance / (eyeDistance - dz);
            float u2 = 0.5 + t * (ub * cos(tilt) - 0.5);
            float v2 = 0.5 + t * (v - 0.5);
            if (u2 < 0.0 || u2 > 1.0 || v2 < 0.0 || v2 > 1.0) {
                return half4(0.0, 0.0, 0.0, 1.0);
            }

            // Map (u2, v2) back to the rectangle, then to picture pixels.
            float uf = region.x + u2 * span;
            float2 m;
            if (hingeEdge == 0)      { m = float2(v2, 1.0 - uf); }
            else if (hingeEdge == 1) { m = float2(uf, v2); }
            else if (hingeEdge == 2) { m = float2(1.0 - uf, v2); }
            else                     { m = float2(v2, uf); }
            float2 p = m * picSize;

            float r = maxBlurPx * progress * (blurFloor + (1.0 - blurFloor) * ub);
            float lod = log2(max(r * 1.4, 1.0));
            float o = r * 0.6;
            half4 c = samplePyramid(p, lod) * 0.4;
            c += samplePyramid(p + float2( o, 0.0), lod) * 0.15;
            c += samplePyramid(p + float2(-o, 0.0), lod) * 0.15;
            c += samplePyramid(p + float2(0.0,  o), lod) * 0.15;
            c += samplePyramid(p + float2(0.0, -o), lod) * 0.15;

            float k = clamp(darkenGain * progress * (0.35 + 0.65 * ub), 0.0, 1.0);
            return half4(c.rgb * half(1.0 - k), 1.0);
        }
    """.trimIndent()
}
