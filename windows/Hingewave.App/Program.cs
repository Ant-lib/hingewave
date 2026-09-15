using Hingewave.App.Angle;
using Hingewave.App.Render;
using Hingewave.App.Tray;

namespace Hingewave.App;

// Hingewave entry point.
//
//   hingewave                            run the tray app
//   hingewave --probe [sec]              print the angle source and readings for sec seconds (default 5)
//   hingewave --render-check <dir>       render the golden set on WARP and report PSNR
//              [--core <coreDir>]        (core/ is found by walking up from the cwd otherwise)
//   hingewave --simulate-close           scripted 120 to 0 to 120 lid sweep over the live desktop
//   hingewave --demo                     the same sweep over a generated picture, no capture needed
//   hingewave --preview <deg>            move to one lid angle and hold until the effect clears

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var list = args.ToList();

        var rc = list.IndexOf("--render-check");
        if (rc >= 0)
        {
            if (rc + 1 >= list.Count)
            {
                Console.WriteLine("usage: hingewave --render-check <outputDir> [--core <coreDir>]");
                return 2;
            }
            string? core = null;
            var c = list.IndexOf("--core");
            if (c >= 0 && c + 1 < list.Count) core = list[c + 1];
            return RenderCheck.Run(list[rc + 1], core);
        }

        var probe = list.IndexOf("--probe");
        if (probe >= 0)
        {
            var seconds = probe + 1 < list.Count && double.TryParse(list[probe + 1], out var s) ? s : 5;
            return Probe(seconds);
        }

        ApplicationConfiguration.Initialize();

        if (list.Contains("--simulate-close")) return RunScripted(ScriptedAngleSource.CloseAndReopen(), demo: false);
        if (list.Contains("--demo")) return RunScripted(ScriptedAngleSource.CloseAndReopen(), demo: true);
        var preview = list.IndexOf("--preview");
        if (preview >= 0 && preview + 1 < list.Count && double.TryParse(list[preview + 1], out var deg))
        {
            return RunScripted(ScriptedAngleSource.Preview(deg), demo: false);
        }

        return RunApp();
    }

    private static int Probe(double seconds)
    {
        using var source = AngleSourceSelector.Best();
        Console.WriteLine($"source: {source.Description}");
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        double? last = null;
        while (DateTime.UtcNow < deadline)
        {
            var angle = source.Read();
            if (angle != last)
            {
                Console.WriteLine(angle is double a ? $"{a:F1}" : "no reading");
                last = angle;
            }
            Thread.Sleep(20);
        }
        return 0;
    }

    private static int RunScripted(ScriptedAngleSource source, bool demo)
    {
        using var device = FoldRenderer.CreateDevice();
        using var controller = new AppController(device, source, reduceMotion: !SystemInformation.IsMenuAnimationEnabled);
        if (demo)
        {
            var bounds = Screen.PrimaryScreen?.Bounds ?? new Rectangle(0, 0, 1920, 1080);
            controller.StaticFrame = DemoPicture.MakeTexture(device, bounds.Width, bounds.Height);
        }
        var lastPrinted = -1;
        controller.OnSample = sample =>
        {
            var whole = (int)Math.Round(sample.Angle);
            if (whole == lastPrinted) return;
            Console.WriteLine($"{sample.Angle,5:F1} deg  {sample.Output.State,-8} tilt {sample.Output.Tilt,5:F1} progress {sample.Output.Progress:F2}");
            lastPrinted = whole;
        };
        controller.OnScriptFinished = () => { controller.Stop(); Application.Exit(); };
        controller.Start();
        Application.Run();
        return 0;
    }

    private static int RunApp()
    {
        Log.Info("Hingewave starting");
        using var device = FoldRenderer.CreateDevice();
        var source = AngleSourceSelector.Best();
        using var controller = new AppController(device, source, reduceMotion: !SystemInformation.IsMenuAnimationEnabled);
        using var tray = new TrayIcon(controller);
        controller.OnSample = sample => tray.Update(sample.Angle);
        controller.Start();
        Application.Run();
        return 0;
    }
}
