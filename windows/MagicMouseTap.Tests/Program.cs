using MagicMouseTap.Core;

var tests = new (string Name, Action Run)[]
{
    ("parses Magic Mouse 2 touch reports", ParserTest),
    ("delays and emits a single click", SingleClickTest),
    ("turns two taps into one double click", DoubleClickTest),
    ("maps a two-finger tap to right click", RightClickTest),
    ("suppresses clicks while stopping scroll", ScrollSuppressionTest),
    ("supports double-tap drag", DragTest),
    ("keeps zoom from becoming selection", ZoomTest)
};

var failed = 0;
foreach (var test in tests)
{
    try
    {
        test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception error)
    {
        failed++;
        Console.Error.WriteLine($"FAIL {test.Name}: {error.Message}");
    }
}

return failed == 0 ? 0 : 1;

static void ParserTest()
{
    var report = new byte[22];
    report[0] = 0x12;
    report[14 + 7] = 0x40;
    var parser = new MagicMouseReportParser();
    True(parser.TryParse(report, DateTimeOffset.UnixEpoch, out var frame), "report rejected");
    Equal(1, frame.Touches.Count, "touch count");
    Equal(0, frame.Touches[0].Id, "touch id");
}

static void SingleClickTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    engine.Process(Frame(t, Touch(0, .5, .5)));
    engine.Process(Frame(t.AddMilliseconds(100)));
    Equal(0, actions.Count, "single click fired before double-tap window");
    engine.Tick(t.AddMilliseconds(700));
    Sequence(actions, GestureActionType.LeftClick);
}

static void DoubleClickTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    Tap(engine, t, .5, .5);
    Tap(engine, t.AddMilliseconds(250), .5, .5);
    Sequence(actions, GestureActionType.DoubleClick);
}

static void RightClickTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    engine.Process(Frame(t, Touch(0, .4, .5), Touch(1, .6, .5)));
    engine.Process(Frame(t.AddMilliseconds(100)));
    Sequence(actions, GestureActionType.RightClick);
}

static void ScrollSuppressionTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    engine.NoteScroll(t);
    Tap(engine, t.AddMilliseconds(50), .5, .5);
    engine.Tick(t.AddSeconds(1));
    Equal(0, actions.Count, "scroll-stop tap clicked");
}

static void DragTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    Tap(engine, t, .5, .5);
    var second = t.AddMilliseconds(250);
    engine.Process(Frame(second, Touch(0, .5, .5)));
    engine.Process(Frame(second.AddMilliseconds(100), Touch(0, .53, .5)));
    engine.Process(Frame(second.AddMilliseconds(150)));
    Sequence(actions, GestureActionType.LeftButtonDown, GestureActionType.LeftButtonUp);
}

static void ZoomTest()
{
    var (engine, actions) = Harness();
    var t = DateTimeOffset.UnixEpoch;
    Tap(engine, t, .5, .5);
    var second = t.AddMilliseconds(250);
    engine.Process(Frame(second, Touch(0, .5, .5)));
    engine.Process(Frame(second.AddMilliseconds(100), Touch(0, .5, .55)));
    engine.Process(Frame(second.AddMilliseconds(150)));
    Sequence(actions, GestureActionType.ZoomOut);
}

static (GestureEngine Engine, List<GestureActionType> Actions) Harness()
{
    var actions = new List<GestureActionType>();
    var engine = new GestureEngine(new GestureSettings());
    engine.ActionRequested += action => actions.Add(action.Type);
    return (engine, actions);
}

static void Tap(GestureEngine engine, DateTimeOffset start, double x, double y)
{
    engine.Process(Frame(start, Touch(0, x, y)));
    engine.Process(Frame(start.AddMilliseconds(100)));
}

static TouchFrame Frame(DateTimeOffset time, params TouchPoint[] touches) => new(time, touches, 0x12, []);
static TouchPoint Touch(int id, double x, double y) => new(id, x, y, true);

static void True(bool value, string message)
{
    if (!value) throw new InvalidOperationException(message);
}

static void Equal<T>(T expected, T actual, string message) where T : notnull
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
        throw new InvalidOperationException($"{message}: expected {expected}, got {actual}");
}

static void Sequence(IReadOnlyList<GestureActionType> actual, params GestureActionType[] expected)
{
    if (!actual.SequenceEqual(expected))
        throw new InvalidOperationException($"expected [{string.Join(", ", expected)}], got [{string.Join(", ", actual)}]");
}
