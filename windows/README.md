# Noboard for Windows

Windows 10/11 x64 implementation of Noboard AI voice input. The Windows and
macOS applications live in separate platform directories and share product
behavior without sharing platform UI code.

The public product version comes from the repository-root `VERSION` file.
Windows and macOS packages always use that same version and are published
together in one GitHub Release.

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

1. Open **语音模型**.
2. Save the API key in Windows Credential Manager. The public DashScope endpoint does not require a Workspace ID.
3. Use **Test connection** to validate the WebSocket handshake without recording audio.
4. Focus a text box in another application and press `Ctrl+Alt+Space` to start.
5. Speak, then press `Ctrl+Alt+Space` again to stop and insert the final text.

The selected model is currently fixed to `qwen3.5-omni-flash-realtime`.

## Product features

- Global `Ctrl+Alt+Space` recording shortcut, live floating preview, clipboard fallback, and tray operation
- Home dashboard with totals, duration, processing time, speaking speed, token/cost estimate, and 35-day activity
- Searchable and filterable local history with record details, copy, delete, and clear operations
- Personal dictionary entries injected into the recognition instructions
- Five built-in expression modes plus editable custom modes
- Credential readiness, connection testing, optional startup with Windows, local-data controls, privacy information, and diagnostics

History, dictionary, expression profiles, preferences, and usage data are stored
in `%LOCALAPPDATA%\Noboard\app-data.json`. Startup and failure diagnostics are
written to `%LOCALAPPDATA%\Noboard\diagnostics.log`. Neither file contains the
API key.

## Privacy

Raw microphone audio is kept in memory, streamed to the configured Qwen Realtime service, and never saved by the app. Credentials are stored for the current Windows user in Windows Credential Manager. Automated tests use a fake transcription service and never access the microphone or paid APIs.

Every usable final result remains on the clipboard, whether or not the focused application accepts automatic paste.

## Troubleshooting

- If the shortcut cannot register, another application may already own `Ctrl+Alt+Space`.
- If text is not pasted, it remains on the clipboard. A non-elevated app cannot synthesize input into an elevated window.
- If microphone capture fails, check **Settings > Privacy > Microphone** and the active input device.
- The Windows app is paste-based; it is not a TSF input method and does not appear in the Windows language bar.
