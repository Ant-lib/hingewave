using Windows.Devices.Sensors;

namespace Hingewave.App.Angle;

/// <summary>Tier 1: a real hinge angle sensor. Rare on laptops, but the best source when present.</summary>
public sealed class HingeSensorSource : IAngleSource
{
    private readonly HingeAngleSensor _sensor;
    private double? _latest;

    private HingeSensorSource(HingeAngleSensor sensor)
    {
        _sensor = sensor;
        _sensor.ReportThresholdInDegrees = 0.5;
        _sensor.ReadingChanged += (_, e) => _latest = e.Reading.AngleInDegrees;
    }

    /// <summary>Returns null when Windows reports no hinge angle sensor.</summary>
    public static HingeSensorSource? TryCreate()
    {
        try
        {
            var sensor = HingeAngleSensor.GetDefaultAsync().AsTask().GetAwaiter().GetResult();
            if (sensor == null) return null;
            var source = new HingeSensorSource(sensor);
            var reading = sensor.GetCurrentReadingAsync().AsTask().GetAwaiter().GetResult();
            if (reading != null) source._latest = reading.AngleInDegrees;
            return source;
        }
        catch (Exception ex)
        {
            Log.Info("hinge sensor unavailable: " + ex.Message);
            return null;
        }
    }

    public AngleTier Tier => AngleTier.HingeSensor;
    public string Description => "hinge angle sensor";
    public bool Finished => false;

    public double? Read() => _latest;

    public void Dispose()
    {
    }
}
