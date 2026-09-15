namespace Hingewave.App.Angle;

/// <summary>Picks the best available angle source, in the order of docs/design.md section 3.4.</summary>
public static class AngleSourceSelector
{
    public static IAngleSource Best()
    {
        if (HingeSensorSource.TryCreate() is { } hinge)
        {
            Log.Info("angle source: hinge angle sensor");
            return hinge;
        }
        if (AccelerometerSource.TryCreate() is { } accel)
        {
            Log.Info("angle source: " + accel.Description);
            return accel;
        }
        Log.Info("angle source: lid switch only");
        return new LidSwitchSource();
    }
}
