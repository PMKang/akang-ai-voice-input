# Noboard for Windows

Windows 10/11 x64 companion implementation for the Noboard AI voice-input project.

## Requirements

- Windows 10 22H2 build 19045 x64 or newer
- .NET 10 SDK to build, or .NET 10 Desktop Runtime to run a framework-dependent build
- A microphone permitted under Windows privacy settings
- An Alibaba Cloud Bailian/DashScope API key

## Build and test

```powershell
dotnet restore .\AkangVoiceInput.Windows.sln
dotnet build .\AkangVoiceInput.Windows.sln -c Debug
dotnet test .\AkangVoiceInput.Windows.sln -c Debug --no-build
```

Run from `windows/`:

```powershell
dotnet run --project .\src\AkangVoiceInput.App\AkangVoiceInput.App.csproj
```

Create the self-contained Windows x64 archive from the repository root:

```powershell
.\windows\scripts\publish-win-x64.ps1
```

Generated release files are written to `windows/artifacts/` and are intentionally excluded from Git.

## First use

1. Open **Settings > Voice model**.
2. Save the API key in Windows Credential Manager. The MVP uses the public DashScope endpoint and does not require a Workspace ID.
3. Use **Test connection** to validate the WebSocket handshake without recording audio.
4. Focus a text box in another application and press `Ctrl+Alt+Space` to start.
5. Speak, then press `Ctrl+Alt+Space` again to stop and insert the final text.

The selected model is fixed to `qwen3.5-omni-flash-realtime` in the MVP.

## Privacy

Raw microphone audio is kept in memory, streamed to the configured Qwen Realtime service, and never saved by the app. Credentials are stored for the current Windows user in Windows Credential Manager. Automated tests use a fake transcription service and never access the microphone or paid APIs.

Every usable final result remains on the clipboard, whether or not the focused application accepts automatic paste.

## Troubleshooting

- If the shortcut cannot register, another application may already own `Ctrl+Alt+Space`.
- If text is not pasted, it remains on the clipboard. A non-elevated app cannot synthesize input into an elevated window.
- If microphone capture fails, check **Settings > Privacy > Microphone** and the active input device.
- The Windows MVP is paste-based; it is not a TSF input method and does not appear in the Windows language bar.
