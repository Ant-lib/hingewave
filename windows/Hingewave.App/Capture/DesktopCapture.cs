using System.Runtime.InteropServices;
using Vortice.Direct3D11;
using Vortice.DXGI;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using WinRT;

namespace Hingewave.App.Capture;

/// <summary>
/// Captures one monitor through Windows.Graphics.Capture into Direct3D 11 textures.
/// The overlay window is excluded by SetWindowDisplayAffinity, so the effect never
/// feeds back into its own picture. Frames stay in GPU memory and are dropped on stop.
/// </summary>
public sealed class DesktopCapture : IDisposable
{
    private readonly ID3D11Device _device;
    private readonly IDirect3DDevice _winrtDevice;
    private readonly GraphicsCaptureItem _item;
    private Direct3D11CaptureFramePool? _pool;
    private GraphicsCaptureSession? _session;
    private ID3D11Texture2D? _latest;
    private readonly object _gate = new();

    /// <summary>Called on the capture thread with every new frame; the texture is owned by this class.</summary>
    public Action? OnFrame { get; set; }

    public int Width { get; }
    public int Height { get; }

    public DesktopCapture(ID3D11Device device, IntPtr monitor)
    {
        _device = device;
        _winrtDevice = CreateWinRTDevice(device);
        _item = CreateItemForMonitor(monitor);
        Width = _item.Size.Width;
        Height = _item.Size.Height;
    }

    public static bool IsSupported() => GraphicsCaptureSession.IsSupported();

    public void Start()
    {
        _pool = Direct3D11CaptureFramePool.CreateFreeThreaded(_winrtDevice, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, new SizeInt32 { Width = Width, Height = Height });
        _pool.FrameArrived += OnFrameArrived;
        _session = _pool.CreateCaptureSession(_item);
        _session.IsCursorCaptureEnabled = false;
        try
        {
            // Windows 11 draws a yellow border around captured content unless told not to.
            if (Windows.Foundation.Metadata.ApiInformation.IsPropertyPresent("Windows.Graphics.Capture.GraphicsCaptureSession", "IsBorderRequired"))
            {
                _session.IsBorderRequired = false;
            }
        }
        catch
        {
            // Not fatal: the border only affects looks.
        }
        _session.StartCapture();
        Log.Info($"capture started {Width}x{Height}");
    }

    /// <summary>Latest frame, or null. Valid until the next frame replaces it or Stop is called.</summary>
    public ID3D11Texture2D? Latest
    {
        get { lock (_gate) return _latest; }
    }

    private void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        using var frame = sender.TryGetNextFrame();
        if (frame == null) return;
        var access = frame.Surface.As<IDirect3DDxgiInterfaceAccess>();
        var iid = typeof(ID3D11Texture2D).GUID;
        var ptr = access.GetInterface(ref iid);
        var frameTexture = new ID3D11Texture2D(ptr);
        var desc = frameTexture.Description;

        // Copy into our own texture so the frame can be returned to the pool immediately.
        lock (_gate)
        {
            if (_latest == null || _latest.Description.Width != desc.Width || _latest.Description.Height != desc.Height)
            {
                _latest?.Dispose();
                _latest = _device.CreateTexture2D(new Texture2DDescription
                {
                    Width = desc.Width,
                    Height = desc.Height,
                    MipLevels = 1,
                    ArraySize = 1,
                    Format = desc.Format,
                    SampleDescription = new SampleDescription(1, 0),
                    Usage = ResourceUsage.Default,
                    BindFlags = BindFlags.ShaderResource,
                });
            }
            _device.ImmediateContext.CopyResource(_latest, frameTexture);
        }
        frameTexture.Dispose();
        OnFrame?.Invoke();
    }

    public void Stop()
    {
        if (_session != null)
        {
            _session.Dispose();
            _session = null;
        }
        if (_pool != null)
        {
            _pool.FrameArrived -= OnFrameArrived;
            _pool.Dispose();
            _pool = null;
        }
        lock (_gate)
        {
            _latest?.Dispose();
            _latest = null;
        }
        Log.Info("capture stopped");
    }

    public void Dispose()
    {
        Stop();
    }

    // MARK: WinRT interop

    [ComImport]
    [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IGraphicsCaptureItemInterop
    {
        IntPtr CreateForWindow(IntPtr window, ref Guid iid);
        IntPtr CreateForMonitor(IntPtr monitor, ref Guid iid);
    }

    [ComImport]
    [Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDirect3DDxgiInterfaceAccess
    {
        IntPtr GetInterface(ref Guid iid);
    }

    [DllImport("d3d11.dll", EntryPoint = "CreateDirect3D11DeviceFromDXGIDevice", SetLastError = true, CharSet = CharSet.Unicode, ExactSpelling = true, CallingConvention = CallingConvention.StdCall)]
    private static extern uint CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    private static readonly Guid GraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");

    private static GraphicsCaptureItem CreateItemForMonitor(IntPtr monitor)
    {
        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var iid = GraphicsCaptureItemGuid;
        var ptr = interop.CreateForMonitor(monitor, ref iid);
        var item = GraphicsCaptureItem.FromAbi(ptr);
        Marshal.Release(ptr);
        return item;
    }

    private static IDirect3DDevice CreateWinRTDevice(ID3D11Device device)
    {
        using var dxgi = device.QueryInterface<IDXGIDevice>();
        var hr = CreateDirect3D11DeviceFromDXGIDevice(dxgi.NativePointer, out var ptr);
        if (hr != 0) throw new InvalidOperationException($"CreateDirect3D11DeviceFromDXGIDevice failed: 0x{hr:X8}");
        var winrtDevice = MarshalInterface<IDirect3DDevice>.FromAbi(ptr);
        Marshal.Release(ptr);
        return winrtDevice;
    }
}
