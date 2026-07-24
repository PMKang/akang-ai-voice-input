using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AkangVoiceInput.Platform;

public sealed record WindowsReleaseAsset(string Name, Uri DownloadUri, long Size);

public sealed record WindowsReleaseInfo(
    string Version,
    string Title,
    string Notes,
    Uri ReleaseUri,
    WindowsReleaseAsset Archive,
    WindowsReleaseAsset Checksum)
{
    public string DisplayVersion => Version.StartsWith("v", StringComparison.OrdinalIgnoreCase)
        ? Version
        : $"v{Version}";
}

public sealed record PreparedWindowsUpdate(
    string Version,
    string StagingDirectory,
    string ArchivePath,
    string Sha256)
{
    public string DisplayVersion => Version.StartsWith("v", StringComparison.OrdinalIgnoreCase)
        ? Version
        : $"v{Version}";
}

public sealed class WindowsUpdateService
{
    private const string LatestReleaseApi =
        "https://api.github.com/repos/PMKang/akang-ai-voice-input/releases/latest";
    private static readonly Regex ChecksumPattern =
        new(@"\b(?<hash>[a-fA-F0-9]{64})\b", RegexOptions.Compiled);

    private readonly HttpClient _httpClient;
    private readonly string _updatesRoot;

    public WindowsUpdateService(HttpClient? httpClient = null, string? updatesRoot = null)
    {
        _httpClient = httpClient ?? CreateHttpClient();
        _updatesRoot = updatesRoot ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Noboard",
            "Updates");
    }

    public async Task<WindowsReleaseInfo> FetchLatestReleaseAsync(
        CancellationToken cancellationToken = default)
    {
        using var response = await _httpClient.GetAsync(LatestReleaseApi, cancellationToken)
            .ConfigureAwait(false);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            throw new InvalidOperationException("尚未发布可下载的新版本。");
        response.EnsureSuccessStatusCode();

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        var payload = await JsonSerializer.DeserializeAsync<GitHubReleasePayload>(
            stream,
            cancellationToken: cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("更新服务返回的数据无法识别。");

        var archive = payload.Assets.FirstOrDefault(asset =>
            asset.Name.EndsWith("-windows-x64.zip", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("该版本未附带 Windows x64 安装包。");
        var checksum = payload.Assets.FirstOrDefault(asset =>
            asset.Name.Equals($"{archive.Name}.sha256", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Windows 更新包缺少 SHA256 校验文件。");

        return new WindowsReleaseInfo(
            payload.TagName,
            string.IsNullOrWhiteSpace(payload.Name) ? payload.TagName : payload.Name,
            payload.Body ?? string.Empty,
            payload.HtmlUrl,
            new WindowsReleaseAsset(archive.Name, archive.BrowserDownloadUrl, archive.Size),
            new WindowsReleaseAsset(checksum.Name, checksum.BrowserDownloadUrl, checksum.Size));
    }

    public static bool IsNewerVersion(string candidate, string current)
    {
        var candidateVersion = ParseVersion(candidate);
        var currentVersion = ParseVersion(current);
        return candidateVersion > currentVersion;
    }

    public async Task<PreparedWindowsUpdate> DownloadAndPrepareAsync(
        WindowsReleaseInfo release,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var versionDirectory = Path.Combine(_updatesRoot, SanitizeVersion(release.Version));
        var archivePath = Path.Combine(versionDirectory, release.Archive.Name);
        var stagingDirectory = Path.Combine(versionDirectory, "staging");
        Directory.CreateDirectory(versionDirectory);

        if (Directory.Exists(stagingDirectory))
            Directory.Delete(stagingDirectory, recursive: true);
        Directory.CreateDirectory(stagingDirectory);

        var expectedHash = await DownloadChecksumAsync(release.Checksum.DownloadUri, cancellationToken)
            .ConfigureAwait(false);
        await DownloadFileAsync(
            release.Archive.DownloadUri,
            archivePath,
            release.Archive.Size,
            progress,
            cancellationToken).ConfigureAwait(false);

        var actualHash = await ComputeSha256Async(archivePath, cancellationToken).ConfigureAwait(false);
        if (!actualHash.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(archivePath);
            throw new InvalidOperationException("更新包 SHA256 校验失败，已停止安装。");
        }

        ZipFile.ExtractToDirectory(archivePath, stagingDirectory, overwriteFiles: true);
        var stagedExecutable = Path.Combine(stagingDirectory, "Noboard.exe");
        if (!File.Exists(stagedExecutable))
            throw new InvalidOperationException("更新包内容不完整，未找到 Noboard.exe。");

        return new PreparedWindowsUpdate(release.Version, stagingDirectory, archivePath, actualHash);
    }

    public string ScheduleInstallAndRestart(
        PreparedWindowsUpdate package,
        int currentProcessId,
        string targetDirectory,
        string currentExecutablePath)
    {
        var executableName = Path.GetFileName(currentExecutablePath);
        if (!executableName.Equals("Noboard.exe", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("开发运行模式不能自动安装；请使用发布版 Noboard.exe 验证更新。");
        if (!File.Exists(Path.Combine(package.StagingDirectory, "Noboard.exe")))
            throw new InvalidOperationException("已下载的更新包不完整，请重新下载。");

        EnsureDirectoryWritable(targetDirectory);
        var scriptPath = Path.Combine(
            Path.GetDirectoryName(package.ArchivePath)!,
            "install-windows-update.ps1");
        File.WriteAllText(scriptPath, InstallerScript, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        startInfo.ArgumentList.Add("-ProcessId");
        startInfo.ArgumentList.Add(currentProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture));
        startInfo.ArgumentList.Add("-SourceDirectory");
        startInfo.ArgumentList.Add(package.StagingDirectory);
        startInfo.ArgumentList.Add("-TargetDirectory");
        startInfo.ArgumentList.Add(targetDirectory);
        startInfo.ArgumentList.Add("-LaunchFile");
        startInfo.ArgumentList.Add("Noboard.exe");

        _ = Process.Start(startInfo)
            ?? throw new InvalidOperationException("无法启动 Windows 更新安装程序。");
        return scriptPath;
    }

    private async Task<string> DownloadChecksumAsync(Uri uri, CancellationToken cancellationToken)
    {
        var text = await _httpClient.GetStringAsync(uri, cancellationToken).ConfigureAwait(false);
        var match = ChecksumPattern.Match(text);
        return match.Success
            ? match.Groups["hash"].Value.ToLowerInvariant()
            : throw new InvalidOperationException("SHA256 校验文件格式无法识别。");
    }

    private async Task DownloadFileAsync(
        Uri uri,
        string destination,
        long expectedSize,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        var temporary = $"{destination}.download";
        if (File.Exists(temporary)) File.Delete(temporary);

        using var response = await _httpClient.GetAsync(
            uri,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength.GetValueOrDefault(expectedSize);
        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken)
            .ConfigureAwait(false);
        await using var output = new FileStream(
            temporary,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            bufferSize: 81920,
            useAsync: true);

        var buffer = new byte[81920];
        long received = 0;
        while (true)
        {
            var count = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (count == 0) break;
            await output.WriteAsync(buffer.AsMemory(0, count), cancellationToken).ConfigureAwait(false);
            received += count;
            if (total > 0) progress?.Report(Math.Clamp((double)received / total, 0, 1));
        }
        await output.FlushAsync(cancellationToken).ConfigureAwait(false);
        await output.DisposeAsync().ConfigureAwait(false);

        File.Move(temporary, destination, overwrite: true);
        progress?.Report(1);
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 81920,
            useAsync: true);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken).ConfigureAwait(false);
        return Convert.ToHexStringLower(hash);
    }

    private static Version ParseVersion(string value)
    {
        var cleaned = value.Trim().TrimStart('v', 'V');
        var release = cleaned.Split('-', 2)[0];
        return Version.TryParse(release, out var parsed)
            ? parsed
            : throw new InvalidOperationException($"无法识别版本号：{value}");
    }

    private static string SanitizeVersion(string version)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return string.Concat(version.Select(character => invalid.Contains(character) ? '-' : character));
    }

    private static void EnsureDirectoryWritable(string directory)
    {
        if (!Directory.Exists(directory))
            throw new DirectoryNotFoundException($"当前安装目录不存在：{directory}");
        var probe = Path.Combine(directory, $".noboard-update-write-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllText(probe, "update");
        }
        catch (Exception exception)
        {
            throw new InvalidOperationException(
                $"当前安装目录不可写，请将 Noboard 解压到个人文件夹后再更新：{directory}",
                exception);
        }
        finally
        {
            if (File.Exists(probe)) File.Delete(probe);
        }
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Noboard-Windows-Updater/1.0");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    private sealed record GitHubReleasePayload(
        [property: System.Text.Json.Serialization.JsonPropertyName("tag_name")] string TagName,
        [property: System.Text.Json.Serialization.JsonPropertyName("name")] string? Name,
        [property: System.Text.Json.Serialization.JsonPropertyName("body")] string? Body,
        [property: System.Text.Json.Serialization.JsonPropertyName("html_url")] Uri HtmlUrl,
        [property: System.Text.Json.Serialization.JsonPropertyName("assets")] GitHubAssetPayload[] Assets);

    private sealed record GitHubAssetPayload(
        [property: System.Text.Json.Serialization.JsonPropertyName("name")] string Name,
        [property: System.Text.Json.Serialization.JsonPropertyName("browser_download_url")] Uri BrowserDownloadUrl,
        [property: System.Text.Json.Serialization.JsonPropertyName("size")] long Size);

    private const string InstallerScript = """
        param(
            [Parameter(Mandatory = $true)][int]$ProcessId,
            [Parameter(Mandatory = $true)][string]$SourceDirectory,
            [Parameter(Mandatory = $true)][string]$TargetDirectory,
            [Parameter(Mandatory = $true)][string]$LaunchFile
        )
        $ErrorActionPreference = "Stop"
        $logPath = Join-Path $env:LOCALAPPDATA "Noboard\updater.log"
        $backupDirectory = Join-Path (Split-Path -Parent $SourceDirectory) "backup"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
        try {
            Wait-Process -Id $ProcessId -Timeout 90 -ErrorAction SilentlyContinue
            if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
                throw "Noboard did not exit before the update timeout."
            }
            if (Test-Path -LiteralPath $backupDirectory) {
                Remove-Item -LiteralPath $backupDirectory -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
            Get-ChildItem -LiteralPath $TargetDirectory -Force |
                Copy-Item -Destination $backupDirectory -Recurse -Force
            Get-ChildItem -LiteralPath $SourceDirectory -Force |
                Copy-Item -Destination $TargetDirectory -Recurse -Force
            $launchPath = Join-Path $TargetDirectory $LaunchFile
            if (-not (Test-Path -LiteralPath $launchPath)) {
                throw "Updated Noboard.exe is missing."
            }
            Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Update installed."
            Start-Process -FilePath $launchPath
            exit 0
        }
        catch {
            Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) Update failed: $($_.Exception.Message)"
            if (Test-Path -LiteralPath $backupDirectory) {
                Get-ChildItem -LiteralPath $backupDirectory -Force |
                    Copy-Item -Destination $TargetDirectory -Recurse -Force
            }
            exit 1
        }
        """;
}
