namespace AkangVoiceInput.Core;

public sealed record HistoryItem
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public string Text { get; init; } = string.Empty;
    public double RecordingDurationSeconds { get; init; }
    public double ProcessingDurationSeconds { get; init; }
    public string Model { get; init; } = TranscriptionOptions.QwenModelId;
    public int InputTokens { get; init; }
    public int OutputTokens { get; init; }
    public int TotalTokens => InputTokens + OutputTokens;
    public int CharacterCount => Text.Length;
    public double EstimatedCostCny => UsageEstimate.EstimatedCost(InputTokens, OutputTokens);
}

public sealed record DictionaryEntry
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Term { get; init; } = string.Empty;
    public string Pronunciation { get; init; } = string.Empty;
    public string Replacement { get; init; } = string.Empty;
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;
}

public sealed record PromptProfile
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; init; } = string.Empty;
    public string Instructions { get; init; } = string.Empty;
    public bool IsBuiltIn { get; init; }
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.Now;
}

public sealed record AppPreferences
{
    public string InterfaceLanguage { get; init; } = "zh-Hans";
    public string Shortcut { get; init; } = "Ctrl+Alt+Space";
    public bool StartWithWindows { get; init; }
    public bool KeepFinalTextOnClipboard { get; init; } = true;
}

public sealed record AppDataSnapshot
{
    public int SchemaVersion { get; init; } = 1;
    public List<HistoryItem> History { get; init; } = [];
    public List<DictionaryEntry> Dictionary { get; init; } = [];
    public List<PromptProfile> PromptProfiles { get; init; } = [];
    public Guid? SelectedPromptProfileId { get; init; }
    public AppPreferences Preferences { get; init; } = new();

    public static AppDataSnapshot CreateDefault()
    {
        var profiles = PromptCatalog.DefaultProfiles().ToList();
        return new AppDataSnapshot
        {
            PromptProfiles = profiles,
            SelectedPromptProfileId = profiles[0].Id
        };
    }

    public AppDataSnapshot WithDefaults()
    {
        var profiles = PromptProfiles.Count == 0 ? PromptCatalog.DefaultProfiles().ToList() : PromptProfiles;
        var selected = SelectedPromptProfileId is { } id && profiles.Any(profile => profile.Id == id)
            ? id
            : profiles[0].Id;
        return this with
        {
            History = History.OrderByDescending(item => item.Date).ToList(),
            Dictionary = Dictionary.OrderBy(item => item.Term, StringComparer.CurrentCultureIgnoreCase).ToList(),
            PromptProfiles = profiles,
            SelectedPromptProfileId = selected
        };
    }
}

public static class UsageEstimate
{
    public const double AudioInputCnyPerMillion = 27;
    public const double TextOutputCnyPerMillion = 20;

    public static double EstimatedCost(int inputTokens, int outputTokens) =>
        inputTokens / 1_000_000d * AudioInputCnyPerMillion
        + outputTokens / 1_000_000d * TextOutputCnyPerMillion;
}

public sealed record DailyUsage(DateOnly Date, int Characters, int Tokens, int Sessions, double ProcessingSeconds);

public sealed record DashboardSnapshot
{
    public int TotalCharacters { get; init; }
    public int TodayCharacters { get; init; }
    public double TotalRecordingSeconds { get; init; }
    public double AverageProcessingSeconds { get; init; }
    public double SavedTimeSeconds { get; init; }
    public double AverageSpeakingCharactersPerMinute { get; init; }
    public int TotalTokens { get; init; }
    public double EstimatedCostCny { get; init; }
    public int RecentSessionCount { get; init; }
    public int RecentActiveDays { get; init; }
    public int RecentLongestStreak { get; init; }
    public int RecentPeakCharacters { get; init; }
    public IReadOnlyList<DailyUsage> DailyUsage { get; init; } = [];
}
