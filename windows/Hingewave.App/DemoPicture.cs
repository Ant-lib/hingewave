using System.Runtime.InteropServices;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace Hingewave.App;

/// <summary>A generated desktop-like picture for demos that need no capture (same look as the macOS demo).</summary>
public static class DemoPicture
{
    public static ID3D11Texture2D MakeTexture(ID3D11Device device, int width, int height)
    {
        var pixels = new byte[width * height * 4];
        float w = width, h = height;
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                float fx = x / w, fy = y / h;
                var r = 0.10f + 0.80f * fx * (0.4f + 0.6f * fy);
                var g = 0.15f + 0.35f * fy + 0.20f * fx;
                var b = 0.45f + 0.35f * (1 - fx) * (1 - fy);
                if (x % 96 == 0 || y % 96 == 0) { r *= 0.85f; g *= 0.85f; b *= 0.85f; }
                var d1 = MathF.Sqrt((fx - 0.28f) * (fx - 0.28f) + (fy - 0.35f) * h / w * ((fy - 0.35f) * h / w));
                var d2 = MathF.Sqrt((fx - 0.70f) * (fx - 0.70f) + (fy - 0.60f) * h / w * ((fy - 0.60f) * h / w));
                if (d1 < 0.12f) { var a = 0.55f * (1 - d1 / 0.12f); r += (1 - r) * a; g += (1 - g) * a; b += (1 - b) * a; }
                if (d2 < 0.16f) { var a = 0.35f * (1 - d2 / 0.16f); r *= 1 - a; g += (0.9f - g) * a; b += (0.7f - b) * a; }
                if (fy > 0.93f && fx > 0.25f && fx < 0.75f) { r = 0.92f; g = 0.92f; b = 0.94f; }
                var i = (y * width + x) * 4;
                pixels[i] = (byte)Math.Clamp(b * 255, 0, 255);
                pixels[i + 1] = (byte)Math.Clamp(g * 255, 0, 255);
                pixels[i + 2] = (byte)Math.Clamp(r * 255, 0, 255);
                pixels[i + 3] = 255;
            }
        }
        var handle = GCHandle.Alloc(pixels, GCHandleType.Pinned);
        try
        {
            var init = new SubresourceData(handle.AddrOfPinnedObject(), (uint)(width * 4));
            return device.CreateTexture2D(new Texture2DDescription
            {
                Width = (uint)width,
                Height = (uint)height,
                MipLevels = 1,
                ArraySize = 1,
                Format = Format.B8G8R8A8_UNorm,
                SampleDescription = new SampleDescription(1, 0),
                Usage = ResourceUsage.Default,
                BindFlags = BindFlags.ShaderResource,
            }, new[] { init });
        }
        finally
        {
            handle.Free();
        }
    }
}
