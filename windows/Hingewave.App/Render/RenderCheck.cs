using System.Drawing;
using System.Drawing.Imaging;
using System.Text.Json;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace Hingewave.App.Render;

/// <summary>
/// Renders core/test-card.png at every entry of core/golden/index.json through the
/// HLSL shader on the WARP software rasteriser and compares with the golden PNGs by PSNR.
/// </summary>
public static class RenderCheck
{
    private sealed record Entry(string file, double tilt, double progress);
    private sealed record Index(int width, int height, double minPsnrDb, Entry[] entries);

    public static string? LocateCore(string? start = null)
    {
        var dir = new DirectoryInfo(start ?? Directory.GetCurrentDirectory());
        for (var i = 0; i < 8 && dir != null; i++, dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "core", "golden", "index.json"))) return Path.Combine(dir.FullName, "core");
        }
        return null;
    }

    public static int Run(string outputDir, string? coreDir)
    {
        var core = coreDir ?? LocateCore();
        if (core == null)
        {
            Console.WriteLine("core/ not found; run from the repository or pass --core <dir>");
            return 2;
        }
        Directory.CreateDirectory(outputDir);
        var index = JsonSerializer.Deserialize<Index>(File.ReadAllText(Path.Combine(core, "golden", "index.json")),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;

        using var device = FoldRenderer.CreateDevice(preferWarp: true);
        using var renderer = new FoldRenderer(device);
        using var source = Pixels.LoadTexture(device, Path.Combine(core, "test-card.png"));
        using var target = device.CreateTexture2D(new Texture2DDescription
        {
            Width = (uint)index.width,
            Height = (uint)index.height,
            MipLevels = 1,
            ArraySize = 1,
            Format = Format.B8G8R8A8_UNorm,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.RenderTarget,
        });
        using var rtv = device.CreateRenderTargetView(target);

        var failures = 0;
        Console.WriteLine("golden             tilt progress  psnr(dB)   result");
        foreach (var e in index.entries)
        {
            renderer.Render(source, e.tilt, e.progress, rtv, index.width, index.height);
            var actual = Pixels.ReadBack(device, target);
            var golden = Pixels.LoadBgra(Path.Combine(core, "golden", e.file));
            var db = Pixels.Psnr(actual, golden);
            Pixels.Save(actual, Path.Combine(outputDir, e.file));
            var ok = db >= index.minPsnrDb;
            if (!ok) failures++;
            Console.WriteLine($"{e.file,-16} {e.tilt,6:F1} {e.progress,8:F2} {db,9:F2}   {(ok ? "ok" : "FAIL")}");
        }
        Console.WriteLine($"wrote actual renders to {outputDir}");
        return failures == 0 ? 0 : 1;
    }
}

/// <summary>Minimal PNG in/out and pixel math on BGRA byte buffers.</summary>
public static class Pixels
{
    public sealed record Image(int Width, int Height, byte[] Bgra);

    public static Image LoadBgra(string path)
    {
        using var bmp = new Bitmap(path);
        var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
        var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var bytes = new byte[bmp.Width * bmp.Height * 4];
            for (var y = 0; y < bmp.Height; y++)
            {
                System.Runtime.InteropServices.Marshal.Copy(data.Scan0 + y * data.Stride, bytes, y * bmp.Width * 4, bmp.Width * 4);
            }
            return new Image(bmp.Width, bmp.Height, bytes);
        }
        finally
        {
            bmp.UnlockBits(data);
        }
    }

    public static ID3D11Texture2D LoadTexture(ID3D11Device device, string path)
    {
        var image = LoadBgra(path);
        var handle = System.Runtime.InteropServices.GCHandle.Alloc(image.Bgra, System.Runtime.InteropServices.GCHandleType.Pinned);
        try
        {
            var init = new SubresourceData(handle.AddrOfPinnedObject(), (uint)(image.Width * 4));
            return device.CreateTexture2D(new Texture2DDescription
            {
                Width = (uint)image.Width,
                Height = (uint)image.Height,
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

    public static Image ReadBack(ID3D11Device device, ID3D11Texture2D texture)
    {
        var desc = texture.Description;
        int width = (int)desc.Width, height = (int)desc.Height;
        using var staging = device.CreateTexture2D(new Texture2DDescription
        {
            Width = desc.Width,
            Height = desc.Height,
            MipLevels = 1,
            ArraySize = 1,
            Format = desc.Format,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Staging,
            CPUAccessFlags = CpuAccessFlags.Read,
        });
        var ctx = device.ImmediateContext;
        ctx.CopyResource(staging, texture);
        var mapped = ctx.Map(staging, 0, MapMode.Read);
        try
        {
            var bytes = new byte[width * height * 4];
            for (var y = 0; y < height; y++)
            {
                System.Runtime.InteropServices.Marshal.Copy(mapped.DataPointer + (nint)(y * (int)mapped.RowPitch), bytes, y * width * 4, width * 4);
            }
            return new Image(width, height, bytes);
        }
        finally
        {
            ctx.Unmap(staging, 0);
        }
    }

    public static void Save(Image image, string path)
    {
        using var bmp = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
        var rect = new Rectangle(0, 0, image.Width, image.Height);
        var data = bmp.LockBits(rect, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        try
        {
            for (var y = 0; y < image.Height; y++)
            {
                System.Runtime.InteropServices.Marshal.Copy(image.Bgra, y * image.Width * 4, data.Scan0 + y * data.Stride, image.Width * 4);
            }
        }
        finally
        {
            bmp.UnlockBits(data);
        }
        bmp.Save(path, ImageFormat.Png);
    }

    /// <summary>PSNR over the BGR channels, pixel values scaled to [0, 1].</summary>
    public static double Psnr(Image a, Image b)
    {
        if (a.Width != b.Width || a.Height != b.Height) return 0;
        double sum = 0;
        long n = 0;
        for (var i = 0; i < a.Bgra.Length; i += 4)
        {
            for (var c = 0; c < 3; c++)
            {
                var d = (a.Bgra[i + c] - b.Bgra[i + c]) / 255.0;
                sum += d * d;
                n++;
            }
        }
        var mse = sum / n;
        return mse == 0 ? double.PositiveInfinity : 10.0 * Math.Log10(1.0 / mse);
    }
}
