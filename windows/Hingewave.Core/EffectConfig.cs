using System.Text.Json;
using System.Text.Json.Serialization;

namespace Hingewave.Core;

/// <summary>Tuned effect parameters. Mirrors core/effect.json; a test proves the two are identical.</summary>
public sealed record EffectConfig(
    [property: JsonPropertyName("eyeDistance")] double EyeDistance,
    [property: JsonPropertyName("maxBlur")] double MaxBlur,
    [property: JsonPropertyName("darkenGain")] double DarkenGain,
    [property: JsonPropertyName("springHz")] double SpringHz,
    [property: JsonPropertyName("stillSeconds")] double StillSeconds,
    [property: JsonPropertyName("clearSeconds")] double ClearSeconds,
    [property: JsonPropertyName("laptop")] LaptopConfig Laptop,
    [property: JsonPropertyName("phone")] PhoneConfig Phone)
{
    /// <summary>Values copied from core/effect.json. Change them there first, then here.</summary>
    public static readonly EffectConfig Defaults = new(
        EyeDistance: 2.0,
        MaxBlur: 0.036,
        DarkenGain: 2.0,
        SpringHz: 6.0,
        StillSeconds: 2.0,
        ClearSeconds: 0.6,
        Laptop: new LaptopConfig(StartAngle: 90.0, EndAngle: 8.0, ArmVelocity: 15.0),
        Phone: new PhoneConfig(
            DeadZone: 6.0,
            Inner: new InnerConfig(ClearStart: 100.0, ClearEnd: 174.0),
            Cover: new CoverConfig(FrostStart: 6.0, FrostEnd: 26.0)));

    public static EffectConfig Load(string path)
    {
        var json = File.ReadAllText(path);
        return JsonSerializer.Deserialize<EffectConfig>(json) ?? throw new InvalidDataException(path);
    }
}

public sealed record LaptopConfig(
    [property: JsonPropertyName("startAngle")] double StartAngle,
    [property: JsonPropertyName("endAngle")] double EndAngle,
    [property: JsonPropertyName("armVelocity")] double ArmVelocity);

public sealed record InnerConfig(
    [property: JsonPropertyName("clearStart")] double ClearStart,
    [property: JsonPropertyName("clearEnd")] double ClearEnd);

public sealed record CoverConfig(
    [property: JsonPropertyName("frostStart")] double FrostStart,
    [property: JsonPropertyName("frostEnd")] double FrostEnd);

public sealed record PhoneConfig(
    [property: JsonPropertyName("deadZone")] double DeadZone,
    [property: JsonPropertyName("inner")] InnerConfig Inner,
    [property: JsonPropertyName("cover")] CoverConfig Cover);
