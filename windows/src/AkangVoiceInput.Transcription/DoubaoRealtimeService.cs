using System.Buffers.Binary;
using System.IO.Compression;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public sealed class DoubaoRealtimeService : ITranscriptionService
{
    private static readonly Uri Endpoint =
        new("wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async");
    private const string ResourceId = "volc.seedasr.sauc.duration";

    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private ClientWebSocket? _socket;
    private CancellationTokenSource? _receiveCancellation;
    private Task? _receiveTask;
    private TaskCompletionSource? _ready;
    private TaskCompletionSource<TranscriptionResult>? _final;
    private string _latestText = string.Empty;
    private int _nextSequence = 1;
    private bool _disposed;

    public event Action<string>? PreviewChanged;

    public async Task StartAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!credentials.IsValid) throw new InvalidOperationException("请先保存豆包 API Key。");
        if (!TranscriptionOptions.IsDoubao(options.ModelId))
            throw new ArgumentException("豆包服务仅支持 Doubao Streaming ASR 2.0。", nameof(options));

        await DisconnectAsync(cancellationToken).ConfigureAwait(false);
        _latestText = string.Empty;
        _nextSequence = 1;
        _ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _final = new TaskCompletionSource<TranscriptionResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        _receiveCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _socket = new ClientWebSocket();
        _socket.Options.SetRequestHeader("X-Api-Key", credentials.ApiKey.Trim());
        _socket.Options.SetRequestHeader("X-Api-Resource-Id", ResourceId);
        _socket.Options.SetRequestHeader("X-Api-Connect-Id", Guid.NewGuid().ToString("D").ToLowerInvariant());
        _socket.Options.SetRequestHeader("X-Api-Request-Id", Guid.NewGuid().ToString("D").ToLowerInvariant());
        _socket.Options.SetRequestHeader("X-Api-Sequence", "-1");

        await _socket.ConnectAsync(Endpoint, cancellationToken)
            .WaitAsync(TimeSpan.FromSeconds(20), cancellationToken).ConfigureAwait(false);
        _receiveTask = ReceiveLoopAsync(_socket, _receiveCancellation.Token);
        await SendFullClientRequestAsync(cancellationToken).ConfigureAwait(false);
        await _ready.Task.WaitAsync(TimeSpan.FromSeconds(20), cancellationToken).ConfigureAwait(false);
    }

    public ValueTask AppendAudioAsync(ReadOnlyMemory<byte> pcm16, CancellationToken cancellationToken = default) =>
        pcm16.IsEmpty
            ? ValueTask.CompletedTask
            : new ValueTask(SendAudioAsync(pcm16, false, cancellationToken));

    public async Task<TranscriptionResult> CompleteAsync(CancellationToken cancellationToken = default)
    {
        var final = _final ?? throw new InvalidOperationException("转写会话尚未开始。");
        await SendAudioAsync(ReadOnlyMemory<byte>.Empty, true, cancellationToken).ConfigureAwait(false);
        var result = await final.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
        await DisconnectAsync(CancellationToken.None).ConfigureAwait(false);
        return result;
    }

    public async Task TestConnectionAsync(
        VoiceCredentials credentials,
        TranscriptionOptions options,
        CancellationToken cancellationToken = default)
    {
        try { await StartAsync(credentials, options, cancellationToken).ConfigureAwait(false); }
        finally { await DisconnectAsync(CancellationToken.None).ConfigureAwait(false); }
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
            catch { }
            socket.Dispose();
        }
        if (receiveTask is not null)
        {
            try { await receiveTask.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false); }
            catch { }
        }
        _receiveCancellation?.Dispose();
        _receiveCancellation = null;
    }

    private async Task SendFullClientRequestAsync(CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            user = new { uid = "noboard-windows" },
            audio = new { format = "pcm", codec = "raw", rate = 16000, bits = 16, channel = 1 },
            request = new { model_name = "bigmodel", enable_itn = true, enable_punc = true, result_type = "full" }
        });
        await SendFrameAsync(
            BuildFrame(0x1, 0x1, 0x1, 0x1, ConsumeSequence(), Gzip(payload)),
            cancellationToken).ConfigureAwait(false);
    }

    private Task SendAudioAsync(ReadOnlyMemory<byte> data, bool final, CancellationToken cancellationToken)
    {
        var sequence = ConsumeSequence();
        return SendFrameAsync(
            BuildFrame(0x2, final ? (byte)0x3 : (byte)0x1, 0x0, 0x1,
                final ? -sequence : sequence, Gzip(data.Span)),
            cancellationToken);
    }

    private async Task SendFrameAsync(byte[] frame, CancellationToken cancellationToken)
    {
        if (_socket?.State != WebSocketState.Open)
            throw new InvalidOperationException("豆包模型连接尚未建立。");
        await _sendGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await _socket.SendAsync(frame, WebSocketMessageType.Binary, true, cancellationToken)
                .ConfigureAwait(false);
        }
        finally { _sendGate.Release(); }
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
                if (result.MessageType == WebSocketMessageType.Binary)
                    HandleFrame(message.ToArray());
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception ex) { Fail(ex); }
    }

    private void HandleFrame(byte[] data)
    {
        if (data.Length < 8) throw new InvalidOperationException("豆包返回了过短的二进制帧。");
        var headerSize = (data[0] & 0x0f) * 4;
        if (headerSize < 4 || data.Length < headerSize)
            throw new InvalidOperationException("豆包返回了无效协议头。");
        var messageType = data[1] >> 4;
        var flags = data[1] & 0x0f;
        var compression = data[2] & 0x0f;
        var cursor = headerSize;

        if (messageType == 0x0f)
        {
            if (data.Length < cursor + 8) throw new InvalidOperationException("豆包错误帧不完整。");
            var code = ReadUInt32(data, cursor);
            cursor += 4;
            var length = checked((int)ReadUInt32(data, cursor));
            cursor += 4;
            var detail = Encoding.UTF8.GetString(Decode(data.AsSpan(cursor, length), compression));
            throw new InvalidOperationException($"豆包模型服务返回错误 {code}：{detail}");
        }
        if (messageType != 0x09) return;
        if ((flags & 0x01) != 0) cursor += 4;
        if ((flags & 0x04) != 0) cursor += 4;
        if (data.Length < cursor + 4) throw new InvalidOperationException("豆包结果帧不完整。");
        var payloadLength = checked((int)ReadUInt32(data, cursor));
        cursor += 4;
        if (data.Length < cursor + payloadLength) throw new InvalidOperationException("豆包结果负载不完整。");
        var payload = Decode(data.AsSpan(cursor, payloadLength), compression);
        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        if (root.TryGetProperty("code", out var codeElement) && codeElement.GetInt32() != 0)
            throw new InvalidOperationException(root.TryGetProperty("message", out var message)
                ? message.GetString() : "豆包模型服务返回错误。");

        _ready?.TrySetResult();
        if (root.TryGetProperty("result", out var result) &&
            result.TryGetProperty("text", out var textElement))
        {
            var text = textElement.GetString()?.Trim() ?? string.Empty;
            if (!string.IsNullOrEmpty(text))
            {
                _latestText = text;
                PreviewChanged?.Invoke(text);
            }
        }
        if (flags == 0x03)
        {
            if (string.IsNullOrWhiteSpace(_latestText))
                Fail(new InvalidOperationException("豆包识别完成但未返回文字。"));
            else
                _final?.TrySetResult(new TranscriptionResult(_latestText));
        }
    }

    private int ConsumeSequence() => _nextSequence++;

    private static byte[] BuildFrame(
        byte type, byte flags, byte serialization, byte compression, int sequence, byte[] payload)
    {
        var frame = new byte[12 + payload.Length];
        frame[0] = 0x11;
        frame[1] = (byte)(type << 4 | flags);
        frame[2] = (byte)(serialization << 4 | compression);
        BinaryPrimitives.WriteInt32BigEndian(frame.AsSpan(4, 4), sequence);
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(8, 4), checked((uint)payload.Length));
        payload.CopyTo(frame, 12);
        return frame;
    }

    private static uint ReadUInt32(byte[] data, int offset) =>
        BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(offset, 4));

    private static byte[] Gzip(ReadOnlySpan<byte> data)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Fastest, true))
            gzip.Write(data);
        return output.ToArray();
    }

    private static byte[] Decode(ReadOnlySpan<byte> payload, int compression)
    {
        if (compression == 0) return payload.ToArray();
        if (compression != 1) throw new InvalidOperationException($"豆包返回了不支持的压缩格式：{compression}。");
        using var input = new MemoryStream(payload.ToArray());
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        using var output = new MemoryStream();
        gzip.CopyTo(output);
        return output.ToArray();
    }

    private void Fail(Exception exception)
    {
        _ready?.TrySetException(exception);
        _final?.TrySetException(exception);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        await DisconnectAsync();
        _sendGate.Dispose();
    }
}
