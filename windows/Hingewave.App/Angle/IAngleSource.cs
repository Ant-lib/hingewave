namespace Hingewave.App.Angle;

public enum AngleTier
{
    /// <summary>A real hinge angle sensor exposed through Windows.Devices.Sensors.HingeAngleSensor.</summary>
    HingeSensor,

    /// <summary>The lid's accelerometer, with the base assumed level.</summary>
    Accelerometer,

    /// <summary>Only the lid open or closed switch; the effect plays on a fixed timeline.</summary>
    LidSwitch,

    /// <summary>A scripted sweep for previews and tests.</summary>
    Scripted,
}

/// <summary>Anything that yields a lid angle in degrees, 0 closed.</summary>
public interface IAngleSource : IDisposable
{
    AngleTier Tier { get; }
    string Description { get; }

    /// <summary>Current angle, or null when no reading is available yet.</summary>
    double? Read();

    /// <summary>True once a scripted source has played out. Real sensors never finish.</summary>
    bool Finished { get; }
}
