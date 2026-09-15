// Hingewave reference fragment shader (GLSL ES 3.0 style, not compiled by any port).
// Ports translate this into MSL, HLSL and AGSL. The math matches docs/design.md
// section 2 and core/reference/hingewave_ref/render.py exactly; blur kernels may
// differ within the golden tolerance.
//
// Coordinates: u runs from 0 at the hinge to 1 at the far edge, v along the hinge.
// Each port maps its pixel grid and hinge edge into (u, v) before this code runs.

precision highp float;

uniform sampler2D uPicture;      // captured panel picture, mipmapped, clamp to edge
uniform float uTilt;             // radians the panel has rotated toward the viewer
uniform float uProgress;         // 0 open, 1 fully folded
uniform float uAspect;           // length along the hinge / length perpendicular
uniform float uEyeDistance;      // panel heights, effect.json eyeDistance
uniform float uMaxBlurPx;        // effect.json maxBlur * panel extent perpendicular to hinge, in pixels
uniform float uDarkenGain;       // effect.json darkenGain
uniform vec2  uPictureSize;      // pixels, (along hinge, perpendicular to hinge)

in vec2 vUV;                     // (v, u): x along the hinge, y perpendicular, hinge at y = 0
out vec4 fragColor;

void main() {
    float u = vUV.y;
    float v = vUV.x;

    // Section 2.2: trace from the eye through the tilted panel to the resting plane.
    float dz = u * sin(uTilt);
    float t = uEyeDistance / (uEyeDistance - dz);
    float u2 = 0.5 + t * (u * cos(uTilt) - 0.5);
    float v2 = 0.5 + t * (v - 0.5);
    if (u2 < 0.0 || u2 > 1.0 || v2 < 0.0 || v2 > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // Section 2.3: blur radius grows from the hinge outward.
    float r = uMaxBlurPx * uProgress * u;
    float lod = log2(max(r, 1.0));
    vec2 texel = 1.0 / uPictureSize;
    vec2 p = vec2(v2, u2);
    vec3 c = textureLod(uPicture, p, lod).rgb * 0.4;
    c += textureLod(uPicture, p + vec2( r,  0.0) * texel * 0.5, lod).rgb * 0.15;
    c += textureLod(uPicture, p + vec2(-r,  0.0) * texel * 0.5, lod).rgb * 0.15;
    c += textureLod(uPicture, p + vec2(0.0,  r) * texel * 0.5, lod).rgb * 0.15;
    c += textureLod(uPicture, p + vec2(0.0, -r) * texel * 0.5, lod).rgb * 0.15;

    // Section 2.4: darkening from the hinge outward, twice the progress strength.
    float k = clamp(uDarkenGain * uProgress * (0.35 + 0.65 * u), 0.0, 1.0);
    fragColor = vec4(c * (1.0 - k), 1.0);
}
