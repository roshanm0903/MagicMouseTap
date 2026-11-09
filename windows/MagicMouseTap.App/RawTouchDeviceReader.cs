using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using MagicMouseTap.Core;

namespace MagicMouseTap.App;

public sealed class RawTouchDeviceReader : IDisposable
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint ShareRead = 0x00000001;
    private const uint ShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint Normal = 0x80;

    private static readonly string[] KnownPaths =
    [
        @"\\.\MagicMouseRawPDO",
        @"\\.\MagicMouse"
    ];

    private readonly MagicMouseReportParser _parser = new();
    private SafeFileHandle? _handle;
    private CancellationTokenSource? _cancellation;
    private Task? _readTask;

    public event Action<TouchFrame>? FrameReceived;
    public event Action<string>? StatusChanged;
    public event Action? Disconnected;

    public bool Open()
    {
        DisposeHandle();
        foreach (var path in KnownPaths)
        {
            var handle = CreateFile(path, GenericRead | GenericWrite, ShareRead | ShareWrite,
                IntPtr.Zero, OpenExisting, Normal, IntPtr.Zero);
            if (handle.IsInvalid)
            {
                handle.Dispose();
                handle = CreateFile(path, GenericRead, ShareRead | ShareWrite,
                    IntPtr.Zero, OpenExisting, Normal, IntPtr.Zero);
            }

            if (handle.IsInvalid)
            {
                handle.Dispose();
                continue;
            }

            _handle = handle;
            StatusChanged?.Invoke($"Connected through {path}");
            return true;
        }

        StatusChanged?.Invoke("Raw touch interface not found");
        return false;
    }

    public void Start()
    {
        if (_handle is null || _handle.IsInvalid) throw new InvalidOperationException("Device is not open.");
        _cancellation = new CancellationTokenSource();
        _readTask = Task.Run(() => ReadLoop(_cancellation.Token));
    }

    private void ReadLoop(CancellationToken cancellationToken)
    {
        var buffer = new byte[512];
        while (!cancellationToken.IsCancellationRequested && _handle is { IsInvalid: false })
        {
            if (!ReadFile(_handle, buffer, (uint)buffer.Length, out var read, IntPtr.Zero) || read == 0)
            {
                var error = Marshal.GetLastWin32Error();
                if (error is 6 or 995 or 1167) break;
                Thread.Sleep(20);
                continue;
            }

            if (_parser.TryParse(buffer.AsSpan(0, checked((int)read)), DateTimeOffset.UtcNow, out var frame))
            {
                FrameReceived?.Invoke(frame);
            }
        }

        if (!cancellationToken.IsCancellationRequested) Disconnected?.Invoke();
    }

    public void Dispose()
    {
        _cancellation?.Cancel();
        DisposeHandle();
        try { _readTask?.Wait(250); } catch { }
        _cancellation?.Dispose();
    }

    private void DisposeHandle()
    {
        _handle?.Dispose();
        _handle = null;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadFile(
        SafeFileHandle file, byte[] buffer, uint bytesToRead, out uint bytesRead, IntPtr overlapped);
}
