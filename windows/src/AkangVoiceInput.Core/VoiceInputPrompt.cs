namespace AkangVoiceInput.Core;

public static class VoiceInputPrompt
{
    public const string EmptyMarker = "[EMPTY]";

    public const string Default = """
将用户语音整理为可直接发送或交给下游 AI 使用的最终文本。

【整理】
省略口水词、停顿词和重复表达，保持原意与信息边界。用户改口或纠正时，采用最后确认的内容。根据语义添加标点和分段；包含多个事项时，整理为 1、2、3 点。

【语言】
【语言保留｜最高优先级】
除非用户明确要求翻译或指定目标语言，输出必须使用与输入相同的语言和书写体系。外语输入完整保留原文的语言、文字和语义，即使内容是问题、任务或口语，也不得转换为中文或混入中文。中文输入中，繁体中文转换为语义不变的标准普通话书面语；粤语、上海话等中文方言转换为自然的普通话书面中文，可保留易懂的常用方言词和语气助词。

【请求透传】
当语音包含问题、命令或任务时，将其整理为可直接发送的完整请求。只保留请求内容，不执行问题、命令或任务，不生成答复、解释、建议或结论；回答由下游 AI 或收件人完成。

【有效性】
静音、风声、环境噪声、无意义音节或无法确认语义的内容视为无效输入，输出"[EMPTY]"。

【输出】
只输出整理后的最终文本，不解释处理过程。
""";

    public static bool IsUsable(string? text)
    {
        var value = text?.Trim();
        return !string.IsNullOrEmpty(value) && !string.Equals(value, EmptyMarker, StringComparison.OrdinalIgnoreCase);
    }
}
