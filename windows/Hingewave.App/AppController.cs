using System.Runtime.InteropServices;
using Hingewave.App.Angle;
using Hingewave.App.Capture;
using Hingewave.App.Overlay;
using Hingewave.App.Render;
using Hingewave.Core;
using Vortice.Direct3D11;

namespace Hingewave.App;

/// <summary>
/// Glue between the lid monitor, desktop capture, renderer and overlay window.
/// Also owns a hidden message window for power notifications (lid switch, display
/// state). All members run on the UI thread.
/// </summary>
public sealed class AppController : IDisposable
{
    public ID3D11Device Device { get; }
    public FoldRenderer Renderer { get; }
    public LidMonitor Monitor { get; }

    private readonly PowerMessageWindow _messages;
    private DesktopCapture? _capture;
    private OverlayWindow? _window;
    private MotionState _lastState = MotionState.Idle;
    private MotionOutput _lastOutput = MotionOutput.Idle;
    private bool _scriptDone;

    /// <summary>When false the model still runs but nothing is captured or shown.</summary>
    public bool FollowLid
    {
        get => _followLid;
        set
        {
            _followLid = value;
            if (!value) TearDown();
        }
    }
    private bool _followLid = true;

    /// <summary>When set, this picture is folded instead of a live capture (demo and preview before permission).</summary>
    public ID3D11Texture2D? StaticFrame { get; set; }

    public double LastAngle { get; private set; }
    public Action<LidMonitor.Sample>? OnSample { get; set; }
    public Action? OnScriptFinished { get; set; }

    public AppController(ID3D11Device device, IAngleSource source, bool reduceMotion)
    {
        Device = device;
        Renderer = new FoldRenderer(device);
        Monitor = new LidMonitor(source, new LaptopMotionModel(EffectConfig.Defaults, reduceMotion));
        _messages = new PowerMessageWindow(this);
        Monitor.Post = action => _messages.BeginInvoke(action);
    }

    public void Start()
    {
        Monitor.OnSample = Handle;
        Monitor.Start();
    }

    public void Stop()
    {
        Monitor.Stop();
        TearDown();
    }

    internal void LidSwitchChanged(bool closed)
    {
        if (Monitor.Source is LidSwitchSource lid) lid.OnLidChanged(closed);
    }

    internal void DisplayStateChanged(bool on)
    {
        if (on) return;
        Log.Info("display off");
        Monitor.DisplayOff();
        TearDown();
    }

    private void Handle(LidMonitor.Sample sample)
    {
        LastAngle = sample.Angle;
        _lastOutput = sample.Output;
        OnSample?.Invoke(sample);

        var output = sample.Output;
        if (output.State != _lastState)
        {
            Log.Info($"state {_lastState} -> {output.State} at {sample.Smoothed:F1} deg");
            _lastState = output.State;
        }

        if (FollowLid)
        {
            if (output.Capture)
            {
                if (_capture == null && _window == null) BeginCapture();
            }
            else if (_capture != null || _window != null)
            {
                TearDown();
            }

            if (output.State is MotionState.Active or MotionState.Clearing && _window != null && _window.Visible)
            {
                var frame = StaticFrame ?? _capture?.Latest;
                if (frame != null) Render(frame, output.Tilt, output.Progress);
            }
        }

        if (sample.SourceFinished && output.State == MotionState.Idle && !_scriptDone)
        {
            _scriptDone = true;
            OnScriptFinished?.Invoke();
        }
    }

    private void Render(ID3D11Texture2D frame, double tilt, double progress)
    {
        _window!.Draw((rtv, w, h) => Renderer.Render(frame, tilt, progress, rtv, w, h));
    }

