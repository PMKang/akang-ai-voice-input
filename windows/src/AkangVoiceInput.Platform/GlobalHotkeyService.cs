using System.ComponentModel;
using System.Runtime.InteropServices;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Platform;

public sealed class GlobalHotkeyService : IDisposable
{
    public const int MessageId = 0x0312;
    private const int HotkeyId = 0x4E42;
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const uint VkLeftMenu = 0xA4;
    private const uint VkRightMenu = 0xA5;
    private const uint LlkhfInjected = 0x10;
    private const uint KeyEventKeyUp = 0x0002;
    private const uint ModAlt = 0x0001, ModControl = 0x0002, ModShift = 0x0004, ModNoRepeat = 0x4000;
    private readonly LowLevelKeyboardProc _keyboardProc;
    private IntPtr _windowHandle;
    private IntPtr _keyboardHook;
    private uint _soloAltKey;
    private bool _soloAltPending;
    private bool _soloAltUsedAsModifier;
    private bool _registered;
    public event EventHandler? Triggered;

    public GlobalHotkeyService()
    {
        _keyboardProc = HandleLowLevelKeyboard;
    }

    public void Register(IntPtr windowHandle, ShortcutBinding shortcut)
    {
        if (windowHandle == IntPtr.Zero) throw new ArgumentException("窗口句柄无效。", nameof(windowHandle));
        ArgumentNullException.ThrowIfNull(shortcut);
        var validation = shortcut.Validate();
        if (!validation.IsValid) throw new ArgumentException(validation.Message, nameof(shortcut));

        Unregister();
        _windowHandle = windowHandle;
        _soloAltKey = shortcut.Kind == ShortcutKind.SoloAlt
            ? shortcut.Side switch
            {
                ShortcutSide.Left => VkLeftMenu,
                ShortcutSide.Right => VkRightMenu,
                _ => 0
            }
            : 0;
        if (_soloAltKey != 0)
        {
            _keyboardHook = SetWindowsHookEx(
                WhKeyboardLl,
                _keyboardProc,
                GetModuleHandle(null),
                0);
            if (_keyboardHook == IntPtr.Zero)
            {
                _windowHandle = IntPtr.Zero;
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    $"无法注册 {shortcut.DisplayText} 快捷键。");
            }
            _registered = true;
            return;
        }

        var modifiers = ToNativeModifiers(shortcut.Modifiers);
        var key = checked((uint)shortcut.VirtualKey);
        if (!RegisterHotKey(windowHandle, HotkeyId, modifiers | ModNoRepeat, key))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                $"无法使用 {shortcut.DisplayText}。它可能已被其他应用或 Windows 系统占用。");
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
        if (_keyboardHook != IntPtr.Zero)
        {
            if (_soloAltUsedAsModifier)
            {
                keybd_event((byte)_soloAltKey, 0, KeyEventKeyUp, UIntPtr.Zero);
            }
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }
        else if (_registered)
        {
            UnregisterHotKey(_windowHandle, HotkeyId);
        }
        _registered = false;
        _soloAltKey = 0;
        _soloAltPending = false;
        _soloAltUsedAsModifier = false;
        _windowHandle = IntPtr.Zero;
    }
    public void Dispose() => Unregister();

    private IntPtr HandleLowLevelKeyboard(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && _keyboardHook != IntPtr.Zero)
        {
            var keyboard = Marshal.PtrToStructure<LowLevelKeyboardInput>(data);
            if ((keyboard.Flags & LlkhfInjected) != 0)
            {
                return CallNextHookEx(_keyboardHook, code, message, data);
            }

            var messageId = message.ToInt32();
            var isKeyDown = messageId is WmKeyDown or WmSysKeyDown;
            var isKeyUp = messageId is WmKeyUp or WmSysKeyUp;

            if (_soloAltKey != 0)
            {
                if (keyboard.VirtualKey == _soloAltKey)
                {
                    if (isKeyDown)
                    {
                        _soloAltPending = true;
                        return new IntPtr(1);
                    }

                    if (isKeyUp)
                    {
                        if (_soloAltUsedAsModifier)
                        {
                            keybd_event((byte)_soloAltKey, 0, KeyEventKeyUp, UIntPtr.Zero);
                        }
                        else if (_soloAltPending)
                        {
                            Triggered?.Invoke(this, EventArgs.Empty);
                        }

                        _soloAltPending = false;
                        _soloAltUsedAsModifier = false;
                        return new IntPtr(1);
                    }
                }
                else if (isKeyDown && _soloAltPending && !_soloAltUsedAsModifier)
                {
                    _soloAltUsedAsModifier = true;
                    keybd_event((byte)_soloAltKey, 0, 0, UIntPtr.Zero);
                }
            }
        }

        return CallNextHookEx(_keyboardHook, code, message, data);
    }

    private static uint ToNativeModifiers(ShortcutModifiers modifiers)
    {
        var result = 0u;
        if (modifiers.HasFlag(ShortcutModifiers.Control)) result |= ModControl;
        if (modifiers.HasFlag(ShortcutModifiers.Alt)) result |= ModAlt;
        if (modifiers.HasFlag(ShortcutModifiers.Shift)) result |= ModShift;
        return result;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr window, int id);

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
    private static extern void keybd_event(
        byte virtualKey,
        byte scanCode,
        uint flags,
        UIntPtr extraInfo);
}
