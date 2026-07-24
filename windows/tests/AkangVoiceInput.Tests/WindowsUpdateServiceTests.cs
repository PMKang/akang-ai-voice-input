using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Diagnostics;
using AkangVoiceInput.Platform;

namespace AkangVoiceInput.Tests;

public sealed class WindowsUpdateServiceTests
{
    [Theory]
    [InlineData("v1.6.1", "1.6.0", true)]
    [InlineData("1.6.0", "1.6.0", false)]
    [InlineData("v1.5.9", "1.6.0", false)]
    [InlineData("v2.0.0-preview.1", "1.9.9", true)]
    public void IsNewerVersionComparesReleaseComponents(string candidate, string current, bool expected)
    {
        Assert.Equal(expected, WindowsUpdateService.IsNewerVersion(candidate, current));
    }

    [Fact]
    public async Task FetchLatestReleaseSelectsWindowsArchiveAndChecksum()
    {
        var payload = """
            {
              "tag_name":"v1.6.1",
              "name":"Noboard v1.6.1",
              "body":"notes",
              "html_url":"https://example.test/release",
              "assets":[
                {"name":"Noboard-v1.6.1-macos.zip","browser_download_url":"https://example.test/mac.zip","size":10},
                {"name":"Noboard-v1.6.1-windows-x64.zip","browser_download_url":"https://example.test/windows.zip","size":20},
                {"name":"Noboard-v1.6.1-windows-x64.zip.sha256","browser_download_url":"https://example.test/windows.sha256","size":98}
              ]
            }
            """;
        using var client = new HttpClient(new StubHandler(_ =>
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json")
            }));
        var service = new WindowsUpdateService(client, Path.GetTempPath());

        var release = await service.FetchLatestReleaseAsync();

        Assert.Equal("v1.6.1", release.Version);
        Assert.Equal("Noboard-v1.6.1-windows-x64.zip", release.Archive.Name);
        Assert.Equal("Noboard-v1.6.1-windows-x64.zip.sha256", release.Checksum.Name);
    }

    [Fact]
    public async Task DownloadAndPrepareVerifiesChecksumAndExecutable()
    {
        var root = Path.Combine(Path.GetTempPath(), $"noboard-update-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var archiveBytes = CreateUpdateArchive();
            var hash = Convert.ToHexStringLower(SHA256.HashData(archiveBytes));
            using var client = new HttpClient(new StubHandler(request =>
            {
                var content = request.RequestUri!.AbsolutePath.EndsWith(".sha256", StringComparison.Ordinal)
                    ? new ByteArrayContent(Encoding.ASCII.GetBytes($"{hash}  Noboard-v9.9.9-windows-x64.zip"))
                    : new ByteArrayContent(archiveBytes);
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = content };
            }));
            var service = new WindowsUpdateService(client, root);
            var release = new WindowsReleaseInfo(
                "v9.9.9",
                "test",
                string.Empty,
                new Uri("https://example.test/release"),
                new WindowsReleaseAsset(
                    "Noboard-v9.9.9-windows-x64.zip",
                    new Uri("https://example.test/update.zip"),
                    archiveBytes.Length),
                new WindowsReleaseAsset(
                    "Noboard-v9.9.9-windows-x64.zip.sha256",
                    new Uri("https://example.test/update.zip.sha256"),
                    98));

            var prepared = await service.DownloadAndPrepareAsync(release);

            Assert.Equal(hash, prepared.Sha256);
            Assert.True(File.Exists(Path.Combine(prepared.StagingDirectory, "Noboard.exe")));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task ScheduledInstallerReplacesFilesAfterProcessExits()
    {
        var root = Path.Combine(Path.GetTempPath(), $"noboard-installer-test-{Guid.NewGuid():N}");
        var versionRoot = Path.Combine(root, "v9.9.9");
        var source = Path.Combine(versionRoot, "staging");
        var target = Path.Combine(root, "installed");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(target);
        var sourceExecutable = Path.Combine(source, "Noboard.exe");
        var targetExecutable = Path.Combine(target, "Noboard.exe");
        File.Copy(Path.Combine(Environment.SystemDirectory, "where.exe"), sourceExecutable);
        File.Copy(Path.Combine(Environment.SystemDirectory, "whoami.exe"), targetExecutable);
        var archive = Path.Combine(versionRoot, "update.zip");
        await File.WriteAllTextAsync(archive, "test");

        try
        {
            using var waitProcess = Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c ping 127.0.0.1 -n 2 >nul",
                CreateNoWindow = true,
                UseShellExecute = false
            })!;
            var service = new WindowsUpdateService(updatesRoot: root);
            var prepared = new PreparedWindowsUpdate("v9.9.9", source, archive, "test");

            service.ScheduleInstallAndRestart(
                prepared,
                waitProcess.Id,
                target,
                targetExecutable);

            var expectedHash = Convert.ToHexStringLower(SHA256.HashData(await File.ReadAllBytesAsync(sourceExecutable)));
            var installed = false;
            for (var attempt = 0; attempt < 50; attempt++)
            {
                await Task.Delay(100);
                if (!File.Exists(targetExecutable)) continue;
                var actualHash = Convert.ToHexStringLower(
                    SHA256.HashData(await File.ReadAllBytesAsync(targetExecutable)));
                if (actualHash != expectedHash) continue;
                installed = true;
                break;
            }

            Assert.True(installed, "The external updater did not replace Noboard.exe.");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static byte[] CreateUpdateArchive()
    {
        using var output = new MemoryStream();
        using (var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
        {
            var entry = archive.CreateEntry("Noboard.exe");
            using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
            writer.Write("test executable");
        }
        return output.ToArray();
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            Task.FromResult(handler(request));
    }
}
