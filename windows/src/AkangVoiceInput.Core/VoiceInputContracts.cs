namespace AkangVoiceInput.Core;

public enum VoiceSessionState
{
    Idle,
    Recording,
    Transcribing,
    Finalizing,
    Inserting,
    Error
}

public sealed record VoiceCredentials(string ApiKey, string? WorkspaceId = null)
{
    public bool IsValid => !string.IsNullOrWhiteSpace(ApiKey);
}

public sealed record TranscriptionOptions(string ModelId, string Instructions)
{
    public const string QwenModelId = "qwen3.5-omni-flash-realtime";

    public static TranscriptionOptions Default { get; } = new(QwenModelId, VoiceInputPrompt.Default);
}

public sealed record TranscriptionResult(string Text, int InputTokens = 0, int OutputTokens = 0);

public sealed record TextInsertionResult(bool Inserted, string? Reason = null);

public sealed class PcmAudioEventArgs(ReadOnlyMemory<byte> data) : EventArgs
{
    public ReadOnlyMemory<byte> Data { get; } = data;
}

public sealed class AudioLevelEventArgs(float level) : EventArgs
{
    public float Level { get; } = Math.Clamp(level, 0, 1);
}

public interface IAudioCaptureService : IDisposable
{
    event EventHandler<PcmAudioEventArgs>? PcmAvailable;
    event EventHandler<AudioLevelEventArgs>? LevelChanged;
    long CapturedByteCount { get; }
    Task StartAsync(CancellationToken cancellationToken = default);
    Task StopAsync(CancellationToken cancellationToken = default);
}

public interface ITranscriptionService : IAsyncDisposable
{
    event Action<string>? PreviewChanged;
    Task StartAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default);
    ValueTask AppendAudioAsync(ReadOnlyMemory<byte> pcm16, CancellationToken cancellationToken = default);
    Task<TranscriptionResult> CompleteAsync(CancellationToken cancellationToken = default);
    Task TestConnectionAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default);
    Task DisconnectAsync(CancellationToken cancellationToken = default);
}

public interface ICredentialStore
{
    VoiceCredentials? Read();
    void Save(VoiceCredentials credentials);
    void Delete();
}

public interface ITextInsertionService
{
    void CaptureTarget();
    Task<TextInsertionResult> InsertAsync(string text, CancellationToken cancellationToken = default);
    void ClearTarget();
}

public sealed class VoiceStateChangedEventArgs(VoiceSessionState state, string message) : EventArgs
{
    public VoiceSessionState State { get; } = state;
    public string Message { get; } = message;
}

public sealed class VoiceSessionCompletedEventArgs(HistoryItem item, TextInsertionResult insertion) : EventArgs
{
    public HistoryItem Item { get; } = item;
    public TextInsertionResult Insertion { get; } = insertion;
}
