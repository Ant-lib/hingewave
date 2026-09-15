namespace Hingewave.Core;

/// <summary>
/// Critically damped spring with an exact closed-form step.
/// Same formula as core/reference/hingewave_ref/spring.py.
/// </summary>
public sealed class Spring
{
    public double Omega { get; }
    public double X { get; private set; }
    public double V { get; private set; }

    public Spring(double hz)
    {
        Omega = 2.0 * Math.PI * hz;
    }

    public void Reset(double value)
    {
        X = value;
        V = 0.0;
    }

    /// <summary>Advances toward <paramref name="target"/> by <paramref name="dt"/> seconds.</summary>
    public (double X, double V) Step(double target, double dt)
    {
        if (dt <= 0.0) return (X, V);
        var w = Omega;
        var d = X - target;
        var e = Math.Exp(-w * dt);
        var xNew = target + (d + (V + w * d) * dt) * e;
        var vNew = (V - w * (V + w * d) * dt) * e;
        X = xNew;
        V = vNew;
        return (X, V);
    }
}
