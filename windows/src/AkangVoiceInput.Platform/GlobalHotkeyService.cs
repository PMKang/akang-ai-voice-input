using System.ComponentModel;
using System.Runtime.InteropServices;

namespace AkangVoiceInput.Platform;

public sealed class GlobalHotkeyService : IDisposable
{
    public const int MessageId = 0x0312;
    private const int HotkeyId = 0x4E42;
    private const uint ModAlt = 0x0001, ModControl = 0x0002, ModShift = 0x0004, ModNoRepeat = 0x4000;
    private IntPtr _windowHandle;
    private bool _registered;
    public event EventHandler? Triggered;

    public void Register(IntPtr windowHandle, string shortcut = "Ctrl+Alt+Space")
    {
        if (windowHandle == IntPtr.Zero) throw new ArgumentException("窗口句柄无效。", nameof(windowHandle));
        var (modifiers, key) = ParseShortcut(shortcut);
        Unregister();
        if (!RegisterHotKey(windowHandle, HotkeyId, modifiers | ModNoRepeat, key))
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"无法注册 {shortcut}，可能已被其他应用占用。");
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

    private static (uint Modifiers, uint Key) ParseShortcut(string shortcut)
    {
        var parts = shortcut.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        uint modifiers = 0;
        uint key = 0;
        foreach (var part in parts)
        {
            switch (part.ToUpperInvariant())
            {
                case "CTRL":
                case "CONTROL": modifiers |= ModControl; break;
                case "ALT": modifiers |= ModAlt; break;
                case "SHIFT": modifiers |= ModShift; break;
                case "SPACE": key = 0x20; break;
                case "V": key = 0x56; break;
                case "B": key = 0x42; break;
                default: throw new ArgumentException($"不支持的快捷键部分：{part}", nameof(shortcut));
            }
        }
        if (modifiers == 0 || key == 0)
            throw new ArgumentException("快捷键必须包含修饰键和主键。", nameof(shortcut));
        return (modifiers, key);
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr window, int id);
}
