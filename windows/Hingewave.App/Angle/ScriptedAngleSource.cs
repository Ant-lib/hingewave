using System.Diagnostics;

namespace Hingewave.App.Angle;

/// <summary>Plays a list of (seconds, degrees) keyframes with linear interpolation. The clock starts on the first read.</summary>
public sealed class ScriptedAngleSource : IAngleSource
{
    private readonly (double T, double Angle)[] _keyframes;
    private Stopwatch? _clock;

    public ScriptedAngleSource(params (double T, double Angle)[] keyframes)
    {
        _keyframes = keyframes;
    }

    /// <summary>120 to 0 over 2 s, hold 1 s, back to 120 over 2 s, then hold 3 s for the clear.</summary>
    public static ScriptedAngleSource CloseAndReopen() =>
        new((0, 120), (0.5, 120), (2.5, 0), (3.5, 0), (5.5, 120), (8.5, 120));

    /// <summary>Quick move from 120 to <paramref name="angle"/> and hold so the stillness clear plays.</summary>
    public static ScriptedAngleSource Preview(double angle, double holdSeconds = 4) =>
        new((0, 120), (0.3, 120), (0.8, angle), (0.8 + holdSeconds, angle));

    public AngleTier Tier => AngleTier.Scripted;
    public string Description => "scripted sweep";

    private double Elapsed => _clock?.Elapsed.TotalSeconds ?? 0;

    public bool Finished => _clock != null && Elapsed >= _keyframes[^1].T;

    public double? Read()
    {
        _clock ??= Stopwatch.StartNew();
        var t = Elapsed;
        var first = _keyframes[0];
        var last = _keyframes[^1];
        if (t <= first.T) return first.Angle;
        if (t >= last.T) return last.Angle;
        for (var i = 1; i < _keyframes.Length; i++)
        {
            if (t > _keyframes[i].T) continue;
            var a = _keyframes[i - 1];
            var b = _keyframes[i];
            var f = (t - a.T) / Math.Max(b.T - a.T, 1e-9);
            return a.Angle + (b.Angle - a.Angle) * f;
        }
        return last.Angle;
    }

    public void Dispose()
    {
    }
}
