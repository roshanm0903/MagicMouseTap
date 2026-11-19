namespace MagicMouseTap.Core;

public readonly record struct TouchPoint(int Id, double X, double Y, bool IsDown);

public sealed record TouchFrame(
    DateTimeOffset Timestamp,
    IReadOnlyList<TouchPoint> Touches,
    byte ReportId,
    byte[] Raw);

public enum GestureActionType
{
    LeftClick,
    DoubleClick,
    RightClick,
    LeftButtonDown,
    LeftButtonUp,
    ZoomIn,
    ZoomOut
}

public readonly record struct GestureAction(GestureActionType Type);
