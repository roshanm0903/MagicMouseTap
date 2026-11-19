using System.Drawing;
using MagicMouseTap.Core;

namespace MagicMouseTap.App;

public sealed class TrayApplication : IDisposable
{
    private readonly SynchronizationContext _ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
    private readonly NotifyIcon _icon;
    private readonly ToolStripMenuItem _enabledItem;
    private readonly ToolStripMenuItem _statusItem;
    private readonly System.Windows.Forms.Timer _gestureTimer;
    private readonly System.Windows.Forms.Timer _reconnectTimer;
    private readonly WheelMonitor _wheelMonitor;
    private AppSettings _settings;
    private GestureEngine _engine;
    private RawTouchDeviceReader? _reader;
    private SettingsForm? _settingsForm;
    private bool _connecting;

    public TrayApplication()
    {
        _settings = AppSettings.Load();
        _engine = CreateEngine(_settings.Gestures);

        var menu = new ContextMenuStrip();
        _enabledItem = new ToolStripMenuItem("Tap to Click: Enabled", null, (_, _) => ToggleEnabled())
        {
            Checked = _settings.Enabled
        };
        _statusItem = new ToolStripMenuItem("Status: Starting…") { Enabled = false };
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Gesture Sensitivity…", null, (_, _) => ShowSettings());
        menu.Items.Add("Reconnect", null, (_, _) => Reconnect());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Application.Exit());

        var bitmap = new Bitmap(16, 16);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.Transparent);
            graphics.FillEllipse(Brushes.White, 2, 1, 12, 14);
            graphics.DrawLine(Pens.DodgerBlue, 8, 2, 8, 8);
        }

        _icon = new NotifyIcon
        {
            Icon = Icon.FromHandle(bitmap.GetHicon()),
            Text = "Magic Mouse Tap",
            ContextMenuStrip = menu,
            Visible = true
        };
        _icon.DoubleClick += (_, _) => ShowSettings();

        _wheelMonitor = new WheelMonitor();
        _wheelMonitor.WheelObserved += time => _ui.Post(_ => _engine.NoteScroll(time), null);

        _gestureTimer = new System.Windows.Forms.Timer { Interval = 20 };
        _gestureTimer.Tick += (_, _) => _engine.Tick(DateTimeOffset.UtcNow);
        _gestureTimer.Start();

        _reconnectTimer = new System.Windows.Forms.Timer { Interval = 3000 };
        _reconnectTimer.Tick += (_, _) => Connect();
        _reconnectTimer.Start();
        Connect();
    }

    private GestureEngine CreateEngine(GestureSettings settings)
    {
        var engine = new GestureEngine(settings);
        engine.ActionRequested += action =>
        {
            if (_settings.Enabled) InputInjector.Execute(action);
        };
        return engine;
    }

    private void Connect()
    {
        if (_connecting || _reader is not null) return;
        _connecting = true;
        SetStatus("Connecting…");

        Task.Run(() =>
        {
            var reader = new RawTouchDeviceReader();
            reader.StatusChanged += SetStatus;
            reader.FrameReceived += frame =>
            {
                _ui.Post(_ =>
                {
                    if (_settings.Enabled) _engine.Process(frame);
                }, null);
            };
            reader.Disconnected += () => _ui.Post(_ =>
            {
                SetStatus("Disconnected; reconnecting…");
                _reader?.Dispose();
                _reader = null;
            }, null);

            var opened = reader.Open();
            _ui.Post(_ =>
            {
                _connecting = false;
                if (!opened)
                {
                    reader.Dispose();
                    return;
                }

                _reader = reader;
                reader.Start();
                SetStatus("Connected; gestures active");
            }, null);
        });
    }

    private void Reconnect()
    {
        _reader?.Dispose();
        _reader = null;
        _engine.CancelActiveGesture();
        Connect();
    }

    private void ToggleEnabled()
    {
        _settings.Enabled = !_settings.Enabled;
        _enabledItem.Checked = _settings.Enabled;
        _enabledItem.Text = _settings.Enabled ? "Tap to Click: Enabled" : "Tap to Click: Disabled";
        if (!_settings.Enabled) _engine.CancelActiveGesture();
        _settings.Save();
    }

    private void ShowSettings()
    {
        if (_settingsForm is { IsDisposed: false })
        {
            _settingsForm.Activate();
            return;
        }

        _settingsForm = new SettingsForm(_settings);
        _settingsForm.SettingsSaved += settings =>
        {
            _settings = settings;
            _engine.UpdateSettings(settings.Gestures);
            ApplyStartup(settings.StartWithWindows);
        };
        _settingsForm.Show();
    }

    private void SetStatus(string status)
    {
        _ui.Post(_ =>
        {
            _statusItem.Text = $"Status: {status}";
            _icon.Text = status.Length <= 63 ? $"Magic Mouse Tap - {status}" : "Magic Mouse Tap";
            _settingsForm?.SetStatus(status);
        }, null);
    }

    private static void ApplyStartup(bool enabled)
    {
        using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Run", writable: true);
        if (enabled)
            key?.SetValue("MagicMouseTap", $"\"{Environment.ProcessPath}\"");
        else
            key?.DeleteValue("MagicMouseTap", throwOnMissingValue: false);
    }

    public void Dispose()
    {
        _gestureTimer.Dispose();
        _reconnectTimer.Dispose();
        _wheelMonitor.Dispose();
        _reader?.Dispose();
        _engine.CancelActiveGesture();
        _icon.Visible = false;
        _icon.Dispose();
    }
}
