using System.IO;

namespace AkangVoiceInput.App;

internal static class AppDiagnostics
{
    private static readonly object Gate = new();

    public static string LogFilePath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Noboard",
        "diagnostics.log");

    public static void Write(string message, Exception? exception = null)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogFilePath)!);
                File.AppendAllText(
                    LogFilePath,
                    $"{DateTimeOffset.Now:O} {message}{(exception is null ? string.Empty : Environment.NewLine + exception)}{Environment.NewLine}");
            }
        }
        catch
        {
            // Diagnostics must never prevent voice input from starting.
        }
    }
}
