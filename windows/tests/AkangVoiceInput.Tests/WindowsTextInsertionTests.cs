using AkangVoiceInput.Platform;

namespace AkangVoiceInput.Tests;

public sealed class WindowsTextInsertionTests
{
    [Fact]
    public void SendInputStructureHasRequiredX64Size()
    {
        Assert.Equal(8, IntPtr.Size);
        Assert.Equal(40, WindowsTextInsertionService.NativeInputStructureSize);
    }
}
