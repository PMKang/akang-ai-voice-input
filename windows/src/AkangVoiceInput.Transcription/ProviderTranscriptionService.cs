using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public sealed class ProviderTranscriptionService : ITranscriptionService
{
    private readonly QwenRealtimeService _qwen = new();
    private readonly DoubaoRealtimeService _doubao = new();
    private ITranscriptionService? _active;

    public ProviderTranscriptionService()
    {
        _qwen.PreviewChanged += ForwardPreview;
        _doubao.PreviewChanged += ForwardPreview;
    }

    public event Action<string>? PreviewChanged;

    public Task StartAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        _active = TranscriptionOptions.IsDoubao(options.ModelId) ? _doubao : _qwen;
        return _active.StartAsync(credentials, options, cancellationToken);
    }

    public ValueTask AppendAudioAsync(ReadOnlyMemory<byte> pcm16, CancellationToken cancellationToken = default) =>
        (_active ?? throw new InvalidOperationException("转写会话尚未开始。"))
        .AppendAudioAsync(pcm16, cancellationToken);

    public Task<TranscriptionResult> CompleteAsync(CancellationToken cancellationToken = default) =>
        (_active ?? throw new InvalidOperationException("转写会话尚未开始。"))
        .CompleteAsync(cancellationToken);

    public Task TestConnectionAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        var service = TranscriptionOptions.IsDoubao(options.ModelId)
            ? (ITranscriptionService)_doubao
            : _qwen;
        return service.TestConnectionAsync(credentials, options, cancellationToken);
    }

    public Task DisconnectAsync(CancellationToken cancellationToken = default) =>
        _active?.DisconnectAsync(cancellationToken) ?? Task.CompletedTask;

    private void ForwardPreview(string text) => PreviewChanged?.Invoke(text);

    public async ValueTask DisposeAsync()
    {
        _qwen.PreviewChanged -= ForwardPreview;
        _doubao.PreviewChanged -= ForwardPreview;
        await _qwen.DisposeAsync();
        await _doubao.DisposeAsync();
    }
}
