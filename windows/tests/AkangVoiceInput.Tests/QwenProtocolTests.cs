using System.Text.Json;
using AkangVoiceInput.Core;
using AkangVoiceInput.Transcription;

namespace AkangVoiceInput.Tests;

public sealed class QwenProtocolTests
{
    [Fact]
    public void PublicEndpointUsesFixedModel()
    {
        var endpoint = QwenRealtimeProtocol.BuildEndpoint(null, TranscriptionOptions.QwenModelId);
        Assert.Equal("wss", endpoint.Scheme);
        Assert.Equal(QwenRealtimeProtocol.PublicHost, endpoint.Host);
        Assert.Contains("model=qwen3.5-omni-flash-realtime", endpoint.Query);
    }

    [Fact]
    public void WorkspaceEndpointIsValidated()
    {
        Assert.Equal("team-123.cn-beijing.maas.aliyuncs.com", QwenRealtimeProtocol.BuildEndpoint("team-123", TranscriptionOptions.QwenModelId).Host);
        Assert.Throws<ArgumentException>(() => QwenRealtimeProtocol.BuildEndpoint("bad.workspace", TranscriptionOptions.QwenModelId));
    }

    [Fact]
    public void SessionUpdateMatchesRealtimeContract()
    {
        using var document = JsonDocument.Parse(QwenRealtimeProtocol.SessionUpdate("event_test", TranscriptionOptions.Default));
        var root = document.RootElement;
        Assert.Equal("session.update", root.GetProperty("type").GetString());
        var session = root.GetProperty("session");
        Assert.Equal("pcm", session.GetProperty("input_audio_format").GetString());
        Assert.Equal("qwen3-asr-flash-realtime", session.GetProperty("input_audio_transcription").GetProperty("model").GetString());
        Assert.Equal(0.2, session.GetProperty("temperature").GetDouble());
        Assert.Equal(2048, session.GetProperty("max_tokens").GetInt32());
    }

    [Fact]
    public void AudioAppendCarriesBase64Pcm()
    {
        using var document = JsonDocument.Parse(QwenRealtimeProtocol.AudioAppend("event_audio", new byte[] { 1, 2, 3 }));
        Assert.Equal("input_audio_buffer.append", document.RootElement.GetProperty("type").GetString());
        Assert.Equal("AQID", document.RootElement.GetProperty("audio").GetString());
    }
}
