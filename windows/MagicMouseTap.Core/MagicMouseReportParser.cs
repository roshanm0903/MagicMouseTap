namespace MagicMouseTap.Core;

/// <summary>
/// Parses Apple Magic Mouse report 0x29 (first generation) and report 0x12
/// (Magic Mouse 2 / USB-C). The raw-touch driver may prepend transport bytes,
/// so the parser scans a short prefix for a valid report boundary.
/// </summary>
public sealed class MagicMouseReportParser
{
    private const byte Mouse1ReportId = 0x29;
    private const byte Mouse2ReportId = 0x12;
    private const int MinX = -1100;
    private const int MaxX = 1258;
    private const int MinY = -1589;
    private const int MaxY = 2047;

    public bool TryParse(ReadOnlySpan<byte> data, DateTimeOffset timestamp, out TouchFrame frame)
    {
        frame = null!;
        for (var offset = 0; offset < Math.Min(data.Length, 8); offset++)
        {
            var report = data[offset..];
            if (report.Length == 0) continue;

            var prefixLength = report[0] switch
            {
                Mouse1ReportId when report.Length >= 6 && (report.Length - 6) % 8 == 0 => 6,
                Mouse2ReportId when report.Length == 8 => 8,
                Mouse2ReportId when report.Length >= 14 && (report.Length - 14) % 8 == 0 => 14,
                _ => 0
            };

            if (prefixLength == 0) continue;

            var touchCount = report.Length == 8 ? 0 : (report.Length - prefixLength) / 8;
            if (touchCount > 15) continue;

            var touches = new List<TouchPoint>(touchCount);
            for (var index = 0; index < touchCount; index++)
            {
                var touch = report.Slice(prefixLength + index * 8, 8);
                var id = ((touch[6] << 2) | (touch[5] >> 6)) & 0x0f;
                var x = SignExtend12(touch[0] | (touch[1] << 8));
                var y = -SignExtend12((touch[1] >> 4) | (touch[2] << 4));
                var state = touch[7] & 0xf0;
                var isDown = state != 0;
                if (!isDown) continue;

                touches.Add(new TouchPoint(
                    id,
                    Normalize(x, MinX, MaxX),
                    Normalize(y, MinY, MaxY),
                    true));
            }

            frame = new TouchFrame(timestamp, touches, report[0], report.ToArray());
            return true;
        }

        return false;
    }

    private static int SignExtend12(int value)
    {
        value &= 0x0fff;
        return (value & 0x0800) != 0 ? value - 0x1000 : value;
    }

    private static double Normalize(int value, int min, int max) =>
        Math.Clamp((value - min) / (double)(max - min), 0, 1);
}
