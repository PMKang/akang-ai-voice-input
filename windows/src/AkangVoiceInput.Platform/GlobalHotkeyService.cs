using System.ComponentModel;
using System.Runtime.InteropServices;

namespace AkangVoiceInput.Platform;

public sealed class GlobalHotkeyService : IDisposable
{
    public const int MessageId = 0x0312;
    private const int HotkeyId = 0x4E42;
    private const uint ModAlt = 0x0001, ModControl = 0x0002, ModNoRepeat = 0x4000, VirtualKeySpace = 0x20;
    private IntPtr _windowHandle;
    private bool _registered;
    public event EventHandler? Triggered;

    public void Register(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero) throw new ArgumentException("窗口句柄无效。", nameof(windowHandle));
        Unregister();
        if (!RegisterHotKey(windowHandle, HotkeyId, ModControl | ModAlt | ModNoRepeat, VirtualKeySpace))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法注册 Ctrl+Alt+Space，可能已被其他应用占用。");
        _windowHandle = windowHandle;
        _registered = true;
    }

    public bool HandleMessage(int message, IntPtr wParam)
    {
        if (!_registered || message != MessageId || wParam.ToInt32() != HotkeyId) return false;
        Triggered?.Invoke(this, EventArgs.Empty);
        return true;
    }

    public void Unregister()
    {
        if (_registered) UnregisterHotKey(_windowHandle, HotkeyId);
        _registered = false;
        _windowHandle = IntPtr.Zero;
    }
    public void Dispose() => Unregister();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr window, int id);
}
