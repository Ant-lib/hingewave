namespace Hingewave.App;

/// <summary>Appends timestamped lines to %LOCALAPPDATA%\Hingewave\Hingewave.log. Never logs screen content.</summary>
public static class Log
{
    private static readonly object Gate = new();
    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Hingewave", "Hingewave.log");

    public static void Info(string message)
    {
        var line = $"{DateTime.UtcNow:O} {message}";
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                File.AppendAllText(Path, line + Environment.NewLine);
            }
            catch
            {
                // Logging must never take the app down.
            }
        }
        if (Environment.UserInteractive && Console.IsErrorRedirected == false)
        {
            Console.Error.WriteLine(line);
        }
    }
}
