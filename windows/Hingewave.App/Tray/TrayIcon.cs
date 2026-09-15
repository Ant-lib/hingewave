using System.Diagnostics;
using Hingewave.App.Angle;
using Microsoft.Win32;

namespace Hingewave.App.Tray;

/// <summary>Tray presence: angle and tier, Follow the Lid, Preview Fold, Calibrate, Start with Windows, Quit.</summary>
public sealed class TrayIcon : IDisposable
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "Hingewave";

    private readonly NotifyIcon _icon;
    private readonly AppController _controller;
    private readonly ToolStripMenuItem _status = new("Waiting for the lid") { Enabled = false };
    private readonly ToolStripMenuItem _follow = new("Follow the Lid");
    private readonly ToolStripMenuItem _preview = new("Preview Fold");
    private readonly ToolStripMenuItem _calibrate = new("Calibrate lid sensor...");
    private readonly ToolStripMenuItem _startup = new("Start with Windows");

    public TrayIcon(AppController controller)
    {
        _controller = controller;
        var menu = new ContextMenuStrip();
        menu.Items.Add(_status);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_follow);
        menu.Items.Add(_preview);
        menu.Items.Add(_calibrate);
        menu.Items.Add(_startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit Hingewave", null, (_, _) => Application.Exit()));

        _follow.Click += (_, _) => { _controller.FollowLid = !_controller.FollowLid; Refresh(); };
        _preview.Click += (_, _) => Preview();
        _calibrate.Click += (_, _) => Calibrate();
        _startup.Click += (_, _) => { SetStartup(!IsStartupEnabled()); Refresh(); };
        _calibrate.Visible = controller.Monitor.Source is AccelerometerSource;

        _icon = new NotifyIcon
        {
            Icon = MakeIcon(),
            Text = "Hingewave",
            ContextMenuStrip = menu,
            Visible = true,
        };
        Refresh();
    }

    public void Update(double angle)
    {
        var tier = _controller.Monitor.Source.Description;
        _status.Text = $"Lid: {angle:F0} deg ({tier})";
        _icon.Text = _status.Text.Length > 63 ? _status.Text[..63] : _status.Text;
    }

    private void Refresh()
    {
        _follow.Checked = _controller.FollowLid;
        _startup.Checked = IsStartupEnabled();
    }

    private static void Preview()
    {
        // Re-run this executable with the scripted sweep over the live desktop.
        try
        {
            Process.Start(new ProcessStartInfo(Environment.ProcessPath ?? "hingewave.exe", "--simulate-close") { UseShellExecute = false });
        }
        catch (Exception ex)
        {
            Log.Info("preview failed to launch: " + ex.Message);
        }
    }

    private void Calibrate()
    {
        if (_controller.Monitor.Source is not AccelerometerSource accel) return;
        if (MessageBox.Show("Open the lid to about 90 degrees, so the screen stands straight up, then press OK.",
                "Hingewave calibration, step 1 of 2", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
        var atNinety = accel.RawPitch;
        if (MessageBox.Show("Now open the lid as far as it goes, then press OK.",
                "Hingewave calibration, step 2 of 2", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
        var fullyOpen = accel.RawPitch;
        if (atNinety is double a && fullyOpen is double b)
        {
            accel.Calibrate(a, b);
            MessageBox.Show("Calibrated. Close the lid slowly to try it.", "Hingewave", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        else
        {
            MessageBox.Show("No accelerometer readings arrived. Try again in a moment.", "Hingewave", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private static bool IsStartupEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, false);
        return key?.GetValue(RunValue) is string;
    }

    private static void SetStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, true);
        if (enabled) key.SetValue(RunValue, $"\"{Environment.ProcessPath}\"");
        else key.DeleteValue(RunValue, false);
    }

    private static Icon MakeIcon()
    {
        // A small laptop glyph: screen tilted over a base line.
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var pen = new Pen(Color.White, 3);
            g.DrawLine(pen, 3, 26, 29, 26);
            g.DrawPolygon(pen, new[] { new Point(9, 6), new Point(25, 8), new Point(24, 22), new Point(8, 22) });
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