    private void BeginCapture()
    {
        var screen = Screen.PrimaryScreen;
        if (screen == null)
        {
            Log.Info("no primary screen; effect skipped");
            Monitor.DisplayOff();
            return;
        }
        var bounds = screen.Bounds;

        if (StaticFrame != null)
        {
            ShowOverlay(bounds);
            return;
        }

        if (!DesktopCapture.IsSupported())
        {
            Log.Info("Windows.Graphics.Capture not supported on this Windows; effect skipped");
            Monitor.DisplayOff();
            return;
        }
        try
        {
            var monitor = MonitorFromPoint(new POINT { X = bounds.X + 1, Y = bounds.Y + 1 }, 2 /* MONITOR_DEFAULTTOPRIMARY */);
            var capture = new DesktopCapture(Device, monitor);
            capture.OnFrame = () => _messages.BeginInvoke(() => FirstFrame(capture, bounds));
            _capture = capture;
            capture.Start();
        }
        catch (Exception ex)
        {
            Log.Info("capture failed: " + ex.Message);
            Monitor.DisplayOff();
            TearDown();
        }
    }

    private void FirstFrame(DesktopCapture capture, Rectangle bounds)
    {
        if (_capture != capture || _window != null) return;
        capture.OnFrame = null;
        ShowOverlay(bounds);
    }

    private void ShowOverlay(Rectangle bounds)
    {
        var window = new OverlayWindow(Device, bounds);
        _window = window;
        var frame = StaticFrame ?? _capture?.Latest;
        window.ShowNoActivate();
        if (frame != null) Render(frame, _lastOutput.Tilt, _lastOutput.Progress);
        Monitor.CaptureReady();
        Log.Info(StaticFrame != null ? "overlay shown (static picture)" : "overlay shown");
    }

    private void TearDown()
    {
        if (_window != null)
        {
            _window.Hide();
            _window.Dispose();
            _window = null;
            Log.Info("overlay hidden");
        }
        _capture?.Dispose();
        _capture = null;
        Renderer.ReleaseScratch();
    }

    public void Dispose()
    {
        Stop();
        Monitor.Dispose();
        Renderer.Dispose();
        _messages.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
}

/// <summary>Hidden window that receives WM_POWERBROADCAST for the lid switch and display state, and marshals calls to the UI thread.</summary>
internal sealed class PowerMessageWindow : Form
{
    private const int WM_POWERBROADCAST = 0x0218;
    private const int PBT_POWERSETTINGCHANGE = 0x8013;
    private static readonly Guid GUID_LIDSWITCH_STATE_CHANGE = new("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
    private static readonly Guid GUID_CONSOLE_DISPLAY_STATE = new("6FE69556-704A-47A0-8F24-C28D936FDA47");

    private readonly AppController _controller;
    private readonly IntPtr _lidRegistration;
    private readonly IntPtr _displayRegistration;

    public PowerMessageWindow(AppController controller)
    {
        _controller = controller;
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.None;
        Opacity = 0;
        WindowState = FormWindowState.Minimized;
        CreateHandle();
        var lid = GUID_LIDSWITCH_STATE_CHANGE;
        var display = GUID_CONSOLE_DISPLAY_STATE;
        _lidRegistration = RegisterPowerSettingNotification(Handle, ref lid, 0);
        _displayRegistration = RegisterPowerSettingNotification(Handle, ref display, 0);
    }

    protected override void SetVisibleCore(bool value) => base.SetVisibleCore(false);

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_POWERBROADCAST && m.WParam.ToInt32() == PBT_POWERSETTINGCHANGE)
        {
            var setting = Marshal.PtrToStructure<POWERBROADCAST_SETTING>(m.LParam);
            if (setting.PowerSetting == GUID_LIDSWITCH_STATE_CHANGE)
            {
                _controller.LidSwitchChanged(closed: setting.Data == 0);
            }
            else if (setting.PowerSetting == GUID_CONSOLE_DISPLAY_STATE)
            {
                _controller.DisplayStateChanged(on: setting.Data != 0);
            }
        }
        base.WndProc(ref m);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            if (_lidRegistration != IntPtr.Zero) UnregisterPowerSettingNotification(_lidRegistration);
            if (_displayRegistration != IntPtr.Zero) UnregisterPowerSettingNotification(_displayRegistration);
        }
        base.Dispose(disposing);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct POWERBROADCAST_SETTING
    {
        public Guid PowerSetting;
        public uint DataLength;
        public byte Data;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr RegisterPowerSettingNotification(IntPtr recipient, ref Guid setting, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterPowerSettingNotification(IntPtr handle);
}
