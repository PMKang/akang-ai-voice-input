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

Each provider's API Key and the optional crash-report ingest token are stored separately in macOS Keychain under the service identifier `com.akang.ai-voice-input.credentials.v3` and can be removed from Settings.

### Application Support

`~/Library/Application Support/AkangVoiceInput/app-data.json` stores final-text history, recording and processing durations, model names, and manual dictionary entries. Writes are atomic to reduce corruption risk.

The same directory also contains a redacted diagnostic ring buffer of at most 160 events so the next launch can detect an unexpected exit. When optional crash reporting is enabled, up to 20 failed reports can remain in a local owner-only retry queue. Turning crash reporting off clears that pending queue.

### UserDefaults

The selected model, shortcut choice, language choice, Cantonese conversion, clipboard fallback preferences, crash-reporting preference (off by default), and a non-secret Fun-ASR hotword vocabulary ID are stored in UserDefaults. A legacy Workspace ID may remain on existing installations for compatibility, but new users do not need to enter one.

## Data not retained

- Raw audio files or Base64 audio fragments
- Full WebSocket requests and responses
- Authorization headers
- Clear-text API Key or Workspace ID diagnostic logs
- Diagnostic logs containing transcription text

When Fun ASR is selected, dictionary entries eligible for recognition are sent to Alibaba Cloud's custom-vocabulary API to create or update a provider hotword list. The app stores only the returned vocabulary ID and a local change fingerprint; it does not store the provider list separately.

## Diagnostics and optional crash reporting

Up to 100 diagnostic events remain in process memory and up to 160 redacted events are kept in the local ring buffer. They cover connection, recording, response, output, permission state, durations, final-text length, token counts, and error summaries. Reports redact user paths, email addresses, Bearer tokens, common key formats, Workspace IDs, and WebSocket hosts. Transcription text is never written to diagnostics.

Automatic crash reporting is off by default. After the user opts in, the next launch checks for a matching macOS `.ips` file from the previous run and extracts only the exception type and application frames; it never uploads the raw `.ips` file. If no matching file exists, the app sends an unexpected-exit lifecycle report plus redacted breadcrumbs. Failed reports stay in the bounded local queue for retry.

The remote path is `Noboard → Cloudflare Worker → D1 → Feishu bot`. The Worker validates and sanitizes again, groups duplicate fingerprints, and sends a group alert only for a new issue, a regression of a resolved issue, or an explicit test. D1 retains redacted environment metadata, error summaries, application frames, and at most 40 breadcrumbs. Feishu messages omit the full stack and breadcrumbs.

The Feishu webhook exists only as a Worker secret. A separate ingest token is stored both as a Worker secret and in the current Mac's Keychain to reject requests that do not know the token. Neither secret belongs in source control.

This client token is not device attestation. It is suitable for personal use or controlled testing; a token preloaded into a publicly distributed client can still be extracted. A public release should move to per-install enrollment and credential rotation while retaining server-side rate limits, alert deduplication, and abuse monitoring.

## macOS permissions

- **Microphone**: captures voice only after the user starts voice input.
- **Accessibility**: inserts final text into the focused input field.

If Accessibility is not authorized or a target control does not support safe insertion, the app does not overwrite the field and falls back to the clipboard.

## Release status

- Development builds use local ad-hoc signing.
- Developer ID signing, notarization, and App Store sandboxing have not yet been completed.
- Before a public release, scan for sensitive information and review all new screenshots and documents manually.
