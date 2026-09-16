import Foundation
import simd

/// Uniforms shared with the Metal shader. Layout must match `FoldUniforms` in
/// `FoldShader.source` exactly: six floats then a float2, 32 bytes.
struct FoldUniforms {
    var tilt: Float          // radians
    var progress: Float      // 0 open, 1 folded
    var eyeDistance: Float   // panel heights
    var maxBlurPx: Float     // effect maxBlur * panel height in pixels
    var darkenGain: Float
    var blurFloor: Float   // effect blurFloor, blur kept at the hinge
    var texSize: SIMD2<Float>
}

/// Metal port of core/shader/hingewave.glsl. Compiled at runtime so the app
/// builds with the Command Line Tools alone, no Xcode required.
enum FoldShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FoldUniforms {
        float tilt;
        float progress;
        float eyeDistance;
        float maxBlurPx;
        float darkenGain;
        float blurFloor;
        float2 texSize;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;   // (0,0) top-left of the target, (1,1) bottom-right
    };

    vertex VOut fold_vertex(uint vid [[vertex_id]]) {
        float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        float2 p = corners[vid];
        VOut o;
        o.position = float4(p, 0.0, 1.0);
        o.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
        return o;
    }

    fragment float4 fold_fragment(VOut in [[stage_in]],
                                  texture2d<float> picture [[texture(0)]],
                                  sampler smp [[sampler(0)]],
                                  constant FoldUniforms& U [[buffer(0)]]) {
        // Hinge along the bottom edge: u grows upward from the hinge, v runs left to right.
        float u = 1.0 - in.uv.y;
        float v = in.uv.x;

        // Section 2.2: trace from the eye through the tilted panel to the resting plane.
        float dz = u * sin(U.tilt);
        float t = U.eyeDistance / (U.eyeDistance - dz);
        float u2 = 0.5 + t * (u * cos(U.tilt) - 0.5);
        float v2 = 0.5 + t * (v - 0.5);
        if (u2 < 0.0 || u2 > 1.0 || v2 < 0.0 || v2 > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        // Section 2.3: blur radius grows from the hinge outward. Mip chain plus a small disc.
        float r = U.maxBlurPx * U.progress * (U.blurFloor + (1.0 - U.blurFloor) * u);
        float lod = log2(max(r * 1.4, 1.0));
        float2 p = float2(v2, 1.0 - u2);
        float2 o = (r * 0.6) / U.texSize;
        float3 c = picture.sample(smp, p, level(lod)).rgb * 0.4;
        c += picture.sample(smp, p + float2( o.x, 0.0), level(lod)).rgb * 0.15;
        c += picture.sample(smp, p + float2(-o.x, 0.0), level(lod)).rgb * 0.15;
        c += picture.sample(smp, p + float2(0.0,  o.y), level(lod)).rgb * 0.15;
        c += picture.sample(smp, p + float2(0.0, -o.y), level(lod)).rgb * 0.15;

        // Section 2.4: darkening from the hinge outward.
        float k = clamp(U.darkenGain * U.progress * (0.35 + 0.65 * u), 0.0, 1.0);
        return float4(c * (1.0 - k), 1.0);
    }
    """
}
