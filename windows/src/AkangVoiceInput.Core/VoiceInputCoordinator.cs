namespace AkangVoiceInput.Core;

public sealed class VoiceInputCoordinator : IAsyncDisposable
{
    private readonly IAudioCaptureService _audio;
    private readonly ITranscriptionService _transcription;
    private readonly ICredentialStore _credentials;
    private readonly ITextInsertionService _insertion;
    private readonly Func<TranscriptionOptions> _optionsProvider;
    private readonly SemaphoreSlim _transitionGate = new(1, 1);
    private CancellationTokenSource? _sessionCancellation;
    private bool _disposed;
    private DateTimeOffset? _recordingStartedAt;
    private DateTimeOffset? _processingStartedAt;

    public VoiceInputCoordinator(
        IAudioCaptureService audio,
        ITranscriptionService transcription,
        ICredentialStore credentials,
        ITextInsertionService insertion,
        Func<TranscriptionOptions>? optionsProvider = null)
    {
        _audio = audio;
        _transcription = transcription;
        _credentials = credentials;
        _insertion = insertion;
        _optionsProvider = optionsProvider ?? (() => TranscriptionOptions.Default);
        _audio.PcmAvailable += OnPcmAvailable;
        _audio.LevelChanged += (_, e) => AudioLevelChanged?.Invoke(this, e);
        _transcription.PreviewChanged += preview => PreviewChanged?.Invoke(this, preview);
    }

    public VoiceSessionState State { get; private set; } = VoiceSessionState.Idle;
    public event EventHandler<VoiceStateChangedEventArgs>? StateChanged;
    public event EventHandler<string>? PreviewChanged;
    public event EventHandler<AudioLevelEventArgs>? AudioLevelChanged;
    public event EventHandler<VoiceSessionCompletedEventArgs>? SessionCompleted;

    public async Task ToggleAsync(CancellationToken cancellationToken = default)
    {
        if (State == VoiceSessionState.Recording)
        {
            await StopAsync(cancellationToken).ConfigureAwait(false);
        }
        else if (State is VoiceSessionState.Idle or VoiceSessionState.Error)
        {
            await StartAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        await _transitionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (State is not (VoiceSessionState.Idle or VoiceSessionState.Error)) return;
            var credentials = _credentials.Read();
            if (credentials is null || !credentials.IsValid)
            {
                SetState(VoiceSessionState.Error, "请先在设置中保存 API Key。");
                return;
            }

            _sessionCancellation?.Dispose();
            _sessionCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            var token = _sessionCancellation.Token;
            _insertion.CaptureTarget();
            PreviewChanged?.Invoke(this, string.Empty);

            try
            {
                SetState(VoiceSessionState.Recording, "正在聆听，按 Ctrl+Alt+Space 停止");
                await _transcription.StartAsync(credentials, _optionsProvider(), token).ConfigureAwait(false);
                await _audio.StartAsync(token).ConfigureAwait(false);
                _recordingStartedAt = DateTimeOffset.Now;
            }
            catch (Exception ex)
            {
                await CleanupSessionAsync().ConfigureAwait(false);
                SetState(VoiceSessionState.Error, SafeMessage(ex));
            }
        }
        finally
        {
            _transitionGate.Release();
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        await _transitionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (State != VoiceSessionState.Recording) return;
            var token = _sessionCancellation?.Token ?? cancellationToken;

            try
            {
                SetState(VoiceSessionState.Transcribing, "正在结束录音");
                await _audio.StopAsync(token).ConfigureAwait(false);
                _processingStartedAt = DateTimeOffset.Now;
                if (_audio.CapturedByteCount == 0)
                {
                    await _transcription.DisconnectAsync(token).ConfigureAwait(false);
                    _insertion.ClearTarget();
                    SetState(VoiceSessionState.Idle, "没有捕获到音频");
                    return;
                }

                SetState(VoiceSessionState.Finalizing, "正在整理最终文字");
                var result = await _transcription.CompleteAsync(token).WaitAsync(TimeSpan.FromSeconds(30), token)
                    .ConfigureAwait(false);

                if (!VoiceInputPrompt.IsUsable(result.Text))
                {
                    _insertion.ClearTarget();
                    SetState(VoiceSessionState.Idle, "没有检测到有效语音");
                    return;
                }

                SetState(VoiceSessionState.Inserting, "正在写入目标窗口");
                var insertion = await _insertion.InsertAsync(result.Text.Trim(), token).ConfigureAwait(false);
                var completedAt = DateTimeOffset.Now;
                var item = new HistoryItem
                {
                    Date = completedAt,
                    Text = result.Text.Trim(),
                    RecordingDurationSeconds = _recordingStartedAt is { } recordingStarted
                        ? Math.Max(0, ((_processingStartedAt ?? completedAt) - recordingStarted).TotalSeconds)
                        : 0,
                    ProcessingDurationSeconds = _processingStartedAt is { } processingStarted
                        ? Math.Max(0, (completedAt - processingStarted).TotalSeconds)
                        : 0,
                    Model = TranscriptionOptions.QwenModelId,
                    InputTokens = result.InputTokens,
                    OutputTokens = result.OutputTokens
                };
                SessionCompleted?.Invoke(this, new VoiceSessionCompletedEventArgs(item, insertion));
                SetState(
                    VoiceSessionState.Idle,
                    insertion.Inserted ? "已输入" : insertion.Reason ?? "文字已保留在剪贴板");
            }
            catch (Exception ex)
            {
                await CleanupSessionAsync().ConfigureAwait(false);
                SetState(VoiceSessionState.Error, SafeMessage(ex));
            }
            finally
            {
                _sessionCancellation?.Dispose();
                _sessionCancellation = null;
                _recordingStartedAt = null;
                _processingStartedAt = null;
            }
        }
        finally
        {
            _transitionGate.Release();
        }
    }

