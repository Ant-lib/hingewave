using System.Runtime.InteropServices;
using Hingewave.Core;
using SharpGen.Runtime;
using Vortice.D3DCompiler;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Vortice.Mathematics;

namespace Hingewave.App.Render;

[StructLayout(LayoutKind.Sequential, Pack = 4, Size = 32)]
internal struct FoldUniforms
{
    public float Tilt;
    public float Progress;
    public float EyeDistance;
    public float MaxBlurPx;
    public float DarkenGain;
    public float BlurFloor;
    public float TexWidth;
    public float TexHeight;
}

/// <summary>
/// One Direct3D 11 pass that turns a captured picture into the folded picture.
/// The source is copied into a mipmapped scratch texture, mips are generated,
/// and the pixel shader samples them by blur radius.
/// </summary>
public sealed class FoldRenderer : IDisposable
{
    public ID3D11Device Device { get; }
    public ID3D11DeviceContext Context { get; }
    public EffectConfig Config { get; set; }

    private readonly ID3D11VertexShader _vs;
    private readonly ID3D11PixelShader _ps;
    private readonly ID3D11SamplerState _sampler;
    private readonly ID3D11RasterizerState _raster;
    private readonly ID3D11Buffer _uniforms;
    private ID3D11Texture2D? _scratch;
    private ID3D11ShaderResourceView? _scratchView;

    public FoldRenderer(ID3D11Device device, EffectConfig? config = null)
    {
        Device = device;
        Context = device.ImmediateContext;
        Config = config ?? EffectConfig.Defaults;

        var source = ShaderSource();
        using var vsBlob = Compile(source, "VS", "vs_4_0");
        using var psBlob = Compile(source, "PS", "ps_4_0");
        _vs = device.CreateVertexShader(vsBlob.AsSpan());
        _ps = device.CreatePixelShader(psBlob.AsSpan());

        _sampler = device.CreateSamplerState(new SamplerDescription
        {
            Filter = Filter.MinMagMipLinear,
            AddressU = TextureAddressMode.Clamp,
            AddressV = TextureAddressMode.Clamp,
            AddressW = TextureAddressMode.Clamp,
            MinLOD = 0,
            MaxLOD = float.MaxValue,
            MaxAnisotropy = 1,
            ComparisonFunc = ComparisonFunction.Never,
        });
        // Direct3D culls back faces by default and the full-screen triangle winds
        // counter-clockwise in screen space, so without this the draw is discarded
        // and the target stays black. Metal does not cull at all, which is why the
        // same geometry works there.
        _raster = device.CreateRasterizerState(new RasterizerDescription
        {
            FillMode = FillMode.Solid,
            CullMode = CullMode.None,
            DepthClipEnable = true,
        });

        _uniforms = device.CreateBuffer(new BufferDescription(32, BindFlags.ConstantBuffer, ResourceUsage.Dynamic, CpuAccessFlags.Write));
    }

    /// <summary>Creates a hardware device, or a WARP software device when requested or when no GPU is available.</summary>
    public static ID3D11Device CreateDevice(bool preferWarp = false)
    {
        var levels = new[] { FeatureLevel.Level_11_1, FeatureLevel.Level_11_0, FeatureLevel.Level_10_1, FeatureLevel.Level_10_0 };
        var flags = DeviceCreationFlags.BgraSupport;
        if (!preferWarp)
        {
            var hw = D3D11.D3D11CreateDevice(null, DriverType.Hardware, flags, levels, out ID3D11Device? device);
            if (hw.Success && device != null) return device;
        }
        D3D11.D3D11CreateDevice(null, DriverType.Warp, flags, levels, out ID3D11Device? warp).CheckError();
        return warp!;
    }

    public void Render(ID3D11Texture2D source, double tilt, double progress, ID3D11RenderTargetView target, int targetWidth, int targetHeight)
    {
        var desc = source.Description;
        var mipped = EnsureScratch((int)desc.Width, (int)desc.Height, desc.Format);
        Context.CopySubresourceRegion(mipped, 0, 0, 0, 0, source, 0);
        Context.GenerateMips(_scratchView!);

        var uniforms = new FoldUniforms
        {
            Tilt = (float)(tilt * Math.PI / 180.0),
            Progress = (float)progress,
            EyeDistance = (float)Config.EyeDistance,
            MaxBlurPx = (float)(Config.MaxBlur * targetHeight),
            DarkenGain = (float)Config.DarkenGain,
            BlurFloor = (float)Config.BlurFloor,
            TexWidth = desc.Width,
            TexHeight = desc.Height,
        };
        var mapped = Context.Map(_uniforms, MapMode.WriteDiscard);
        Marshal.StructureToPtr(uniforms, mapped.DataPointer, false);
        Context.Unmap(_uniforms, 0);

        Context.OMSetRenderTargets(target);
        Context.RSSetViewport(new Viewport(0, 0, targetWidth, targetHeight));
        Context.RSSetState(_raster);
        Context.IASetInputLayout(null);
        Context.IASetPrimitiveTopology(PrimitiveTopology.TriangleList);
        Context.VSSetShader(_vs);
        Context.PSSetShader(_ps);
        Context.PSSetConstantBuffer(0, _uniforms);
        Context.PSSetShaderResource(0, _scratchView!);
        Context.PSSetSampler(0, _sampler);
        Context.Draw(3, 0);
        Context.PSUnsetShaderResources(0, 1);
    }

    public void ReleaseScratch()
    {
        _scratchView?.Dispose();
        _scratch?.Dispose();
        _scratchView = null;
        _scratch = null;
    }

    private ID3D11Texture2D EnsureScratch(int width, int height, Format format)
    {
        if (_scratch != null)
        {
            var d = _scratch.Description;
            if (d.Width == width && d.Height == height && d.Format == format) return _scratch;
            ReleaseScratch();
        }
        _scratch = Device.CreateTexture2D(new Texture2DDescription
        {
            Width = (uint)width,
            Height = (uint)height,
            MipLevels = 0,
            ArraySize = 1,
            Format = format,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.ShaderResource | BindFlags.RenderTarget,
            MiscFlags = ResourceOptionFlags.GenerateMips,
        });
        _scratchView = Device.CreateShaderResourceView(_scratch);
        return _scratch;
    }

    private static string ShaderSource()
    {
        using var stream = typeof(FoldRenderer).Assembly.GetManifestResourceStream("Hingewave.App.Render.FoldShader.hlsl")
            ?? throw new InvalidOperationException("embedded FoldShader.hlsl missing");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static Blob Compile(string source, string entry, string profile)
    {
        var result = Compiler.Compile(source, entry, "FoldShader.hlsl", profile, out Blob blob, out Blob errors);
        if (result.Failure)
        {
            var message = errors != null ? Marshal.PtrToStringAnsi(errors.BufferPointer) : result.ToString();
            throw new InvalidOperationException($"shader compile failed ({entry}): {message}");
        }
        errors?.Dispose();
        return blob;
    }

    public void Dispose()
    {
        ReleaseScratch();
        _raster.Dispose();
        _uniforms.Dispose();
        _sampler.Dispose();
        _ps.Dispose();
        _vs.Dispose();
    }
}
