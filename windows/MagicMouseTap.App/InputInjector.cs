using System.Runtime.InteropServices;
using MagicMouseTap.Core;

namespace MagicMouseTap.App;

public static class InputInjector
{
    private const uint InputMouse = 0;
    private const uint InputKeyboard = 1;
    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;
    private const uint RightDown = 0x0008;
    private const uint RightUp = 0x0010;
    private const uint Wheel = 0x0800;
    private const uint KeyUp = 0x0002;
    private const ushort Control = 0x11;

    public static void Execute(GestureAction action)
    {
        switch (action.Type)
        {
            case GestureActionType.LeftClick: Click(LeftDown, LeftUp, 1); break;
            case GestureActionType.DoubleClick: Click(LeftDown, LeftUp, 2); break;
            case GestureActionType.RightClick: Click(RightDown, RightUp, 1); break;
            case GestureActionType.LeftButtonDown: SendMouse(LeftDown); break;
            case GestureActionType.LeftButtonUp: SendMouse(LeftUp); break;
            case GestureActionType.ZoomIn: ControlWheel(120); break;
            case GestureActionType.ZoomOut: ControlWheel(-120); break;
        }
    }

    private static void Click(uint down, uint up, int count)
    {
        for (var i = 0; i < count; i++)
        {
            SendMouse(down);
            SendMouse(up);
        }
    }

    private static void ControlWheel(int amount)
    {
        SendKeyboard(Control, 0);
        SendMouse(Wheel, unchecked((uint)amount));
        SendKeyboard(Control, KeyUp);
    }

    private static void SendMouse(uint flags, uint data = 0)
    {
        var input = new INPUT
        {
            type = InputMouse,
            union = new InputUnion
            {
                mouse = new MOUSEINPUT { mouseData = data, dwFlags = flags }
            }
        };
        SendInput(1, [input], Marshal.SizeOf<INPUT>());
    }

    private static void SendKeyboard(ushort key, uint flags)
    {
        var input = new INPUT
        {
            type = InputKeyboard,
            union = new InputUnion
            {
                keyboard = new KEYBDINPUT { virtualKey = key, flags = flags }
            }
        };
        SendInput(1, [input], Marshal.SizeOf<INPUT>());
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion union; }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mouse;
        [FieldOffset(0)] public KEYBDINPUT keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr extraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort virtualKey;
        public ushort scanCode;
        public uint flags;
        public uint time;
        public IntPtr extraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, INPUT[] inputs, int size);
}
