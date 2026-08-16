using System.ComponentModel;
using System.Runtime.InteropServices;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Platform;

public sealed class WindowsTextInsertionService : ITextInsertionService
{
    private const uint CfUnicodeText = 13, GmemMoveable = 0x0002, InputKeyboard = 1, KeyUp = 0x0002;
    private const ushort VkControl = 0x11, VkV = 0x56;
    private IntPtr _targetWindow;

    internal static int NativeInputStructureSize => Marshal.SizeOf<Input>();

    public void CaptureTarget() => _targetWindow = GetForegroundWindow();

    public async Task<TextInsertionResult> InsertAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text)) return new(false, "没有可写入的文字。");
        if (!TryWriteClipboardText(text, out var clipboardError)) return new(false, clipboardError);
        if (_targetWindow == IntPtr.Zero || !IsWindow(_targetWindow))
            return new(false, "未找到原输入窗口，文字已复制，请按 Ctrl+V。");

        // The hotkey normally leaves the original editor in the foreground.
        // Avoid a redundant SetForegroundWindow call because Windows may reject
        // it even though the correct window is already active.
        if (GetForegroundWindow() != _targetWindow)
        {
            ShowWindowAsync(_targetWindow, ShowRestore);
            SetForegroundWindow(_targetWindow);
            await Task.Delay(70, cancellationToken).ConfigureAwait(false);
            if (GetForegroundWindow() != _targetWindow)
                return new(false, "无法恢复原输入窗口，文字已复制，请按 Ctrl+V。");
        }

        var inputs = new[] { Key(VkControl, 0), Key(VkV, 0), Key(VkV, KeyUp), Key(VkControl, KeyUp) };
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length)
            return new(false, "自动粘贴失败，文字已复制，请按 Ctrl+V。");

        ClearTarget();
        return new(true);
    }

    public void ClearTarget() => _targetWindow = IntPtr.Zero;

    private static Input Key(ushort key, uint flags) => new() { Type = InputKeyboard, Union = new InputUnion { Keyboard = new KeyboardInput { VirtualKey = key, Flags = flags } } };

    private static bool TryWriteClipboardText(string text, out string? error)
    {
        error = null;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            if (!OpenClipboard(IntPtr.Zero)) { Thread.Sleep(25); continue; }
            try
            {
                if (!EmptyClipboard()) break;
                var handle = GlobalAlloc(GmemMoveable, (nuint)((text.Length + 1) * sizeof(char)));
                if (handle == IntPtr.Zero) break;
                var pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero) { GlobalFree(handle); break; }
                try { Marshal.Copy(text.ToCharArray(), 0, pointer, text.Length); Marshal.WriteInt16(pointer, text.Length * 2, 0); }
                finally { GlobalUnlock(handle); }
                if (SetClipboardData(CfUnicodeText, handle) != IntPtr.Zero) return true;
                GlobalFree(handle);
                break;
            }
            finally { CloseClipboard(); }
        }
        error = new Win32Exception(Marshal.GetLastWin32Error(), "无法写入剪贴板。").Message;
        return false;
    }

    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputUnion Union; }
    // The INPUT union is 32 bytes on x64 because MOUSEINPUT is larger than
    // KEYBDINPUT. SendInput rejects a collapsed 24-byte union as invalid.
    [StructLayout(LayoutKind.Explicit, Size = 32)] private struct InputUnion { [FieldOffset(0)] public KeyboardInput Keyboard; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort VirtualKey; public ushort ScanCode; public uint Flags; public uint Time; public nuint ExtraInfo; }

    private const int ShowRestore = 9;
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll", SetLastError = true)][return: MarshalAs(UnmanagedType.Bool)] private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool CloseClipboard();
    [DllImport("user32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetClipboardData(uint format, IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalAlloc(uint flags, nuint bytes);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll")][return: MarshalAs(UnmanagedType.Bool)] private static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalFree(IntPtr memory);
}
