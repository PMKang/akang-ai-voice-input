# Windows architecture

The Windows client is an independent .NET 10 WPF application under `windows/`. It does not change or depend on the existing macOS Swift package.

## Supported baseline

- Windows 10 Enterprise 22H2, build 19045, x64 is the minimum tested baseline.
- Windows 11 x64 is expected to work but is not yet a release gate.
- .NET 10 Desktop Runtime is required for framework-dependent builds.
- This Windows 10 baseline is self-supported by the project. Microsoft ended general Windows 10 support on 2025-10-14.

## Project boundaries

- `AkangVoiceInput.Core`: session state machine, contracts, prompt, validation, and orchestration.
- `AkangVoiceInput.Audio`: 16 kHz, 16-bit, mono PCM microphone capture. Raw audio remains in memory and is never written to disk.
- `AkangVoiceInput.Transcription`: Qwen Realtime WebSocket protocol and a fake service for deterministic tests.
- `AkangVoiceInput.Platform`: Win32 global hotkey, foreground-window tracking, clipboard/paste insertion, and Windows Credential Manager.
- `AkangVoiceInput.App`: WPF shell, tray icon, settings, compact floating status window, and composition root.
- `AkangVoiceInput.Tests`: state-machine, protocol, prompt, and validation tests without microphone or paid API access.

## Runtime flow

1. `Ctrl+Alt+Space` or the tray action toggles a session.
2. Before recording, the platform service records the foreground window.
3. The coordinator connects Qwen Realtime while microphone capture starts.
4. Audio is emitted as 100 ms PCM16 chunks and streamed as Base64 `input_audio_buffer.append` events.
5. Input-transcription snapshots replace the floating preview. Response deltas build a separate final-output buffer.
6. Stop commits the audio buffer and requests the final response.
7. `[EMPTY]` and blank results are treated as no usable speech. Other final text is left on the clipboard and pasted into the remembered target window.
8. If focus restoration or paste is blocked, the text remains on the clipboard and the UI explains the fallback.

## State model

`Idle -> Recording -> Transcribing -> Finalizing -> Inserting -> Idle`

Any operational failure moves to `Error`; dismissing or starting again returns to `Idle`. Repeated hotkey events are debounced, and state transitions serialize through the coordinator.

## Security and privacy

- API credentials are stored in Windows Credential Manager for the current user.
- The user enters one Bailian API Key; the MVP uses the public DashScope endpoint and exposes no Workspace ID setting.
- Logs must not include keys, authorization headers, raw audio, full WebSocket payloads, or recognized text.
- Audio is sent only after an explicit user action starts recording.
- Connection testing opens a session but does not capture or send audio.
- The first real microphone/API validation is a manual release step and is not run by automated tests.

## Known Windows limitations

- Windows UIPI can prevent a normal process from sending input to an elevated target. In that case the result stays on the clipboard.
- Some applications reject synthetic `Ctrl+V`, expose no conventional editable control, or change focus during finalization.
- A registered global hotkey can conflict with another application. The MVP uses fixed `Ctrl+Alt+Space` and reports registration failure.
- The MVP is a tray utility with paste-based handoff, not a TSF input method or system IME.
