using System.Text.Json;

namespace AkangVoiceInput.Core;

public interface IAppDataStore
{
    string DataFilePath { get; }
    Task<AppDataSnapshot> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(AppDataSnapshot snapshot, CancellationToken cancellationToken = default);
}

public sealed class JsonAppDataStore : IAppDataStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };
    private readonly SemaphoreSlim _gate = new(1, 1);

    public JsonAppDataStore(string? dataFilePath = null)
    {
        DataFilePath = dataFilePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Noboard",
            "app-data.json");
    }

    public string DataFilePath { get; }

    public async Task<AppDataSnapshot> LoadAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!File.Exists(DataFilePath)) return AppDataSnapshot.CreateDefault();
            await using var stream = File.OpenRead(DataFilePath);
            var snapshot = await JsonSerializer.DeserializeAsync<AppDataSnapshot>(stream, JsonOptions, cancellationToken)
                .ConfigureAwait(false);
            return (snapshot ?? AppDataSnapshot.CreateDefault()).WithDefaults();
        }
        catch (JsonException)
        {
            return AppDataSnapshot.CreateDefault();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task SaveAsync(AppDataSnapshot snapshot, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var directory = Path.GetDirectoryName(DataFilePath)
                ?? throw new InvalidOperationException("数据文件路径无效。");
            Directory.CreateDirectory(directory);
            var temporaryPath = DataFilePath + ".tmp";
            await using (var stream = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                await JsonSerializer.SerializeAsync(stream, snapshot.WithDefaults(), JsonOptions, cancellationToken)
                    .ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            }
            File.Move(temporaryPath, DataFilePath, true);
        }
        finally
        {
            _gate.Release();
        }
    }
}
