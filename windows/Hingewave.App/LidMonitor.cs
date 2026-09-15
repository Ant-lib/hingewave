using System.Diagnostics;
using Hingewave.App.Angle;
using Hingewave.Core;

namespace Hingewave.App;

/// <summary>
/// Polls an angle source at a fixed rate on a background thread, runs the motion
/// model, and delivers each output on the UI thread through <see cref="Post"/>.
/// </summary>
public sealed class LidMonitor : IDisposable
{
    public readonly record struct Sample(double Angle, double Smoothed, MotionOutput Output, bool SourceFinished);

    public IAngleSource Source { get; }
    public double Hz { get; }

    private readonly LaptopMotionModel _model;
    private readonly object _gate = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private Thread? _thread;
    private volatile bool _running;

    /// <summary>Marshals a callback to the UI thread. Set by the host before <see cref="Start"/>.</summary>
    public Action<Action> Post { get; set; } = a => a();

    /// <summary>Delivered on the UI thread for every poll.</summary>
    public Action<Sample>? OnSample { get; set; }

    public LidMonitor(IAngleSource source, LaptopMotionModel model, double hz = 50)
    {
        Source = source;
        _model = model;
        Hz = hz;
    }

    public bool ReduceMotion
    {
        get { lock (_gate) return _model.ReduceMotion; }
        set { lock (_gate) _model.ReduceMotion = value; }
    }

    public void Start()
    {
        if (_thread != null) return;
        _running = true;
        _thread = new Thread(Loop) { Name = "hingewave-lid", IsBackground = true, Priority = ThreadPriority.AboveNormal };
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        _thread = null;
    }

    public void CaptureReady()
    {
        lock (_gate) _model.CaptureReady(_clock.Elapsed.TotalSeconds);
    }

    public void DisplayOff()
    {
        lock (_gate) _model.DisplayOff();
    }

    private void Loop()
    {
        var interval = 1.0 / Hz;
        var next = _clock.Elapsed.TotalSeconds;
        while (_running)
        {
            if (Source.Read() is double angle)
            {
                var now = _clock.Elapsed.TotalSeconds;
                MotionOutput output;
                double smoothed;
                lock (_gate)
                {
                    output = _model.Feed(now, angle);
                    smoothed = _model.SmoothedAngle;
                }
                var sample = new Sample(angle, smoothed, output, Source.Finished);
                Post(() => OnSample?.Invoke(sample));
            }
            next += interval;
            var sleep = next - _clock.Elapsed.TotalSeconds;
            if (sleep > 0) Thread.Sleep(TimeSpan.FromSeconds(sleep));
            else next = _clock.Elapsed.TotalSeconds;
        }
    }

    public void Dispose()
    {
        Stop();
        Source.Dispose();
    }
}
