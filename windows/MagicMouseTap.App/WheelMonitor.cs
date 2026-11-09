using System.Diagnostics;
using System.Runtime.InteropServices;

namespace MagicMouseTap.App;

public sealed class WheelMonitor : IDisposable
{
    private const int LowLevelMouseHook = 14;
    private const int MouseWheel = 0x020A;
    private const int MouseHorizontalWheel = 0x020E;
    private readonly HookProc _callback;
    private IntPtr _hook;

    public WheelMonitor()
    {
        _callback = HookCallback;
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule!;
        _hook = SetWindowsHookEx(LowLevelMouseHook, _callback, GetModuleHandle(module.ModuleName), 0);
    }

    public event Action<DateTimeOffset>? WheelObserved;

    private IntPtr HookCallback(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && (message == (IntPtr)MouseWheel || message == (IntPtr)MouseHorizontalWheel))
            WheelObserved?.Invoke(DateTimeOffset.UtcNow);
        return CallNextHookEx(_hook, code, message, data);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc callback, IntPtr module, uint threadId);
    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
