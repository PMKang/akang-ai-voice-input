# Privacy and security

This document describes the current technical data boundary of Noboard · 自在说. It is not a legal privacy policy.

## Data flow

1. `AVAudioEngine` captures microphone audio locally.
2. Audio is converted in memory to `16 kHz / mono / PCM16`.
3. Encrypted WebSocket sends audio fragments to the Alibaba Cloud Model Studio Workspace configured by the user.
4. When the model returns final text, the app tries to insert it into the focused text field.
5. If insertion is unavailable, the app copies the result to the system clipboard when enabled by the user.

This is not offline speech recognition. Using voice input means audio is sent to the configured model service for processing.

## Local storage

### Keychain

Your API Key is stored in macOS Keychain under the service identifier `com.akang.ai-voice-input` and can be removed from Settings.

### Application Support

`~/Library/Application Support/AkangVoiceInput/app-data.json` stores final-text history, recording and processing durations, model names, and manual dictionary entries. Writes are atomic to reduce corruption risk.

### UserDefaults

Workspace ID, shortcut choice, language choice, Cantonese conversion, and clipboard fallback preferences are stored in UserDefaults.

## Data not retained

- Raw audio files or Base64 audio fragments
- Full WebSocket requests and responses
- Authorization headers
- Clear-text API Key or Workspace ID diagnostic logs
- Diagnostic logs containing transcription text

## Diagnostics

Diagnostic events remain only in process memory, with at most 100 entries. They cover connection, recording, response, output, permission state, durations, final-text length, token counts, and error summaries. Before copying, reports redact Bearer tokens, common key formats, Workspace IDs, and WebSocket hosts. Diagnostics are cleared when the app quits.

## macOS permissions

- **Microphone**: captures voice only after the user starts voice input.
- **Accessibility**: inserts final text into the focused input field.

If Accessibility is not authorized or a target control does not support safe insertion, the app does not overwrite the field and falls back to the clipboard.

## Release status

- Development builds use local ad-hoc signing.
- Developer ID signing, notarization, and App Store sandboxing have not yet been completed.
- Before a public release, scan for sensitive information and review all new screenshots and documents manually.
