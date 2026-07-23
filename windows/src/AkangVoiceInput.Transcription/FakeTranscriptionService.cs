using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public sealed class FakeTranscriptionService(string finalText = "测试完成") : ITranscriptionService
{
    private readonly List<byte> _audio = [];
    private bool _started;

    public event Action<string>? PreviewChanged;
    public int AudioByteCount => _audio.Count;

    public Task StartAsync(VoiceCredentials credentials, TranscriptionOptions options, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _audio.Clear();
        _started = true;
        return Task.CompletedTask;
    }

    public ValueTask AppendAudioAsync(ReadOnlyMemory<byte> pcm16, CancellationToken cancellationToken = default)
    {
        if (!_started) throw new InvalidOperationException("Fake session not started.");
        cancellationToken.ThrowIfCancellationRequested();
        _audio.AddRange(pcm16.ToArray());
        PreviewChanged?.Invoke("测试预览");
        return ValueTask.CompletedTask;
    }

    public Task<TranscriptionResult> CompleteAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _started = false;
        return Task.FromResult(new TranscriptionResult(finalText));
    }

    public Task TestConnectionAsync(VoiceCredentials credentials, TranscriptionOptions options, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    public Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        _started = false;
        return Task.CompletedTask;
    }

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
