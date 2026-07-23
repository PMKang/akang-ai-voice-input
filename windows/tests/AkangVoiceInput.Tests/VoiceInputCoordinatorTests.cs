using AkangVoiceInput.Core;
using AkangVoiceInput.Transcription;

namespace AkangVoiceInput.Tests;

public sealed class VoiceInputCoordinatorTests
{
    [Fact]
    public async Task RecordingCompletesAndInsertsFinalText()
    {
        var audio = new FakeAudioCapture();
        var insertion = new FakeInsertion();
        await using var coordinator = Create(audio, insertion, "最终文字");

        await coordinator.StartAsync();
        Assert.Equal(VoiceSessionState.Recording, coordinator.State);
        audio.Emit(new byte[3200]);
        await coordinator.StopAsync();

        Assert.Equal(VoiceSessionState.Idle, coordinator.State);
        Assert.Equal("最终文字", insertion.InsertedText);
        Assert.True(insertion.TargetCaptured);
    }

    [Fact]
    public async Task EmptyMarkerDoesNotInsert()
    {
        var audio = new FakeAudioCapture();
        var insertion = new FakeInsertion();
        await using var coordinator = Create(audio, insertion, VoiceInputPrompt.EmptyMarker);
        await coordinator.StartAsync();
        audio.Emit(new byte[3200]);
        await coordinator.StopAsync();
        Assert.Null(insertion.InsertedText);
        Assert.Equal(VoiceSessionState.Idle, coordinator.State);
    }

    [Fact]
    public async Task MissingCredentialsMovesToErrorWithoutStartingAudio()
    {
        var audio = new FakeAudioCapture();
        await using var coordinator = new VoiceInputCoordinator(audio, new FakeTranscriptionService(), new FakeCredentials(null), new FakeInsertion());
        await coordinator.StartAsync();
        Assert.Equal(VoiceSessionState.Error, coordinator.State);
        Assert.False(audio.Started);
    }

    [Fact]
    public async Task ToggleStartsThenStops()
    {
        var audio = new FakeAudioCapture();
        await using var coordinator = Create(audio, new FakeInsertion(), "完成");
        await coordinator.ToggleAsync();
        audio.Emit(new byte[3200]);
        await coordinator.ToggleAsync();
        Assert.Equal(VoiceSessionState.Idle, coordinator.State);
    }

    private static VoiceInputCoordinator Create(FakeAudioCapture audio, FakeInsertion insertion, string finalText) =>
        new(audio, new FakeTranscriptionService(finalText), new FakeCredentials(new VoiceCredentials("test-key")), insertion);

    private sealed class FakeAudioCapture : IAudioCaptureService
    {
        public event EventHandler<PcmAudioEventArgs>? PcmAvailable;
        public event EventHandler<AudioLevelEventArgs>? LevelChanged;
        public long CapturedByteCount { get; private set; }
        public bool Started { get; private set; }
        public Task StartAsync(CancellationToken cancellationToken = default) { Started = true; CapturedByteCount = 0; return Task.CompletedTask; }
        public Task StopAsync(CancellationToken cancellationToken = default) { Started = false; return Task.CompletedTask; }
        public void Emit(byte[] data) { CapturedByteCount += data.Length; PcmAvailable?.Invoke(this, new PcmAudioEventArgs(data)); LevelChanged?.Invoke(this, new AudioLevelEventArgs(0.5f)); }
        public void Dispose() { }
    }

    private sealed class FakeCredentials(VoiceCredentials? value) : ICredentialStore
    {
        public VoiceCredentials? Read() => value;
        public void Save(VoiceCredentials credentials) => throw new NotSupportedException();
        public void Delete() => throw new NotSupportedException();
    }

    private sealed class FakeInsertion : ITextInsertionService
    {
        public bool TargetCaptured { get; private set; }
        public string? InsertedText { get; private set; }
        public void CaptureTarget() => TargetCaptured = true;
        public Task<TextInsertionResult> InsertAsync(string text, CancellationToken cancellationToken = default) { InsertedText = text; return Task.FromResult(new TextInsertionResult(true)); }
        public void ClearTarget() => TargetCaptured = false;
    }
}
