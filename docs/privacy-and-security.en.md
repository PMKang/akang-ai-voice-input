# Privacy and security

This document describes the current technical data boundary of Noboard · 自在说. It is not a legal privacy policy.

## Data flow

1. `AVAudioEngine` captures microphone audio locally.
2. Audio is converted in memory to `16 kHz / mono / PCM16`.
3. Encrypted WebSocket sends audio fragments to the Alibaba Cloud Model Studio service authenticated by the user's API Key.
4. When the model returns final text, the app tries to insert it into the focused text field.
5. If insertion is unavailable, the app copies the result to the system clipboard when enabled by the user.

This is not offline speech recognition. Using voice input means audio is sent to the configured model service for processing.

## Local storage

### Keychain

Each provider's API Key is stored separately in macOS Keychain under the service identifier `com.akang.ai-voice-input` and can be removed from Settings.

### Application Support

`~/Library/Application Support/AkangVoiceInput/app-data.json` stores final-text history, recording and processing durations, model names, and manual dictionary entries. Writes are atomic to reduce corruption risk.

### UserDefaults

The selected model, shortcut choice, language choice, Cantonese conversion, clipboard fallback preferences, and a non-secret Fun-ASR hotword vocabulary ID are stored in UserDefaults. A legacy Workspace ID may remain on existing installations for compatibility, but new users do not need to enter one.

## Data not retained

- Raw audio files or Base64 audio fragments
- Full WebSocket requests and responses
- Authorization headers
- Clear-text API Key or Workspace ID diagnostic logs
- Diagnostic logs containing transcription text

When Fun ASR is selected, dictionary entries eligible for recognition are sent to Alibaba Cloud's custom-vocabulary API to create or update a provider hotword list. The app stores only the returned vocabulary ID and a local change fingerprint; it does not store the provider list separately.

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
