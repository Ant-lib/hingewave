using System.Text.Json;
using Windows.Devices.Sensors;

namespace Hingewave.App.Angle;

/// <summary>
/// Tier 2: the lid's accelerometer. Convertibles expose it for auto-rotate. With the
/// base assumed level, the lid angle is the pitch of gravity in the lid's frame:
/// atan2(-y, z) in the sensor's fixed coordinate system. Sensor axes differ between
/// laptops, so a two-position calibration (lid at about 90 degrees, then fully open)
/// fixes the sign and offset and is stored in %LOCALAPPDATA%\Hingewave\calibration.json.
/// </summary>
public sealed class AccelerometerSource : IAngleSource
{
    public sealed record Calibration(double Sign, double Offset);

    private static readonly string CalibrationPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Hingewave", "calibration.json");

    private readonly Accelerometer _sensor;
    private double? _raw;
    private Calibration _calibration;

    private AccelerometerSource(Accelerometer sensor)
    {
        _sensor = sensor;
        _sensor.ReportInterval = Math.Max(sensor.MinimumReportInterval, 20);
        _sensor.ReadingChanged += (_, e) =>
        {
            var r = e.Reading;
            _raw = Math.Atan2(-r.AccelerationY, r.AccelerationZ) * 180.0 / Math.PI;
        };
        _calibration = LoadCalibration() ?? new Calibration(1.0, 0.0);
    }

    public static AccelerometerSource? TryCreate()
    {
        try
        {
            var sensor = Accelerometer.GetDefault();
            if (sensor == null) return null;
            var source = new AccelerometerSource(sensor);
            var reading = sensor.GetCurrentReading();
            if (reading != null) source._raw = Math.Atan2(-reading.AccelerationY, reading.AccelerationZ) * 180.0 / Math.PI;
            return source;
        }
        catch (Exception ex)
        {
            Log.Info("accelerometer unavailable: " + ex.Message);
            return null;
        }
    }

    public AngleTier Tier => AngleTier.Accelerometer;
    public string Description => IsCalibrated ? "lid accelerometer (calibrated)" : "lid accelerometer (not calibrated)";
    public bool Finished => false;
    public bool IsCalibrated { get; private set; }

    /// <summary>Raw pitch in degrees before calibration, for the calibration dialog.</summary>
    public double? RawPitch => _raw;

    public double? Read()
    {
        if (_raw is not double raw) return null;
        var angle = raw * _calibration.Sign + _calibration.Offset;
        angle %= 360.0;
        if (angle < 0) angle += 360.0;
        return angle > 200.0 ? 0.0 : Math.Min(angle, 180.0);
    }

    /// <summary>Stores the mapping from two raw pitches: one at a lid angle of about 90 degrees, one fully open.</summary>
    public void Calibrate(double rawAtNinety, double rawFullyOpen, double fullyOpenDegrees = 130.0)
    {
        var delta = rawFullyOpen - rawAtNinety;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        var sign = delta >= 0 ? 1.0 : -1.0;
        var offset = 90.0 - sign * rawAtNinety;
        _calibration = new Calibration(sign, offset);
        IsCalibrated = true;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(CalibrationPath)!);
            File.WriteAllText(CalibrationPath, JsonSerializer.Serialize(_calibration));
        }
        catch (Exception ex)
        {
            Log.Info("could not save calibration: " + ex.Message);
        }
        Log.Info($"accelerometer calibrated sign={sign} offset={offset:F1} (open reference {fullyOpenDegrees} deg)");
    }

    private Calibration? LoadCalibration()
    {
        try
        {
            if (!File.Exists(CalibrationPath)) return null;
            var c = JsonSerializer.Deserialize<Calibration>(File.ReadAllText(CalibrationPath));
            if (c != null) IsCalibrated = true;
            return c;
        }
        catch
        {
            return null;
        }
    }

    public void Dispose()
    {
    }
}
