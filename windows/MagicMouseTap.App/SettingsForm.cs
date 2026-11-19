using MagicMouseTap.Core;

namespace MagicMouseTap.App;

public sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly Label _status = new() { AutoSize = true };
    private readonly TrackBar _sensitivity = Slider(0, 100);
    private readonly TrackBar _tapDuration = Slider(150, 500);
    private readonly TrackBar _movement = Slider(20, 100);
    private readonly TrackBar _doubleTap = Slider(250, 850);
    private readonly TrackBar _zoom = Slider(15, 100);
    private readonly TrackBar _drag = Slider(10, 100);
    private readonly TrackBar _scrollStop = Slider(150, 700);
    private readonly CheckBox _startup = new() { Text = "Start with Windows", AutoSize = true };

    public SettingsForm(AppSettings settings)
    {
        _settings = settings;
        Text = "Magic Mouse Tap - Gesture Sensitivity";
        Width = 560;
        Height = 690;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScroll = true;

        _sensitivity.Value = (int)Math.Round(settings.Gestures.TapSensitivity * 100);
        _tapDuration.Value = (int)settings.Gestures.TapDurationMs;
        _movement.Value = (int)Math.Round(settings.Gestures.SurfaceMovementTolerance * 1000);
        _doubleTap.Value = (int)settings.Gestures.DoubleTapIntervalMs;
        _zoom.Value = (int)Math.Round(settings.Gestures.ZoomSwipeDistance * 1000);
        _drag.Value = (int)Math.Round(settings.Gestures.DragStartDistance * 1000);
        _scrollStop.Value = (int)settings.Gestures.ScrollStopWindowMs;
        _startup.Checked = settings.StartWithWindows;

        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(18),
            ColumnCount = 1,
            AutoScroll = true
        };
        panel.Controls.Add(new Label
        {
            Text = "Magic Mouse Tap",
            Font = new Font("Segoe UI", 18, FontStyle.Bold),
            AutoSize = true
        });
        panel.Controls.Add(_status);
        AddSetting(panel, "Tap sensitivity", _sensitivity, "Lower values reject more accidental touches.");
        AddSetting(panel, "Maximum tap duration (ms)", _tapDuration, "How long one finger may remain down and still count as a tap.");
        AddSetting(panel, "Surface movement tolerance", _movement, "Maximum movement before a touch becomes a gesture.");
        AddSetting(panel, "Double-tap interval (ms)", _doubleTap, "Maximum time between the two taps.");
        AddSetting(panel, "Zoom swipe distance", _zoom, "Second-tap swipe needed before zoom starts.");
        AddSetting(panel, "Drag start distance", _drag, "Second-tap movement needed to hold the left button.");
        AddSetting(panel, "Scroll-stop protection (ms)", _scrollStop, "A tap shortly after scrolling stops movement but does not click.");
        panel.Controls.Add(_startup);

        var buttons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        var save = new Button { Text = "Save", Width = 110, Height = 36 };
        save.Click += (_, _) => Save();
        var reset = new Button { Text = "Reset defaults", Width = 120, Height = 36 };
        reset.Click += (_, _) => ResetDefaults();
        buttons.Controls.Add(save);
        buttons.Controls.Add(reset);
        panel.Controls.Add(buttons);
        Controls.Add(panel);
    }

    public event Action<AppSettings>? SettingsSaved;

    public void SetStatus(string status)
    {
        if (InvokeRequired) { BeginInvoke(new Action(() => SetStatus(status))); return; }
        _status.Text = $"Status: {status}";
    }

    private void Save()
    {
        _settings.Gestures.TapSensitivity = _sensitivity.Value / 100.0;
        _settings.Gestures.TapDurationMs = _tapDuration.Value;
        _settings.Gestures.SurfaceMovementTolerance = _movement.Value / 1000.0;
        _settings.Gestures.DoubleTapIntervalMs = _doubleTap.Value;
        _settings.Gestures.ZoomSwipeDistance = _zoom.Value / 1000.0;
        _settings.Gestures.DragStartDistance = _drag.Value / 1000.0;
        _settings.Gestures.ScrollStopWindowMs = _scrollStop.Value;
        _settings.StartWithWindows = _startup.Checked;
        _settings.Save();
        SettingsSaved?.Invoke(_settings);
        Close();
    }

    private void ResetDefaults()
    {
        var defaults = new GestureSettings();
        _sensitivity.Value = (int)(defaults.TapSensitivity * 100);
        _tapDuration.Value = (int)defaults.TapDurationMs;
        _movement.Value = (int)(defaults.SurfaceMovementTolerance * 1000);
        _doubleTap.Value = (int)defaults.DoubleTapIntervalMs;
        _zoom.Value = (int)(defaults.ZoomSwipeDistance * 1000);
        _drag.Value = (int)(defaults.DragStartDistance * 1000);
        _scrollStop.Value = (int)defaults.ScrollStopWindowMs;
    }

    private static TrackBar Slider(int min, int max) => new()
    {
        Minimum = min,
        Maximum = max,
        Width = 480,
        TickStyle = TickStyle.None
    };

    private static void AddSetting(TableLayoutPanel panel, string title, Control control, string help)
    {
        panel.Controls.Add(new Label { Text = title, AutoSize = true, Font = new Font("Segoe UI", 10, FontStyle.Bold) });
        panel.Controls.Add(control);
        panel.Controls.Add(new Label { Text = help, AutoSize = true, ForeColor = Color.DimGray, MaximumSize = new Size(480, 0) });
    }
}
