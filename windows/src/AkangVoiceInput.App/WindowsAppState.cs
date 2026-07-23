using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AkangVoiceInput.Core;

namespace AkangVoiceInput.App;

public sealed class WindowsAppState : INotifyPropertyChanged
{
    private readonly IAppDataStore _store;
    private HistoryItem? _selectedHistoryItem;
    private PromptProfile? _selectedPromptProfile;
    private PromptProfile? _activePromptProfile;
    private string _historySearch = string.Empty;
    private int _historyRangeIndex;
    private string _dictionarySearch = string.Empty;
    private DashboardSnapshot _dashboard = new();
    private string _dashboardUsageScope = "all";
    private string _lastDataStatus = "本地数据已就绪";

    public WindowsAppState(IAppDataStore store)
    {
        _store = store;
        var snapshot = store.LoadAsync().GetAwaiter().GetResult().WithDefaults();
        foreach (var item in snapshot.History) HistoryItems.Add(item);
        foreach (var entry in snapshot.Dictionary) DictionaryEntries.Add(entry);
        foreach (var profile in snapshot.PromptProfiles) PromptProfiles.Add(profile);
        Preferences = snapshot.Preferences;
        ActivePromptProfile = PromptProfiles.FirstOrDefault(profile => profile.Id == snapshot.SelectedPromptProfileId)
            ?? PromptProfiles.First();
        SelectedPromptProfile = ActivePromptProfile;
        RefreshAll();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public ObservableCollection<HistoryItem> HistoryItems { get; } = [];
    public ObservableCollection<HistoryItem> FilteredHistoryItems { get; } = [];
    public ObservableCollection<HistoryItem> RecentHistoryItems { get; } = [];
    public ObservableCollection<DictionaryEntry> DictionaryEntries { get; } = [];
    public ObservableCollection<DictionaryEntry> FilteredDictionaryEntries { get; } = [];
    public ObservableCollection<PromptProfile> PromptProfiles { get; } = [];
    public ObservableCollection<DailyUsage> DailyUsage { get; } = [];
    public AppPreferences Preferences { get; private set; }
    public string DataFilePath => _store.DataFilePath;

    public HistoryItem? SelectedHistoryItem
    {
        get => _selectedHistoryItem;
        set { _selectedHistoryItem = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasSelectedHistory)); }
    }

    public bool HasSelectedHistory => SelectedHistoryItem is not null;

    public PromptProfile? SelectedPromptProfile
    {
        get => _selectedPromptProfile;
        set
        {
            if (value is null || ReferenceEquals(_selectedPromptProfile, value)) return;
            _selectedPromptProfile = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SelectedPromptInstructions));
        }
    }

    public PromptProfile? ActivePromptProfile
    {
        get => _activePromptProfile;
        private set
        {
            if (value is null || ReferenceEquals(_activePromptProfile, value)) return;
            _activePromptProfile = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ActivePromptProfileName));
        }
    }

    public string ActivePromptProfileName => ActivePromptProfile?.Name ?? "智能整理";
    public string SelectedPromptInstructions => SelectedPromptProfile?.Instructions ?? VoiceInputPrompt.Default;
    public string ActiveVoiceModelName => VoiceModelCatalog.DisplayName(Preferences.ActiveVoiceModelId);
    public string ActiveVoiceProviderName => TranscriptionOptions.IsDoubao(Preferences.ActiveVoiceModelId)
        ? "豆包" : "阿里云百炼";

    public string DashboardUsageScope
    {
        get => _dashboardUsageScope;
        set
        {
            var normalized = value is "doubao" or "bailian" ? value : "all";
            if (_dashboardUsageScope == normalized) return;
            _dashboardUsageScope = normalized;
            OnPropertyChanged();
            RefreshDashboard();
        }
    }

    public string HistorySearch
    {
        get => _historySearch;
        set { _historySearch = value ?? string.Empty; OnPropertyChanged(); RefreshHistoryFilter(); }
    }

    public int HistoryRangeIndex
    {
        get => _historyRangeIndex;
        set { _historyRangeIndex = value; OnPropertyChanged(); RefreshHistoryFilter(); }
    }

    public string DictionarySearch
    {
        get => _dictionarySearch;
        set { _dictionarySearch = value ?? string.Empty; OnPropertyChanged(); RefreshDictionaryFilter(); }
    }

    public DashboardSnapshot Dashboard
    {
        get => _dashboard;
        private set
        {
            _dashboard = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(TotalCharactersDisplay));
            OnPropertyChanged(nameof(TodayCharactersDisplay));
            OnPropertyChanged(nameof(TotalRecordingDisplay));
            OnPropertyChanged(nameof(AverageProcessingDisplay));
            OnPropertyChanged(nameof(RecentProcessingDisplay));
            OnPropertyChanged(nameof(BaselineProcessingDisplay));
            OnPropertyChanged(nameof(RecentProcessingCaption));
            OnPropertyChanged(nameof(BaselineProcessingCaption));
            OnPropertyChanged(nameof(SavedTimeDisplay));
            OnPropertyChanged(nameof(SpeakingSpeedDisplay));
            OnPropertyChanged(nameof(TotalTokensDisplay));
            OnPropertyChanged(nameof(EstimatedCostDisplay));
            OnPropertyChanged(nameof(MonthlyCharactersDisplay));
            OnPropertyChanged(nameof(MonthlyTokensDisplay));
            OnPropertyChanged(nameof(AccountBalanceDisplay));
            OnPropertyChanged(nameof(RecentActivityDisplay));
        }
    }

    public string TotalCharactersDisplay => Dashboard.TotalCharacters.ToString("N0");
    public string TodayCharactersDisplay => Dashboard.TodayCharacters.ToString("N0");
    public string TotalRecordingDisplay => FormatDuration(Dashboard.TotalRecordingSeconds);
    public string AverageProcessingDisplay => $"{Dashboard.AverageProcessingSeconds:F2} 秒";
    public string RecentProcessingDisplay => Dashboard.Recent3DaySessionCount == 0
        ? "—" : $"{Dashboard.Recent3DayAverageProcessingSeconds:F3} 秒";
    public string BaselineProcessingDisplay => Dashboard.Baseline30DaySessionCount == 0
        ? "—" : $"{Dashboard.Baseline30DayAverageProcessingSeconds:F3} 秒";
    public string RecentProcessingCaption => $"最近 3 天 · {Dashboard.Recent3DaySessionCount} 次";
    public string BaselineProcessingCaption => $"近 30 天 · {Dashboard.Baseline30DaySessionCount} 次";
    public string SavedTimeDisplay => FormatDuration(Dashboard.SavedTimeSeconds);
    public string SpeakingSpeedDisplay => $"{Dashboard.AverageSpeakingCharactersPerMinute:F0} 字/分钟";
    public string TotalTokensDisplay => Dashboard.TokenAccountingSupported
        ? Dashboard.TotalTokens.ToString("N0") : "暂不支持";
    public string EstimatedCostDisplay => Dashboard.EstimatedCostSupported
        ? $"¥{Dashboard.EstimatedCostCny:F4}" : "暂不支持";
    public string MonthlyCharactersDisplay => Dashboard.RecentCharacters.ToString("N0");
    public string MonthlyTokensDisplay => Dashboard.TokenAccountingSupported
        ? Dashboard.RecentTokens.ToString("N0") : "暂不支持";
    public string AccountBalanceDisplay => DashboardUsageScope == "all" ? "按供应商查看" : "暂不支持";
    public string RecentActivityDisplay =>
        $"{Dashboard.RecentSessionCount} 次 · {Dashboard.RecentActiveDays} 个活跃日 · 最长连续 {Dashboard.RecentLongestStreak} 天";

    public string LastDataStatus
    {
        get => _lastDataStatus;
        private set { _lastDataStatus = value; OnPropertyChanged(); }
    }

    public TranscriptionOptions CreateTranscriptionOptions()
    {
        var profile = ActivePromptProfile ?? PromptCatalog.DefaultProfiles()[0];
        return new TranscriptionOptions(
            Preferences.ActiveVoiceModelId,
            TranscriptionOptions.IsPromptCompatible(Preferences.ActiveVoiceModelId)
                ? PromptCatalog.ComposeInstructions(profile, DictionaryEntries)
                : string.Empty);
    }

    public async Task RecordSessionAsync(HistoryItem item)
    {
        HistoryItems.Insert(0, item);
        SelectedHistoryItem = item;
        RefreshAll();
        await PersistAsync("已保存本次语音记录");
    }

    public async Task DeleteHistoryAsync(HistoryItem item)
    {
        HistoryItems.Remove(item);
        if (SelectedHistoryItem?.Id == item.Id) SelectedHistoryItem = FilteredHistoryItems.FirstOrDefault();
        RefreshAll();
        await PersistAsync("历史记录已删除");
    }

    public async Task ClearHistoryAsync()
    {
        HistoryItems.Clear();
        SelectedHistoryItem = null;
        RefreshAll();
        await PersistAsync("历史记录已清空");
    }

    public async Task SaveDictionaryEntryAsync(DictionaryEntry entry)
    {
        var existing = DictionaryEntries.FirstOrDefault(item => item.Id == entry.Id);
        if (existing is not null)
        {
            var index = DictionaryEntries.IndexOf(existing);
            DictionaryEntries[index] = entry;
        }
        else
        {
            DictionaryEntries.Add(entry);
        }
        SortDictionary();
        RefreshDictionaryFilter();
        await PersistAsync("个人词典已更新");
    }

    public async Task DeleteDictionaryEntryAsync(DictionaryEntry entry)
    {
        DictionaryEntries.Remove(entry);
        RefreshDictionaryFilter();
        await PersistAsync("词条已删除");
    }

    public async Task ActivatePromptProfileAsync(PromptProfile profile)
    {
        ActivePromptProfile = profile;
        await PersistAsync($"已启用「{profile.Name}」");
    }

    public async Task<PromptProfile> CreatePromptProfileAsync(string name, string instructions)
    {
        var profile = new PromptProfile
        {
            Name = string.IsNullOrWhiteSpace(name) ? NextCustomProfileName() : name.Trim(),
            Instructions = string.IsNullOrWhiteSpace(instructions) ? VoiceInputPrompt.Default : instructions.Trim(),
            IsBuiltIn = false
        };
        PromptProfiles.Add(profile);
        SelectedPromptProfile = profile;
        await PersistAsync($"已创建「{profile.Name}」");
        return profile;
    }

    public async Task<PromptProfile> DuplicatePromptProfileAsync(PromptProfile source)
    {
        return await CreatePromptProfileAsync($"{source.Name}（自定义）", source.Instructions);
    }

    public async Task UpdatePromptProfileAsync(PromptProfile source, string name, string instructions)
    {
        if (source.IsBuiltIn) throw new InvalidOperationException("内置表达方式请先复制为自定义方案。");
        if (string.IsNullOrWhiteSpace(instructions)) throw new InvalidOperationException("表达规则不能为空。");
        var updated = source with
        {
            Name = string.IsNullOrWhiteSpace(name) ? source.Name : name.Trim(),
            Instructions = instructions.Trim()
        };
        var index = PromptProfiles.IndexOf(source);
        PromptProfiles[index] = updated;
        SelectedPromptProfile = updated;
        if (ActivePromptProfile?.Id == source.Id) ActivePromptProfile = updated;
        await PersistAsync($"已保存「{updated.Name}」");
    }

    public async Task DeletePromptProfileAsync(PromptProfile profile)
    {
        if (profile.IsBuiltIn) throw new InvalidOperationException("内置表达方式不能删除。");
        PromptProfiles.Remove(profile);
        SelectedPromptProfile = PromptProfiles.First();
        if (ActivePromptProfile?.Id == profile.Id) ActivePromptProfile = PromptProfiles.First();
        await PersistAsync("自定义表达方式已删除");
    }

    public async Task UpdatePreferencesAsync(AppPreferences preferences)
    {
        Preferences = preferences;
        OnPropertyChanged(nameof(Preferences));
        OnPropertyChanged(nameof(ActiveVoiceModelName));
        OnPropertyChanged(nameof(ActiveVoiceProviderName));
        await PersistAsync("设置已保存");
    }

    public async Task ResetAllDataAsync()
    {
        HistoryItems.Clear();
        DictionaryEntries.Clear();
        PromptProfiles.Clear();
        foreach (var profile in PromptCatalog.DefaultProfiles()) PromptProfiles.Add(profile);
        ActivePromptProfile = PromptProfiles[0];
        SelectedPromptProfile = ActivePromptProfile;
        Preferences = new AppPreferences();
        RefreshAll();
        await PersistAsync("已恢复本地默认数据");
    }

    private async Task PersistAsync(string status)
    {
        var snapshot = new AppDataSnapshot
        {
            History = HistoryItems.ToList(),
            Dictionary = DictionaryEntries.ToList(),
            PromptProfiles = PromptProfiles.ToList(),
            SelectedPromptProfileId = ActivePromptProfile?.Id,
            Preferences = Preferences
        };
        await _store.SaveAsync(snapshot);
        LastDataStatus = status;
    }

    private void RefreshAll()
    {
        RefreshDashboard();
        Replace(RecentHistoryItems, HistoryItems.Take(5));
        RefreshHistoryFilter();
        RefreshDictionaryFilter();
    }

    private void RefreshDashboard()
    {
        var scoped = _dashboardUsageScope switch
        {
            "doubao" => HistoryItems.Where(item => TranscriptionOptions.IsDoubao(item.Model)),
            "bailian" => HistoryItems.Where(item => !TranscriptionOptions.IsDoubao(item.Model)),
            _ => HistoryItems.AsEnumerable()
        };
        Dashboard = UsageStatistics.Create(scoped);
        Replace(DailyUsage, Dashboard.DailyUsage);
    }

    private void RefreshHistoryFilter()
    {
        var now = DateTimeOffset.Now;
        var earliest = HistoryRangeIndex switch
        {
            1 => now.Date,
            2 => now.AddDays(-7),
            3 => now.AddDays(-30),
            _ => DateTimeOffset.MinValue
        };
        var filtered = HistoryItems.Where(item =>
            item.Date >= earliest
            && (string.IsNullOrWhiteSpace(HistorySearch)
                || item.Text.Contains(HistorySearch, StringComparison.CurrentCultureIgnoreCase)));
        Replace(FilteredHistoryItems, filtered);
        if (SelectedHistoryItem is null || !FilteredHistoryItems.Any(item => item.Id == SelectedHistoryItem.Id))
            SelectedHistoryItem = FilteredHistoryItems.FirstOrDefault();
    }

    private void RefreshDictionaryFilter()
    {
        var filtered = DictionaryEntries.Where(entry =>
            string.IsNullOrWhiteSpace(DictionarySearch)
            || entry.Term.Contains(DictionarySearch, StringComparison.CurrentCultureIgnoreCase)
            || entry.Replacement.Contains(DictionarySearch, StringComparison.CurrentCultureIgnoreCase));
        Replace(FilteredDictionaryEntries, filtered);
    }

    private void SortDictionary()
    {
        var sorted = DictionaryEntries.OrderBy(entry => entry.Term, StringComparer.CurrentCultureIgnoreCase).ToList();
        Replace(DictionaryEntries, sorted);
    }

    private string NextCustomProfileName()
    {
        var index = 1;
        var candidate = "自定义表达";
        while (PromptProfiles.Any(profile => profile.Name == candidate))
        {
            index++;
            candidate = $"自定义表达 {index}";
        }
        return candidate;
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> source)
    {
        target.Clear();
        foreach (var item in source) target.Add(item);
    }

    private static string FormatDuration(double seconds)
    {
        var duration = TimeSpan.FromSeconds(Math.Max(0, seconds));
        if (duration.TotalHours >= 1) return $"{(int)duration.TotalHours} 小时 {duration.Minutes} 分";
        if (duration.TotalMinutes >= 1) return $"{duration.Minutes} 分 {duration.Seconds} 秒";
        return $"{duration.TotalSeconds:F0} 秒";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
