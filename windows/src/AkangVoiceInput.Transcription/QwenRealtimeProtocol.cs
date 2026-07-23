using System.Text.Json;
using System.Text.RegularExpressions;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public static partial class QwenRealtimeProtocol
{
    public const string PublicHost = "dashscope.aliyuncs.com";

    public static Uri BuildEndpoint(string? workspaceId, string modelId)
    {
        if (!string.Equals(modelId, TranscriptionOptions.QwenModelId, StringComparison.Ordinal))
            throw new ArgumentException("Windows MVP 仅支持 qwen3.5-omni-flash-realtime。", nameof(modelId));

        var workspace = workspaceId?.Trim();
        var host = string.IsNullOrEmpty(workspace)
            ? PublicHost
            : WorkspacePattern().IsMatch(workspace)
                ? $"{workspace}.cn-beijing.maas.aliyuncs.com"
                : throw new ArgumentException("Workspace ID 只能包含字母、数字和连字符。", nameof(workspaceId));
        return new Uri($"wss://{host}/api-ws/v1/realtime?model={Uri.EscapeDataString(modelId)}");
    }

    public static string SessionUpdate(string eventId, TranscriptionOptions options) => JsonSerializer.Serialize(new
    {
        event_id = eventId,
        type = "session.update",
        session = new
        {
            modalities = new[] { "text" },
            input_audio_format = "pcm",
            input_audio_transcription = new { model = "qwen3-asr-flash-realtime" },
            instructions = options.Instructions,
            turn_detection = (object?)null,
            temperature = 0.2,
            max_tokens = 2048
        }
    });

    public static string AudioAppend(string eventId, ReadOnlySpan<byte> pcm16) => JsonSerializer.Serialize(new
    {
        event_id = eventId,
        type = "input_audio_buffer.append",
        audio = Convert.ToBase64String(pcm16)
    });

    public static string SimpleEvent(string eventId, string type) => JsonSerializer.Serialize(new
    {
        event_id = eventId,
        type
    });

    [GeneratedRegex("^[A-Za-z0-9-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex WorkspacePattern();
}