    public async Task TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        var credentials = _credentials.Read();
        if (credentials is null || !credentials.IsValid) throw new InvalidOperationException("请先保存 API Key。");
        await _transcription.TestConnectionAsync(credentials, _optionsProvider(), cancellationToken)
            .ConfigureAwait(false);
    }

    private void OnPcmAvailable(object? sender, PcmAudioEventArgs e)
    {
        if (State is not (VoiceSessionState.Recording or VoiceSessionState.Transcribing)) return;
        _ = ForwardAudioAsync(e.Data);
    }

    private async Task ForwardAudioAsync(ReadOnlyMemory<byte> data)
    {
        try
        {
            await _transcription.AppendAudioAsync(data, _sessionCancellation?.Token ?? CancellationToken.None)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex)
        {
            SetState(VoiceSessionState.Error, SafeMessage(ex));
        }
    }

    private async Task CleanupSessionAsync()
    {
        try { await _audio.StopAsync().ConfigureAwait(false); } catch { }
        try { await _transcription.DisconnectAsync().ConfigureAwait(false); } catch { }
        _insertion.ClearTarget();
    }

    private void SetState(VoiceSessionState state, string message)
    {
        State = state;
        StateChanged?.Invoke(this, new VoiceStateChangedEventArgs(state, message));
    }

    private static string SafeMessage(Exception exception) => exception switch
    {
        OperationCanceledException => "操作已取消。",
        TimeoutException => "等待模型返回最终文字超时，请重试。",
        _ => string.IsNullOrWhiteSpace(exception.Message) ? "语音输入失败，请重试。" : exception.Message
    };

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        _sessionCancellation?.Cancel();
        await CleanupSessionAsync().ConfigureAwait(false);
        _audio.PcmAvailable -= OnPcmAvailable;
        _audio.Dispose();
        await _transcription.DisposeAsync().ConfigureAwait(false);
        _transitionGate.Dispose();
        _sessionCancellation?.Dispose();
    }
}
