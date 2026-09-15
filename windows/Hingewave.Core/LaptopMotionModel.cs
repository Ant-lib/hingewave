namespace Hingewave.Core;

public enum MotionState
{
    Idle,
    Armed,
    Active,
    Clearing,
}

/// <summary>One frame of the motion model.</summary>
/// <param name="State">Current state.</param>
/// <param name="Tilt">Degrees the panel has rotated away from the resting plane.</param>
/// <param name="Progress">0 open, 1 fully folded.</param>
/// <param name="Capture">The host should be capturing the screen.</param>
public readonly record struct MotionOutput(MotionState State, double Tilt, double Progress, bool Capture)
{
    public static readonly MotionOutput Idle = new(MotionState.Idle, 0.0, 0.0, false);
}

public static class Easing
{
    public static double Smoothstep(double x)
    {
        if (x <= 0.0) return 0.0;
        if (x >= 1.0) return 1.0;
        return x * x * (3.0 - 2.0 * x);
    }
}

/// <summary>
/// Motion model for laptop lids. Executable form of docs/design.md section 3.2,
/// mirroring core/reference/hingewave_ref/motion.py and verified by core/fixtures.
/// </summary>
public sealed class LaptopMotionModel
{
    private const double StillSpeed = 2.0;
    private const double EndMargin = 2.0;
    /// <summary>Within this many degrees of the rest angle counts as reopened.</summary>
    private const double ReopenMargin = 2.0;

    public EffectConfig Config { get; }
    public bool ReduceMotion { get; set; }
    public MotionState State { get; private set; } = MotionState.Idle;
    public bool CaptureSeen { get; private set; }

    /// <summary>The smoothed angle after the last feed, for display.</summary>
    public double SmoothedAngle => _spring.X;

    private readonly Spring _spring;
    private double? _lastT;
    private double? _stillSince;
    private double? _clearStarted;
    private double? _restStillSince;

    /// <summary>Angle the lid rests at; follows the lid whenever it has been still for RestSeconds while idle.</summary>
    public double? RestAngle { get; private set; }

    public LaptopMotionModel(EffectConfig? config = null, bool reduceMotion = false)
    {
        Config = config ?? EffectConfig.Defaults;
        ReduceMotion = reduceMotion;
        _spring = new Spring(Config.SpringHz);
    }

    public void CaptureReady(double t)
    {
        CaptureSeen = true;
        if (State == MotionState.Armed) State = MotionState.Active;
    }

    public void DisplayOff() => GoIdle();

    public MotionOutput Feed(double t, double angle)
    {
        double x, v;
        if (_lastT is double last)
        {
            (x, v) = _spring.Step(angle, t - last);
        }
        else
        {
            _spring.Reset(angle);
            x = angle;
            v = 0.0;
        }
        _lastT = t;

        var lp = Config.Laptop;

        if (State == MotionState.Idle)
        {
            RestAngle ??= x;
            if (Math.Abs(v) < StillSpeed)
            {
                if (_restStillSince is double since)
                {
                    if (t - since >= lp.RestSeconds) RestAngle = x;
                }
                else
                {
                    _restStillSince = t;
                }
            }
            else
            {
                _restStillSince = null;
            }
            if (RestAngle is double rest && rest - x >= lp.ArmDelta && v <= -lp.ArmVelocity)
            {
                State = MotionState.Armed;
                CaptureSeen = false;
                _stillSince = null;
            }
        }

        if (State is MotionState.Armed or MotionState.Active)
        {
            if (RestAngle is double r && x > r - ReopenMargin)
            {
                BeginClearing(t);
            }
            else if (Math.Abs(v) < StillSpeed && x > lp.EndAngle + EndMargin)
            {
                if (_stillSince is double since)
                {
                    if (t - since >= Config.StillSeconds) BeginClearing(t);
                }
                else
                {
                    _stillSince = t;
                }
            }
            else
            {
                _stillSince = null;
            }
        }

        if (State == MotionState.Idle) return MotionOutput.Idle;

        var (tilt, progress) = Shape(x);

        if (State == MotionState.Clearing && _clearStarted is double started)
        {
            var k = 1.0 - (t - started) / Config.ClearSeconds;
            if (k <= 0.0)
            {
                GoIdle();
                return MotionOutput.Idle;
            }
            tilt *= k;
            progress *= k;
        }

        return new MotionOutput(State, tilt, progress, true);
    }

    private (double Tilt, double Progress) Shape(double x)
    {
        var lp = Config.Laptop;
        var rest = RestAngle ?? x;
        var tilt = ReduceMotion ? 0.0 : Math.Max(0.0, rest - x);
        var progress = Easing.Smoothstep((rest - x) / Math.Max(rest - lp.EndAngle, 1e-6));
        return (tilt, progress);
    }

    private void BeginClearing(double t)
    {
        if (State == MotionState.Clearing) return;
        State = MotionState.Clearing;
        _clearStarted = t;
        _stillSince = null;
    }

    private void GoIdle()
    {
        State = MotionState.Idle;
        _stillSince = null;
        _clearStarted = null;
        CaptureSeen = false;
        // Re-anchor at the current angle so a fresh close starts from here.
        RestAngle = null;
        _restStillSince = null;
    }
}
