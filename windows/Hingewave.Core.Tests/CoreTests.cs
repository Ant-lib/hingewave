using System.Text.Json;
using Hingewave.Core;
using Xunit;

namespace Hingewave.Core.Tests;

/// <summary>Locates the repository's core/ directory from the test binary location.</summary>
internal static class CorePaths
{
    public static string Core
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            for (var i = 0; i < 8 && dir != null; i++, dir = dir.Parent)
            {
                var candidate = Path.Combine(dir.FullName, "core", "effect.json");
                if (File.Exists(candidate)) return Path.Combine(dir.FullName, "core");
            }
            throw new DirectoryNotFoundException("core/effect.json not found above " + AppContext.BaseDirectory);
        }
    }
}

public class EffectConfigParityTests
{
    [Fact]
    public void DefaultsMatchEffectJson()
    {
        var fromFile = EffectConfig.Load(Path.Combine(CorePaths.Core, "effect.json"));
        Assert.Equal(EffectConfig.Defaults, fromFile);
    }
}

public class SpringTests
{
    [Fact]
    public void SettlesWithoutOvershoot()
    {
        var s = new Spring(6.0);
        s.Reset(0.0);
        double peak = 0.0, x = 0.0;
        for (var t = 0.0; t < 1.0; t += 0.02)
        {
            x = s.Step(100.0, 0.02).X;
            peak = Math.Max(peak, x);
        }
        Assert.True(Math.Abs(x - 100.0) < 1.0);
        Assert.True(peak <= 100.0 + 1e-9);
    }

    [Fact]
    public void FrameRateIndependent()
    {
        var fine = new Spring(6.0);
        var coarse = new Spring(6.0);
        fine.Reset(10.0);
        coarse.Reset(10.0);
        var xFine = 0.0;
        for (var i = 0; i < 100; i++) xFine = fine.Step(50.0, 0.01).X;
        var xCoarse = coarse.Step(50.0, 1.0).X;
        Assert.Equal(xCoarse, xFine, 6);
    }
}

public class FixtureTests
{
    private sealed record Expectation(double t, string state, double tilt, double progress, bool capture);
    private sealed record Tolerance(double deg, double progress);
    private sealed record LaptopFixture(string platform, double captureLatencyMs, bool reduceMotion, double[][] samples, Expectation[] expect, Tolerance tolerance);

    [Fact]
    public void AllLaptopFixturesReplay()
    {
        var files = Directory.GetFiles(Path.Combine(CorePaths.Core, "fixtures"), "laptop-*.json").OrderBy(f => f).ToArray();
        Assert.True(files.Length >= 4, "expected laptop fixtures in core/fixtures");
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true, IncludeFields = true };
        foreach (var file in files)
        {
            var fixture = JsonSerializer.Deserialize<LaptopFixture>(File.ReadAllText(file), options)!;
            Assert.Equal("laptop", fixture.platform);
            Replay(fixture, Path.GetFileName(file));
        }
    }

    private static void Replay(LaptopFixture fixture, string name)
    {
        var model = new LaptopMotionModel(EffectConfig.Defaults, fixture.reduceMotion);
        double? armedAt = null;
        var outputs = new Dictionary<double, MotionOutput>();
        var latency = fixture.captureLatencyMs / 1000.0;

        foreach (var sample in fixture.samples)
        {
            double t = sample[0], angle = sample[1];
            if (armedAt is double a && t >= a + latency)
            {
                model.CaptureReady(t);
                armedAt = null;
            }
            var output = model.Feed(t, angle);
            if (output.State == MotionState.Armed && armedAt == null && !model.CaptureSeen) armedAt = t;
            outputs[t] = output;
        }

        foreach (var e in fixture.expect)
        {
            Assert.True(outputs.TryGetValue(e.t, out var output), $"{name}: no output at t={e.t}");
            Assert.True(string.Equals(output.State.ToString(), e.state, StringComparison.OrdinalIgnoreCase), $"{name} t={e.t} state {output.State} != {e.state}");
            Assert.True(Math.Abs(output.Tilt - e.tilt) <= fixture.tolerance.deg, $"{name} t={e.t} tilt {output.Tilt} != {e.tilt}");
            Assert.True(Math.Abs(output.Progress - e.progress) <= fixture.tolerance.progress, $"{name} t={e.t} progress {output.Progress} != {e.progress}");
            Assert.True(output.Capture == e.capture, $"{name} t={e.t} capture");
        }
    }
}
