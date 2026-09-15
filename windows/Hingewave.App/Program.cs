using Hingewave.App.Render;

namespace Hingewave.App;

// Hingewave entry point.
//
//   hingewave                            run the tray app (added in a later task)
//   hingewave --render-check <dir>       render the golden set on WARP and report PSNR
//              [--core <coreDir>]        (core/ is found by walking up from the cwd otherwise)

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

        Console.WriteLine("Hingewave for Windows: tray app arrives in a later task.");
        return 0;
    }
}
