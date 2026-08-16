using AkangVoiceInput.Core;

namespace AkangVoiceInput.Tests;

public sealed class ShortcutBindingTests
{
    [Theory]
    [InlineData("LeftAlt", "左 Alt")]
    [InlineData("RightAlt", "右 Alt")]
    [InlineData("F2", "F2")]
    [InlineData("Ctrl+Alt+Space", "Ctrl + Alt + Space")]
    [InlineData("Ctrl+Shift+Space", "Ctrl + Shift + Space")]
    [InlineData("Alt+Shift+Space", "Alt + Shift + Space")]
    [InlineData("Ctrl+Alt+V", "Ctrl + Alt + V")]
    [InlineData("Ctrl+Shift+J", "Ctrl + Shift + J")]
    [InlineData("Alt+7", "Alt + 7")]
    [InlineData("Shift+F12", "Shift + F12")]
    public void ParsesLegacyAndCustomShortcutText(string stored, string display)
    {
        var binding = ShortcutBinding.ParseLegacy(stored);

        Assert.True(binding.Validate().IsValid);
        Assert.Equal(display, binding.DisplayText);
        Assert.Equal(stored, binding.CanonicalText);
    }

    [Fact]
    public void NewInstallUsesRecommendedLeftAltPreset()
    {
        var snapshot = AppDataSnapshot.CreateDefault();

        Assert.Equal(ShortcutBinding.LeftAlt, snapshot.Preferences.Shortcut);
    }

    [Theory]
    [InlineData("J")]
    [InlineData("Space")]
    [InlineData("F1")]
    [InlineData("Alt+F4")]
    [InlineData("Alt+Space")]
    public void RejectsUnsafeOrReservedShortcut(string stored)
    {
        Assert.Throws<FormatException>(() => ShortcutBinding.ParseLegacy(stored));
    }

    [Fact]
    public void WarnsWhenShortcutMayConflictWithInputMethod()
    {
        var binding = ShortcutBinding.ParseLegacy("Ctrl+Space");

        var validation = binding.Validate();

        Assert.True(validation.IsValid);
        Assert.True(validation.IsWarning);
        Assert.Contains("输入法", validation.Message);
    }

    [Fact]
    public async Task SavesStructuredShortcutAndLoadsItBack()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"noboard-tests-{Guid.NewGuid():N}");
        var path = Path.Combine(directory, "app-data.json");
        try
        {
            var store = new JsonAppDataStore(path);
            var expected = ShortcutBinding.ParseLegacy("Ctrl+Shift+J");
            var snapshot = AppDataSnapshot.CreateDefault() with
            {
                Preferences = new AppPreferences { Shortcut = expected }
            };

            await store.SaveAsync(snapshot);
            var json = await File.ReadAllTextAsync(path);
            var loaded = await store.LoadAsync();

            Assert.Contains("\"kind\": \"custom\"", json);
            Assert.Contains("\"virtualKey\": 74", json);
            Assert.Equal(expected, loaded.Preferences.Shortcut);
        }
        finally
        {
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }
}
