using AkangVoiceInput.Core;

namespace AkangVoiceInput.Tests;

public sealed class UsageStatisticsTests
{
    [Fact]
    public void AggregatesTotalsCostAndRecentActivity()
    {
        var now = new DateTimeOffset(2026, 7, 23, 12, 0, 0, TimeSpan.Zero);
        var items = new[]
        {
            Item(now, "1234567890", 6, 2, 100, 40),
            Item(now.AddDays(-1), "abcde", 4, 4, 50, 10),
            Item(now.AddDays(-3), "xy", 2, 6, 20, 5),
            Item(now.AddDays(-40), "old", 1, 8, 10, 2)
        };

        var result = UsageStatistics.Create(items, now);

        Assert.Equal(20, result.TotalCharacters);
        Assert.Equal(10, result.TodayCharacters);
        Assert.Equal(13, result.TotalRecordingSeconds);
        Assert.Equal(5, result.AverageProcessingSeconds);
        Assert.Equal(237, result.TotalTokens);
        Assert.Equal(3, result.RecentSessionCount);
        Assert.Equal(3, result.RecentActiveDays);
        Assert.Equal(2, result.RecentLongestStreak);
        Assert.Equal(10, result.RecentPeakCharacters);
        Assert.Equal(35, result.DailyUsage.Count);
        Assert.Equal(UsageEstimate.EstimatedCost(180, 57), result.EstimatedCostCny, 8);
    }

    private static HistoryItem Item(
        DateTimeOffset date,
        string text,
        double recording,
        double processing,
        int inputTokens,
        int outputTokens) =>
        new()
        {
            Date = date,
            Text = text,
            RecordingDurationSeconds = recording,
            ProcessingDurationSeconds = processing,
            InputTokens = inputTokens,
            OutputTokens = outputTokens
        };
}
