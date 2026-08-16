using AkangVoiceInput.Core;

namespace AkangVoiceInput.Tests;

public sealed class PromptCatalogTests
{
    [Fact]
    public void ProvidesFiveStableBuiltInProfiles()
    {
        var first = PromptCatalog.DefaultProfiles();
        var second = PromptCatalog.DefaultProfiles();

        Assert.Equal(5, first.Count);
        Assert.All(first, profile => Assert.True(profile.IsBuiltIn));
        Assert.Equal(first.Select(profile => profile.Id), second.Select(profile => profile.Id));
        Assert.Contains(first, profile => profile.Name == "智能整理");
        Assert.Contains(first, profile => profile.Name == "原声直达");
        Assert.Contains(first, profile => profile.Name == "清晰表达");
        Assert.Contains(first, profile => profile.Name == "正式成文");
        Assert.Contains(first, profile => profile.Name == "要点速记");
    }

    [Fact]
    public void AddsSanitizedDictionaryTermsToInstructions()
    {
        var profile = PromptCatalog.DefaultProfiles()[0];
        var result = PromptCatalog.ComposeInstructions(
            profile,
            [
                new DictionaryEntry
                {
                    Term = "阿康\n输入法",
                    Pronunciation = "a kang",
                    Replacement = "阿康输入法"
                }
            ]);

        Assert.StartsWith(profile.Instructions.Trim(), result);
        Assert.Contains("阿康 输入法", result);
        Assert.Contains("a kang", result);
        Assert.Contains("阿康输入法", result);
        Assert.DoesNotContain("阿康\n输入法", result);
    }

    [Fact]
    public void LimitsDictionaryPromptToOneHundredTerms()
    {
        var entries = Enumerable.Range(1, 105)
            .Select(index => new DictionaryEntry { Term = $"unique-term-{index:000}" });

        var result = PromptCatalog.ComposeInstructions(PromptCatalog.DefaultProfiles()[0], entries);

        Assert.Contains("unique-term-100", result);
        Assert.DoesNotContain("unique-term-101", result);
    }
}
