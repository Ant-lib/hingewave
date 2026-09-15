using System.Runtime.InteropServices;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace Hingewave.App.Overlay;

/// <summary>
/// Borderless, topmost, click-through window covering one monitor, drawn with a
/// DXGI flip-model swap chain. Excluded from screen capture so it never feeds back
/// into its own picture.
/// </summary>
public sealed class OverlayWindow : Form
{
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOPMOST = 0x00000008;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x00000011;
    private const int SW_SHOWNOACTIVATE = 4;

    private readonly ID3D11Device _device;
    private IDXGISwapChain1? _swapChain;
    private ID3D11Texture2D? _backBuffer;
    private ID3D11RenderTargetView? _rtv;

    public int PixelWidth { get; }
    public int PixelHeight { get; }

    public OverlayWindow(ID3D11Device device, Rectangle bounds)
    {
        _device = device;
        PixelWidth = bounds.Width;
        PixelHeight = bounds.Height;

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.Black;
        Text = "Hingewave overlay";
        SetBounds(bounds.X, bounds.Y, bounds.Width, bounds.Height);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOPMOST;
            return cp;
        }
    }

    protected override bool ShowWithoutActivation => true;

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        SetWindowDisplayAffinity(Handle, WDA_EXCLUDEFROMCAPTURE);
        CreateSwapChain();
    }

    /// <summary>Shows the window without taking focus.</summary>
    public void ShowNoActivate()
    {
        if (!IsHandleCreated) CreateHandle();
        ShowWindow(Handle, SW_SHOWNOACTIVATE);
        Visible = true;
    }

    /// <summary>Runs <paramref name="draw"/> against the back buffer and presents it.</summary>
    public void Draw(Action<ID3D11RenderTargetView, int, int> draw)
    {
        if (_swapChain == null || _rtv == null) return;
        draw(_rtv, PixelWidth, PixelHeight);
        _swapChain.Present(1, PresentFlags.None);
    }

    private void CreateSwapChain()
    {
        using var dxgiDevice = _device.QueryInterface<IDXGIDevice>();
        using var adapter = dxgiDevice.GetAdapter();
        using var factory = adapter.GetParent<IDXGIFactory2>();
        var desc = new SwapChainDescription1
        {
            Width = (uint)PixelWidth,
            Height = (uint)PixelHeight,
            Format = Format.B8G8R8A8_UNorm,
            BufferCount = 2,
            BufferUsage = Usage.RenderTargetOutput,
            SampleDescription = new SampleDescription(1, 0),
            Scaling = Scaling.Stretch,
            SwapEffect = SwapEffect.FlipDiscard,
            AlphaMode = AlphaMode.Ignore,
        };
        _swapChain = factory.CreateSwapChainForHwnd(_device, Handle, desc);
        _backBuffer = _swapChain.GetBuffer<ID3D11Texture2D>(0);
        _rtv = _device.CreateRenderTargetView(_backBuffer);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        // The swap chain owns the pixels.
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _rtv?.Dispose();
            _backBuffer?.Dispose();
            _swapChain?.Dispose();
            _rtv = null;
            _backBuffer = null;
            _swapChain = null;
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int cmd);
}
