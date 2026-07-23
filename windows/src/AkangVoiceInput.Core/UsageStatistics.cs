namespace AkangVoiceInput.Core;

public static class UsageStatistics
{
    private const double AssumedTypingCharactersPerMinute = 40;

    public static DashboardSnapshot Create(
        IEnumerable<HistoryItem> source,
        DateTimeOffset? now = null,
        int recentDays = 35)
    {
        var current = now ?? DateTimeOffset.Now;
        var items = source.OrderByDescending(item => item.Date).ToList();
        var today = DateOnly.FromDateTime(current.LocalDateTime);
        var firstDay = today.AddDays(-(recentDays - 1));
        var daily = Enumerable.Range(0, recentDays)
            .Select(offset => firstDay.AddDays(offset))
            .ToDictionary(date => date, date => new MutableDaily(date));

        foreach (var item in items)
        {
            var date = DateOnly.FromDateTime(item.Date.LocalDateTime);
            if (!daily.TryGetValue(date, out var bucket)) continue;
            bucket.Characters += item.CharacterCount;
            bucket.Tokens += item.TotalTokens;
            bucket.Sessions++;
            bucket.ProcessingSeconds += item.ProcessingDurationSeconds;
        }

        var activities = daily.Values.OrderBy(bucket => bucket.Date)
            .Select(bucket => new DailyUsage(bucket.Date, bucket.Characters, bucket.Tokens, bucket.Sessions, bucket.ProcessingSeconds))
            .ToList();
        var totalCharacters = items.Sum(item => item.CharacterCount);
        var totalRecording = items.Sum(item => item.RecordingDurationSeconds);
        var totalProcessing = items.Sum(item => item.ProcessingDurationSeconds);
        var threeDayStart = current.AddDays(-3);
        var thirtyDayStart = current.AddDays(-30);
        var recentProcessing = items.Where(item => item.Date >= threeDayStart && item.ProcessingDurationSeconds > 0).ToList();
        var baselineProcessing = items.Where(item => item.Date >= thirtyDayStart && item.ProcessingDurationSeconds > 0).ToList();
        var estimatedTypingSeconds = totalCharacters / AssumedTypingCharactersPerMinute * 60;
        return new DashboardSnapshot
        {
            TotalCharacters = totalCharacters,
            TodayCharacters = items.Where(item => DateOnly.FromDateTime(item.Date.LocalDateTime) == today).Sum(item => item.CharacterCount),
            TotalRecordingSeconds = totalRecording,
            AverageProcessingSeconds = items.Count == 0 ? 0 : totalProcessing / items.Count,
            Recent3DayAverageProcessingSeconds = recentProcessing.Count == 0
                ? 0 : recentProcessing.Average(item => item.ProcessingDurationSeconds),
            Recent3DaySessionCount = recentProcessing.Count,
            Baseline30DayAverageProcessingSeconds = baselineProcessing.Count == 0
                ? 0 : baselineProcessing.Average(item => item.ProcessingDurationSeconds),
            Baseline30DaySessionCount = baselineProcessing.Count,
            SavedTimeSeconds = Math.Max(0, estimatedTypingSeconds - totalRecording),
            AverageSpeakingCharactersPerMinute = totalRecording <= 0 ? 0 : totalCharacters / totalRecording * 60,
            TotalTokens = items.Sum(item => item.TotalTokens),
            TokenAccountingSupported = items.All(item =>
                item.Model is TranscriptionOptions.QwenModelId or TranscriptionOptions.QwenPlusModelId),
            EstimatedCostCny = items.Where(item => item.Model == TranscriptionOptions.QwenModelId)
                .Sum(item => item.EstimatedCostCny),
            EstimatedCostSupported = items.Any(item =>
                item.Model == TranscriptionOptions.QwenModelId && item.TotalTokens > 0),
            RecentSessionCount = activities.Sum(activity => activity.Sessions),
            RecentCharacters = activities.Sum(activity => activity.Characters),
            RecentTokens = activities.Sum(activity => activity.Tokens),
            RecentActiveDays = activities.Count(activity => activity.Characters > 0),
            RecentLongestStreak = LongestStreak(activities),
            RecentPeakCharacters = activities.Max(activity => activity.Characters),
            DailyUsage = activities
        };
    }

    private static int LongestStreak(IEnumerable<DailyUsage> activities)
    {
        var longest = 0;
        var current = 0;
        foreach (var activity in activities)
        {
            current = activity.Characters > 0 ? current + 1 : 0;
            longest = Math.Max(longest, current);
        }
        return longest;
    }

    private sealed class MutableDaily(DateOnly date)
    {
        public DateOnly Date { get; } = date;
        public int Characters { get; set; }
        public int Tokens { get; set; }
        public int Sessions { get; set; }
        public double ProcessingSeconds { get; set; }
    }
}
