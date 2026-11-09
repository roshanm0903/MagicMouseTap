namespace MagicMouseTap.Core;

public sealed class GestureEngine
{
    private GestureSettings _settings;
    private DateTimeOffset? _sequenceStart;
    private Dictionary<int, TouchPoint> _startTouches = [];
    private Dictionary<int, TouchPoint> _latestTouches = [];
    private int _maxTouches;
    private bool _moved;
    private bool _scrolled;
    private bool _dragging;
    private bool _zoomed;
    private DateTimeOffset? _lastTapAt;
    private TouchPoint? _lastTapPoint;
    private DateTimeOffset? _pendingSingleClickAt;
    private bool _secondTap;
    private DateTimeOffset _lastScrollAt = DateTimeOffset.MinValue;

    public GestureEngine(GestureSettings settings) => _settings = settings;

    public event Action<GestureAction>? ActionRequested;

    public void UpdateSettings(GestureSettings settings)
    {
        CancelActiveGesture();
        _settings = settings;
    }

    public void NoteScroll(DateTimeOffset timestamp)
    {
        _lastScrollAt = timestamp;
        _pendingSingleClickAt = null;
        if (_sequenceStart is not null) _scrolled = true;
    }

    public void Tick(DateTimeOffset timestamp)
    {
        if (_pendingSingleClickAt is null || timestamp < _pendingSingleClickAt) return;
        _pendingSingleClickAt = null;
        _lastTapAt = null;
        ActionRequested?.Invoke(new GestureAction(GestureActionType.LeftClick));
    }

    public void Process(TouchFrame frame)
    {
        var down = frame.Touches.Where(t => t.IsDown).ToArray();
        if (down.Length == 0)
        {
            FinishSequence(frame.Timestamp);
            return;
        }

        if (_sequenceStart is null)
        {
            BeginSequence(frame.Timestamp, down);
        }

        _maxTouches = Math.Max(_maxTouches, down.Length);
        _latestTouches = down.ToDictionary(t => t.Id);
        UpdateMovement();

        if (_secondTap && down.Length == 1 && !_scrolled)
        {
            var start = _startTouches.Values.First();
            var current = down[0];
            var dx = current.X - start.X;
            var dy = current.Y - start.Y;

            if (!_zoomed && Math.Abs(dy) >= _settings.ZoomSwipeDistance)
            {
                _zoomed = true;
                ActionRequested?.Invoke(new GestureAction(
                    dy > 0 ? GestureActionType.ZoomOut : GestureActionType.ZoomIn));
                return;
            }

            if (!_zoomed && !_dragging && Math.Sqrt(dx * dx + dy * dy) >= _settings.DragStartDistance)
            {
                _dragging = true;
                ActionRequested?.Invoke(new GestureAction(GestureActionType.LeftButtonDown));
            }
        }
    }

    public void CancelActiveGesture()
    {
        if (_dragging) ActionRequested?.Invoke(new GestureAction(GestureActionType.LeftButtonUp));
        ResetSequence();
        _lastTapAt = null;
        _lastTapPoint = null;
        _pendingSingleClickAt = null;
    }

    private void BeginSequence(DateTimeOffset timestamp, IReadOnlyList<TouchPoint> touches)
    {
        _sequenceStart = timestamp;
        _startTouches = touches.ToDictionary(t => t.Id);
        _latestTouches = touches.ToDictionary(t => t.Id);
        _maxTouches = touches.Count;
        _moved = false;
        _scrolled = timestamp - _lastScrollAt <= TimeSpan.FromMilliseconds(_settings.ScrollStopWindowMs);
        _dragging = false;
        _zoomed = false;

        _secondTap = touches.Count == 1 &&
            _lastTapAt is not null &&
            timestamp - _lastTapAt <= TimeSpan.FromMilliseconds(_settings.DoubleTapIntervalMs) &&
            _lastTapPoint is not null &&
            Distance(touches[0], _lastTapPoint.Value) <= _settings.EffectiveMovementTolerance * 2;
    }

    private void UpdateMovement()
    {
        foreach (var (id, current) in _latestTouches)
        {
            if (_startTouches.TryGetValue(id, out var start) &&
                Distance(start, current) > _settings.EffectiveMovementTolerance)
            {
                _moved = true;
            }
        }
    }

    private void FinishSequence(DateTimeOffset timestamp)
    {
        if (_sequenceStart is null) return;

        if (_dragging)
        {
            ActionRequested?.Invoke(new GestureAction(GestureActionType.LeftButtonUp));
            ResetSequence();
            _lastTapAt = null;
            return;
        }

        if (_zoomed || _scrolled)
        {
            ResetSequence();
            _lastTapAt = null;
            return;
        }

        var elapsed = (timestamp - _sequenceStart.Value).TotalMilliseconds;
        var isTap = elapsed <= _settings.EffectiveTapDurationMs && !_moved;
        var point = _latestTouches.Values.FirstOrDefault();

        if (isTap && _maxTouches == 2)
        {
            ActionRequested?.Invoke(new GestureAction(GestureActionType.RightClick));
            _lastTapAt = null;
        }
        else if (isTap && _maxTouches == 1 && _secondTap)
        {
            _pendingSingleClickAt = null;
            ActionRequested?.Invoke(new GestureAction(GestureActionType.DoubleClick));
            _lastTapAt = null;
        }
        else if (isTap && _maxTouches == 1)
        {
            _lastTapAt = timestamp;
            _lastTapPoint = point;
            _pendingSingleClickAt = timestamp.AddMilliseconds(_settings.DoubleTapIntervalMs);
        }
        else
        {
            _lastTapAt = null;
        }

        ResetSequence();
    }

    private void ResetSequence()
    {
        _sequenceStart = null;
        _startTouches = [];
        _latestTouches = [];
        _maxTouches = 0;
        _moved = false;
        _scrolled = false;
        _dragging = false;
        _zoomed = false;
        _secondTap = false;
    }

    private static double Distance(TouchPoint a, TouchPoint b)
    {
        var dx = a.X - b.X;
        var dy = a.Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }
}
