using System.Diagnostics;
using Hingewave.Core;

namespace Hingewave.App.Angle;

/// <summary>
/// Tier 3: only the lid switch. Windows says open or closed and nothing in between, so
/// each change plays a fixed ramp through the same motion model: 120 to 0 over
/// clearSeconds on close, 0 to 120 on open. The host feeds lid events from
/// WM_POWERBROADCAST (GUID_LIDSWITCH_STATE_CHANGE) through <see cref="OnLidChanged"/>.
/// </summary>
public sealed class LidSwitchSource : IAngleSource
{
    private const double OpenAngle = 120.0;
    private readonly double _rampSeconds;
    private readonly object _gate = new();
    private Stopwatch? _clock;
    private double _from = OpenAngle;
    private double _to = OpenAngle;

    public LidSwitchSource(EffectConfig? config = null)
    {
        _rampSeconds = (config ?? EffectConfig.Defaults).ClearSeconds;
    }

    public AngleTier Tier => AngleTier.LidSwitch;
    public string Description => "lid switch only (timed playback)";
    public bool Finished => false;

    public void OnLidChanged(bool closed)
    {
        lock (_gate)
        {
            _from = Read() ?? OpenAngle;
            _to = closed ? 0.0 : OpenAngle;
            _clock = Stopwatch.StartNew();
        }
        Log.Info(closed ? "lid closed (switch)" : "lid opened (switch)");
    }

    public double? Read()
    {
        lock (_gate)
        {
            if (_clock == null) return _to;
            var f = Math.Min(1.0, _clock.Elapsed.TotalSeconds / _rampSeconds);
            return _from + (_to - _from) * f;
        }
    }

    public void Dispose()
    {
    }
}
