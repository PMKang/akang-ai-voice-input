using AkangVoiceInput.Core;

namespace AkangVoiceInput.Platform;

public sealed class ProviderCredentialStore(
    ICredentialStore bailian,
    ICredentialStore doubao,
    Func<string> activeModelProvider) : ICredentialStore
{
    private ICredentialStore ActiveStore =>
        TranscriptionOptions.IsDoubao(activeModelProvider()) ? doubao : bailian;

    public VoiceCredentials? Read() => ActiveStore.Read();
    public void Save(VoiceCredentials credentials) => ActiveStore.Save(credentials);
    public void Delete() => ActiveStore.Delete();
}
