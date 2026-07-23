using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public sealed class QwenRealtimeService : ITranscriptionService
{
    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _receiveCancellation;
    private Task? _receiveTask;
    private TaskCompletionSource? _ready;
    private TaskCompletionSource<TranscriptionResult>? _final;
    private readonly StringBuilder _finalText = new();
    private int _inputTokens;
    private int _outputTokens;
    private bool _disposed;

    public event Action<string>? PreviewChanged;

    public async Task StartAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!credentials.IsValid) throw new InvalidOperationException("API Key 未配置。");
        await DisconnectAsync(cancellationToken).ConfigureAwait(false);

        _finalText.Clear();
        _inputTokens = 0;
        _outputTokens = 0;
        _ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _final = new TaskCompletionSource<TranscriptionResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        _receiveCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _socket = new ClientWebSocket();
        _socket.Options.SetRequestHeader("Authorization", $"Bearer {credentials.ApiKey.Trim()}");

        var endpoint = QwenRealtimeProtocol.BuildEndpoint(credentials.WorkspaceId, options.ModelId);
        await _socket.ConnectAsync(endpoint, cancellationToken).WaitAsync(TimeSpan.FromSeconds(20), cancellationToken)
            .ConfigureAwait(false);
        _receiveTask = ReceiveLoopAsync(_socket, _receiveCancellation.Token);
        await SendTextAsync(QwenRealtimeProtocol.SessionUpdate(NewEventId(), options), cancellationToken)
            .ConfigureAwait(false);
        await _ready.Task.WaitAsync(TimeSpan.FromSeconds(20), cancellationToken).ConfigureAwait(false);
    }

    public ValueTask AppendAudioAsync(ReadOnlyMemory<byte> pcm16, CancellationToken cancellationToken = default)
    {
        if (pcm16.IsEmpty) return ValueTask.CompletedTask;
        return new ValueTask(SendTextAsync(QwenRealtimeProtocol.AudioAppend(NewEventId(), pcm16.Span), cancellationToken));
    }

    public async Task<TranscriptionResult> CompleteAsync(CancellationToken cancellationToken = default)
    {
        EnsureConnected();
        var final = _final ?? throw new InvalidOperationException("转写会话尚未开始。");
        await SendTextAsync(
            QwenRealtimeProtocol.SimpleEvent(NewEventId(), "input_audio_buffer.commit"),
            cancellationToken).ConfigureAwait(false);
        await SendTextAsync(
            QwenRealtimeProtocol.SimpleEvent(NewEventId(), "response.create"),
            cancellationToken).ConfigureAwait(false);
        var result = await final.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
        await DisconnectAsync(CancellationToken.None).ConfigureAwait(false);
        return result;
    }

    public async Task TestConnectionAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await StartAsync(credentials, options, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            await DisconnectAsync(CancellationToken.None).ConfigureAwait(false);
        }
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        var socket = _socket;
        var receiveTask = _receiveTask;
        _socket = null;
        _receiveTask = null;
        _receiveCancellation?.Cancel();

        if (socket is not null)
        {
            try
            {
                if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "done", cancellationToken)
                        .ConfigureAwait(false);
            }
            catch (Exception) when (cancellationToken.IsCancellationRequested || socket.State != WebSocketState.Open)
            {
            }
            socket.Dispose();
        }

        if (receiveTask is not null)
        {
            try { await receiveTask.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false); }
            catch (Exception) { }
        }

        _receiveCancellation?.Dispose();
        _receiveCancellation = null;
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[16 * 1024];
        try
        {
            while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                using var message = new MemoryStream();
                WebSocketReceiveResult result;
                do
                {
                    result = await socket.ReceiveAsync(buffer, cancellationToken).ConfigureAwait(false);
                    if (result.MessageType == WebSocketMessageType.Close) return;
                    message.Write(buffer, 0, result.Count);
                } while (!result.EndOfMessage);

                if (result.MessageType == WebSocketMessageType.Text)
                    HandleServerMessage(Encoding.UTF8.GetString(message.GetBuffer(), 0, checked((int)message.Length)));
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            Fail(ex);
        }
        finally
        {
            if (!cancellationToken.IsCancellationRequested && _final is { Task.IsCompleted: false })
                Fail(new InvalidOperationException("模型连接已关闭，未收到最终文字。"));
        }
    }

    private void HandleServerMessage(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var type = ReadString(root, "type");
        switch (type)
        {
            case "session.updated":
                _ready?.TrySetResult();
                break;
            case "conversation.item.input_audio_transcription.delta":
            case "conversation.item.input_audio_transcription.text":
                var text = ReadString(root, "text") ?? ReadString(root, "transcript") ?? ReadString(root, "delta") ?? string.Empty;
                var stash = ReadString(root, "stash") ?? string.Empty;
                PreviewChanged?.Invoke(text + stash);
                break;
            case "conversation.item.input_audio_transcription.completed":
                PreviewChanged?.Invoke(ReadString(root, "transcript") ?? ReadString(root, "text") ?? string.Empty);
                break;
            case "response.text.delta":
                _finalText.Append(ReadString(root, "delta"));
                break;
            case "response.text.done":
                var completed = ReadString(root, "text");
                if (!string.IsNullOrEmpty(completed))
                {
                    _finalText.Clear();
                    _finalText.Append(completed);
                }
                TryCompleteFinal();
                break;
            case "response.done":
                ReadUsage(root);
                TryCompleteFinal();
                break;
            case "error":
                var error = root.TryGetProperty("error", out var errorObject)
                    ? ReadString(errorObject, "message")
                    : null;
                Fail(new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "模型服务返回错误。" : error));
                break;
        }
    }

    private void ReadUsage(JsonElement root)
    {
        if (!root.TryGetProperty("response", out var response) ||
            !response.TryGetProperty("usage", out var usage)) return;
        _inputTokens = ReadInt(usage, "input_tokens");
        _outputTokens = ReadInt(usage, "output_tokens");
    }

    private void TryCompleteFinal()
    {
        var text = _finalText.ToString().Trim();
        if (!string.IsNullOrEmpty(text))
            _final?.TrySetResult(new TranscriptionResult(text, _inputTokens, _outputTokens));
    }

    private void Fail(Exception exception)
    {
        _ready?.TrySetException(exception);
        _final?.TrySetException(exception);
    }

    private async Task SendTextAsync(string json, CancellationToken cancellationToken)
    {
        EnsureConnected();
        var bytes = Encoding.UTF8.GetBytes(json);
        await _sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await _socket!.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sendGate.Release();
        }
    }

    private void EnsureConnected()
    {
        if (_socket?.State != WebSocketState.Open) throw new InvalidOperationException("模型连接尚未建立。");
    }

    private static string NewEventId() => $"event_{Guid.NewGuid():N}";
    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static int ReadInt(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.TryGetInt32(out var number) ? number : 0;

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        await DisconnectAsync().ConfigureAwait(false);
        _sendGate.Dispose();
    }
}
