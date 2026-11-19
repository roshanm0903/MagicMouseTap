namespace MagicMouseTap.Core;

public sealed class GestureSettings
{
    public double TapSensitivity { get; set; } = 0.35;
    public double TapDurationMs { get; set; } = 300;
    public double SurfaceMovementTolerance { get; set; } = 0.04;
    public double DoubleTapIntervalMs { get; set; } = 550;
    public double ZoomSwipeDistance { get; set; } = 0.035;
    public double DragStartDistance { get; set; } = 0.025;
    public double ScrollStopWindowMs { get; set; } = 350;

    public double SensitivityMultiplier => 0.55 + Math.Clamp(TapSensitivity, 0, 1) * 0.90;
    public double EffectiveTapDurationMs => TapDurationMs * SensitivityMultiplier;
    public double EffectiveMovementTolerance => SurfaceMovementTolerance * SensitivityMultiplier;
}
