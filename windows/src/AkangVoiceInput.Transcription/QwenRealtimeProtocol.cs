using System.Text.Json;
using System.Text.RegularExpressions;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.Transcription;

public static partial class QwenRealtimeProtocol
{
    public const string PublicHost = "dashscope.aliyuncs.com";

    public static Uri BuildEndpoint(string? workspaceId, string modelId)
    {
        if (modelId is not (TranscriptionOptions.QwenModelId
            or TranscriptionOptions.QwenPlusModelId
            or TranscriptionOptions.FunAsrModelId))
            throw new ArgumentException("不支持的阿里云百炼录音模型。", nameof(modelId));

        var workspace = workspaceId?.Trim();
        var host = string.IsNullOrEmpty(workspace)
            ? PublicHost
            : WorkspacePattern().IsMatch(workspace)
                ? $"{workspace}.cn-beijing.maas.aliyuncs.com"
                : throw new ArgumentException("Workspace ID 只能包含字母、数字和连字符。", nameof(workspaceId));
        return modelId == TranscriptionOptions.FunAsrModelId
            ? new Uri($"wss://{host}/api-ws/v1/inference")
            : new Uri($"wss://{host}/api-ws/v1/realtime?model={Uri.EscapeDataString(modelId)}");
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

    public static string FunTaskStart(string taskId) => JsonSerializer.Serialize(new
    {
        header = new { action = "run-task", task_id = taskId, streaming = "duplex" },
        payload = new
        {
            task_group = "audio",
            task = "asr",
            function = "recognition",
            model = TranscriptionOptions.FunAsrModelId,
            parameters = new
            {
                format = "pcm",
                sample_rate = 16000,
                semantic_punctuation_enabled = false,
                max_sentence_silence = 2500,
                heartbeat = true
            },
            input = new { }
        }
    });

    public static string FunTaskFinish(string taskId) => JsonSerializer.Serialize(new
    {
        header = new { action = "finish-task", task_id = taskId, streaming = "duplex" },
        payload = new { input = new { } }
    });

    [GeneratedRegex("^[A-Za-z0-9-]+$", RegexOptions.CultureInvariant)]
    private static partial Regex WorkspacePattern();
}
