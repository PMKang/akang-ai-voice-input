using AkangVoiceInput.Core;

namespace AkangVoiceInput.Tests;

public sealed class JsonAppDataStoreTests
{
    [Fact]
    public async Task SavesAndLoadsHistoryDictionaryProfilesAndPreferences()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"noboard-tests-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "app-data.json");
        try
        {
            var store = new JsonAppDataStore(path);
            var customProfile = new PromptProfile
            {
                Name = "会议纪要",
                Instructions = "整理为会议纪要。",
                IsBuiltIn = false
            };
            var snapshot = new AppDataSnapshot
            {
                History =
                [
                    new HistoryItem
                    {
                        Text = "测试历史",
                        RecordingDurationSeconds = 3,
                        InputTokens = 10,
                        OutputTokens = 5
                    }
                ],
                Dictionary = [new DictionaryEntry { Term = "Noboard", Replacement = "Noboard" }],
                PromptProfiles = [customProfile],
                SelectedPromptProfileId = customProfile.Id,
                Preferences = new AppPreferences { StartWithWindows = true }
            };

            await store.SaveAsync(snapshot);
            var loaded = await store.LoadAsync();

            Assert.Equal("测试历史", Assert.Single(loaded.History).Text);
            Assert.Equal("Noboard", Assert.Single(loaded.Dictionary).Term);
            Assert.Equal(customProfile.Id, loaded.SelectedPromptProfileId);
            Assert.True(loaded.Preferences.StartWithWindows);
            Assert.False(File.Exists(path + ".tmp"));
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task InvalidJsonFallsBackToBuiltInDefaults()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"noboard-tests-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "app-data.json");
        try
        {
            Directory.CreateDirectory(directory);
            await File.WriteAllTextAsync(path, "{invalid");

            var loaded = await new JsonAppDataStore(path).LoadAsync();

            Assert.Equal(5, loaded.PromptProfiles.Count);
            Assert.NotNull(loaded.SelectedPromptProfileId);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }
}
