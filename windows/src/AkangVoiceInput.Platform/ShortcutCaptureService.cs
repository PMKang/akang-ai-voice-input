using System.ComponentModel;
using System.Runtime.InteropServices;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Platform;

public sealed record ShortcutCaptureEvent(
    ShortcutModifiers Modifiers,
    int? VirtualKey,
    bool WindowsKeyDown);

public sealed class ShortcutCaptureService : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const uint VkLeftShift = 0xA0;
    private const uint VkRightShift = 0xA1;
    private const uint VkLeftControl = 0xA2;
    private const uint VkRightControl = 0xA3;
    private const uint VkLeftAlt = 0xA4;
    private const uint VkRightAlt = 0xA5;
    private const uint VkLeftWindows = 0x5B;
    private const uint VkRightWindows = 0x5C;

    private readonly LowLevelKeyboardProc _keyboardProc;
    private IntPtr _keyboardHook;
    private bool _controlDown;
    private bool _altDown;
    private bool _shiftDown;
    private bool _windowsDown;

    public ShortcutCaptureService()
    {
        _keyboardProc = HandleLowLevelKeyboard;
    }

    public event EventHandler<ShortcutCaptureEvent>? KeyChanged;

    public void Start()
    {
        if (_keyboardHook != IntPtr.Zero) return;

        _keyboardHook = SetWindowsHookEx(
            WhKeyboardLl,
            _keyboardProc,
            GetModuleHandle(null),
            0);
        if (_keyboardHook == IntPtr.Zero)
        {
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "无法启动快捷键录入监听。");
        }
    }

    public void Stop()
    {
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }

        _controlDown = false;
        _altDown = false;
        _shiftDown = false;
        _windowsDown = false;
    }

    public void Dispose() => Stop();

    private IntPtr HandleLowLevelKeyboard(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && _keyboardHook != IntPtr.Zero)
        {
            var keyboard = Marshal.PtrToStructure<LowLevelKeyboardInput>(data);
            var messageId = message.ToInt32();
            var isKeyDown = messageId is WmKeyDown or WmSysKeyDown;
            var isKeyUp = messageId is WmKeyUp or WmSysKeyUp;
            if (isKeyDown || isKeyUp)
            {
                var isModifier = UpdateModifierState(keyboard.VirtualKey, isKeyDown);
                if (isKeyDown && IsCurrentProcessForeground())
                {
                    KeyChanged?.Invoke(
                        this,
                        new ShortcutCaptureEvent(
                            CurrentModifiers(),
                            isModifier ? null : checked((int)keyboard.VirtualKey),
                            _windowsDown));
                }
            }
        }

        return CallNextHookEx(_keyboardHook, code, message, data);
    }

    private bool UpdateModifierState(uint virtualKey, bool isDown)
    {
        switch (virtualKey)
        {
            case VkLeftControl:
            case VkRightControl:
                _controlDown = isDown;
                return true;
            case VkLeftAlt:
            case VkRightAlt:
                _altDown = isDown;
                return true;
            case VkLeftShift:
            case VkRightShift:
                _shiftDown = isDown;
                return true;
            case VkLeftWindows:
            case VkRightWindows:
                _windowsDown = isDown;
                return true;
            default:
                return false;
        }
    }

    private ShortcutModifiers CurrentModifiers()
    {
        var modifiers = ShortcutModifiers.None;
        if (_controlDown) modifiers |= ShortcutModifiers.Control;
        if (_altDown) modifiers |= ShortcutModifiers.Alt;
        if (_shiftDown) modifiers |= ShortcutModifiers.Shift;
        return modifiers;
    }

    private static bool IsCurrentProcessForeground()
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) return false;
        GetWindowThreadProcessId(foreground, out var processId);
        return processId == Environment.ProcessId;
    }

    private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct LowLevelKeyboardInput
    {
        public readonly uint VirtualKey;
        public readonly uint ScanCode;
        public readonly uint Flags;
        public readonly uint Time;
        public readonly nuint ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int hookId,
        LowLevelKeyboardProc callback,
        IntPtr module,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int code,
        IntPtr message,
        IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(
        IntPtr window,
        out uint processId);
}
