using System.Reflection;

namespace AkangVoiceInput.App;

public static class VersionInfo
{
    public static string ProductVersion { get; } = ResolveProductVersion();

    public static string SidebarLabel => $"v{ProductVersion} · Windows";

    public static string AboutLabel => $"当前版本 v{ProductVersion} · Windows";

    private static string ResolveProductVersion()
    {
        var informationalVersion = Assembly.GetEntryAssembly()
            ?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return informationalVersion.Split('+', 2)[0];
        }

        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version;
        return assemblyVersion is null
            ? "开发版"
            : $"{assemblyVersion.Major}.{assemblyVersion.Minor}.{assemblyVersion.Build}";
    }
}
