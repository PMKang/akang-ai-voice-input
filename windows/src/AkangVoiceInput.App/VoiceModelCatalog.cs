using AkangVoiceInput.Core;

namespace AkangVoiceInput.App;

internal sealed record VoiceModelOption(
    string Id,
    string Provider,
    string Name,
    string Subtitle,
    string Capability);

internal static class VoiceModelCatalog
{
    public static IReadOnlyList<VoiceModelOption> All { get; } =
    [
        new(
            TranscriptionOptions.QwenModelId,
            "阿里云百炼",
            "Qwen 3.5 Omni Flash Realtime",
            "当前默认 · 实时语音输入 · 支持表达方式提示词",
            "支持表达方式提示词"),
        new(
            TranscriptionOptions.QwenPlusModelId,
            "阿里云百炼",
            "Qwen 3.5 Omni Plus Realtime",
            "Prompt 上下文、多语种与情感识别",
            "支持表达方式提示词"),
        new(
            TranscriptionOptions.FunAsrModelId,
            "阿里云百炼",
            "Fun ASR Realtime",
            "实时语音识别 · 热词、多语种及方言",
            "支持原始转写与个人词典"),
        new(
            TranscriptionOptions.DoubaoModelId,
            "豆包",
            "Doubao Streaming ASR 2.0",
            "双向流式 WebSocket · 原始实时转写",
            "不执行表达方式提示词")
    ];

    public static string DisplayName(string id) =>
        All.FirstOrDefault(option => option.Id == id)?.Name ?? id;
}
