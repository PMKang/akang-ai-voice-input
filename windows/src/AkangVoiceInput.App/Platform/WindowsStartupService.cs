using Microsoft.Win32;
using System.IO;

namespace AkangVoiceInput.App.Platform;

internal sealed class WindowsStartupService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Noboard";

    public bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return key?.GetValue(ValueName) is string value && !string.IsNullOrWhiteSpace(value);
    }

    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (!enabled)
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
            return;
        }

        var executablePath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executablePath) ||
            !string.Equals(Path.GetFileName(executablePath), "Noboard.exe", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("开发运行模式无法设置开机启动，请在安装或解压正式版后启用。");
        }

        key.SetValue(ValueName, $"\"{executablePath}\"");
    }
}
