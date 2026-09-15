// HLSL port of core/shader/hingewave.glsl (docs/design.md section 2).
// Full-screen triangle vertex shader plus the fold pixel shader. The picture
// is sampled from a mip chain by blur radius, the same approach as the Metal
// and AGSL ports.

cbuffer FoldUniforms : register(b0)
{
    float tilt;          // radians the panel has rotated toward the viewer
    float progress;      // 0 open, 1 folded
    float eyeDistance;   // panel heights
    float maxBlurPx;     // effect maxBlur * panel height in pixels
    float darkenGain;
    float pad0;
    float2 texSize;      // picture size in pixels
};

Texture2D picture : register(t0);
SamplerState smp : register(s0);

struct VOut
{
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;   // (0,0) top-left of the target, (1,1) bottom-right
};

VOut VS(uint vid : SV_VertexID)
{
    float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 p = corners[vid];
    VOut o;
    o.position = float4(p, 0.0, 1.0);
    o.uv = float2((p.x + 1.0) * 0.5, 1.0 - (p.y + 1.0) * 0.5);
    return o;
}

float4 PS(VOut i) : SV_TARGET
{
    // Hinge along the bottom edge: u grows upward from the hinge, v runs left to right.
    float u = 1.0 - i.uv.y;
    float v = i.uv.x;

    // Section 2.2: trace from the eye through the tilted panel to the resting plane.
    float dz = u * sin(tilt);
    float t = eyeDistance / (eyeDistance - dz);
    float u2 = 0.5 + t * (u * cos(tilt) - 0.5);
    float v2 = 0.5 + t * (v - 0.5);
    if (u2 < 0.0 || u2 > 1.0 || v2 < 0.0 || v2 > 1.0)
    {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // Section 2.3: blur radius grows from the hinge outward. Mip chain plus a small disc.
    float r = maxBlurPx * progress * u;
    float lod = log2(max(r * 1.4, 1.0));
    float2 p = float2(v2, 1.0 - u2);
    float2 o = (r * 0.6) / texSize;
    float3 c = picture.SampleLevel(smp, p, lod).rgb * 0.4;
    c += picture.SampleLevel(smp, p + float2( o.x, 0.0), lod).rgb * 0.15;
    c += picture.SampleLevel(smp, p + float2(-o.x, 0.0), lod).rgb * 0.15;
    c += picture.SampleLevel(smp, p + float2(0.0,  o.y), lod).rgb * 0.15;
    c += picture.SampleLevel(smp, p + float2(0.0, -o.y), lod).rgb * 0.15;

    // Section 2.4: darkening from the hinge outward.
    float k = saturate(darkenGain * progress * (0.35 + 0.65 * u));
    return float4(c * (1.0 - k), 1.0);
}
