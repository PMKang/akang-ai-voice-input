# Noboard · 自在说

<h3 align="center">
  <a href="README.md">Read in English</a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="README.zh-CN.md">阅读简体中文版</a>
</h3>

> Talk free. Write naturally. An AI voice-input tool for macOS and Windows, built from scratch with Codex.

## Platform support and versions

Noboard supports both macOS and Windows. The two native clients share the same
product goals and visual language while keeping platform-specific code separate.

| Platform | Current version | System requirement | Source |
| --- | --- | --- | --- |
| macOS | `1.5.0` | macOS 12 Monterey or later; Apple silicon and Intel | Repository root: `Sources/`, `Package.swift`, and `AkangVoiceInput.xcodeproj` |
| Windows | `1.5.0-windows-preview.1` | Windows 10 22H2 (build 19045) or Windows 11, x64 | `windows/` |

The Windows version is currently a preview. Platform version numbers may advance
independently when a release contains platform-specific changes.

## See it in action

https://github.com/user-attachments/assets/1514c115-916f-4858-a3d6-d77244e5a1dd

## The story behind Noboard

After trying voice-input apps again, I found the experience surprisingly uneven. Some were slow, some stalled at exactly the moment I had a complete thought, and some subscriptions were hard to justify for everyday use. At the same time, my daily Codex allowance often reset unused. So I gave myself a practical challenge: could a product manager work with AI to build the voice-input tool I actually wanted to use?

The project grew from a small experiment into an end-to-end product journey: comparing models, validating real-time audio, studying competing products, prototyping the interface, handling macOS permissions and global shortcuts, and learning how to insert text reliably across applications. The difficult part was never drawing a polished window. It was making the path from “I have a thought” to “the words are already in the right text field” feel short and dependable.

Noboard is the result. It is local-first, uses the user’s own model credentials, and remains open for anyone who wants to inspect, adapt, or improve it. I am sharing not only a finished app, but also the decisions, limitations, and unfinished edges behind it—because those are often the most useful parts of building with AI.

## Product overview

![Noboard · 自在说](docs/images/app-overview.jpeg)

## What it does

- Starts and stops voice input from any application with a global shortcut.
- Shows a floating panel on the active screen with a live waveform and recognition preview.
- Writes the final text into the focused field, or copies it to the clipboard when direct insertion is unavailable.
- Cleans up filler words, self-corrections, punctuation, paragraphs, and lists according to the selected writing style.
- Understands Chinese dialects such as Cantonese and Shanghainese, then turns them into natural written Mandarin while retaining understandable local tone.
- Stores history, personal dictionary entries, writing styles, token usage, estimated cost, and activity insights locally.
- Includes Sky Blue, Indigo Violet, and Coral icon themes; the selection updates the UI accent color and the running Dock icon.
- Lets you choose Alibaba Cloud Qwen 3.5 Omni Flash Realtime, Qwen 3.5 Omni Plus Realtime, Fun ASR Realtime, or Doubao Streaming ASR 2.0. Fun ASR automatically maps your local personal dictionary to provider hotwords; Doubao uses its own single API Key and performs direct streaming transcription.
- Lets users customize Chinese and English brand names independently; the sidebar, menu bar, About page, and recording panel update together.
- Uses a custom hollow microphone menu-bar icon. While recording, only the inner core fills so it remains distinct from the system microphone icon.

The default model is Alibaba Cloud Model Studio’s `qwen3.5-omni-flash-realtime`. A single Realtime WebSocket session handles audio understanding, prompt injection, and text output, avoiding the extra delay of a separate ASR-to-LLM pipeline. The architecture is not tied to one model provider and can be extended later.

## Three ways to use it

### 1. Download and use

You do not need Xcode, Visual Studio, or build knowledge.

1. Open the [latest release page](https://github.com/PMKang/akang-ai-voice-input/releases/latest).
2. For macOS, download the package whose name contains `macos.dmg`, for example `AkangVoiceInput-v1.5.0-0722223000-macos.dmg`. Open the DMG and drag `Noboard · 自在说.app` onto `Applications`.
3. For Windows, download the Windows x64 package, extract it to a folder, and launch `Noboard.exe`.
4. If macOS cannot verify the developer on first launch, hold `Control`, click the app, choose **Open**, and confirm once more.
5. In **Voice Model Configuration**, add your own Alibaba Cloud Model Studio or Doubao API Key, test the connection, then grant the requested permissions.

Each release still includes a `macos.zip` asset for the in-app updater and for manual extraction when needed.

macOS 12 (Monterey) and later are supported. The package is Universal and runs on both Apple silicon and Intel Macs. On macOS 12, the menu bar uses a native status-item menu; the **Launch at Login** setting requires macOS 13 or later.

The app never provides or bundles a shared key. Your credentials are stored in the current Mac’s Keychain; history, dictionary entries, and writing-style rules stay on the device.

For the full first-run setup flow, see the [First-run setup guide](docs/first-run-setup.en.md).

### 2. Clone the source and build with AI

If the packaged app is not enough, or you want to see how it works, clone the source. You can give the commands and any errors below to Codex, ChatGPT, or another coding assistant.

```bash
git clone https://github.com/PMKang/akang-ai-voice-input.git
cd akang-ai-voice-input
open AkangVoiceInput.xcodeproj
```

You can also run:

```bash
swift test
./script/build_and_run.sh --verify
```

To build the Windows client on Windows:

```powershell
cd windows
dotnet restore .\AkangVoiceInput.Windows.sln
dotnet build .\AkangVoiceInput.Windows.sln -c Debug
dotnet test .\AkangVoiceInput.Windows.sln -c Debug --no-build
dotnet run --project .\src\AkangVoiceInput.App\AkangVoiceInput.App.csproj
```

Ideas are welcome as Pull Requests. Before submitting, run the relevant tests and check code quality and privacy. Valuable merged improvements will be credited in the release notes.

### 3. Use it as building blocks for AI-assisted customization

For a specific idea, provide any file or folder from the project to an AI assistant and extend the existing structure. For example:

- Give `Sources/AkangVoiceInput/` and `README.md` to an AI assistant and ask it to add a writing style or a new model provider.
- Ask it to read the product documentation under `docs/product/` before adding a setting toggle.
- Provide a file path, a screenshot, and a concrete goal, then ask for a reviewable implementation plan.

The project is fully open source and is intended as a place to experiment with models, shortcuts, prompts, and local workflows. Please protect your API Key and share general-purpose improvements through Pull Requests.

## Model, cost, and privacy

- You need to configure your own Alibaba Cloud Model Studio or Doubao API Key. A Workspace ID is not required for normal Alibaba setup.
- Usage metrics can be filtered globally by provider. Token usage and local cost estimates are available only when the selected model returns compatible usage data. Doubao Streaming ASR 2.0 and Fun ASR do not return a compatible Token total, so the app shows **Not Supported** instead of a misleading zero.
- Account balance is provider-owned and is not queried by the app. Free quotas, promotions, and final billing are determined by the provider console.
- API Keys are stored only in macOS Keychain, never in source code or project files.
- Audio is sent in real time to the model service configured by the user. The app does not keep local recordings.
- Diagnostic reports exclude keys, Workspace IDs, audio, and transcription text.

For details, see [Privacy and security](docs/privacy-and-security.en.md).

## Build together

The project currently ships native macOS and Windows clients. Their UI, writing
styles, model integrations, and local-data behavior share product concepts, while
shortcuts, audio capture, floating panels, credential storage, and text insertion
remain native to each operating system. Mobile and shared-core work are still
future directions and should not be copied mechanically from either desktop client.

The [future collaboration roadmap](docs/future-roadmap.md) lists directions under evaluation and good first contributions. If you know Windows global shortcuts, mobile input, cross-platform architecture, or model integration, please open an Issue to discuss the approach before implementing it.

## Contributing

Especially welcome: more real-time models, shortcuts and macOS input-method compatibility, insertion into complex controls, additional writing styles, and improved dialect support.

Please contribute through Issues or Pull Requests. This project uses the [MIT License](LICENSE), so you are free to study, adapt, and redistribute it.

If this tool saves you even a little typing, a GitHub Star would mean a lot. It helps show that this experiment—born from unused daily Codex allowance—is useful to someone else as well.

## Follow the author

Scan the QR code to follow the WeChat public account **阿康AI探索号**, where I share AI tools, product tests, development notes, and lessons learned.

<img src="Resources/OfficialAccountQR.jpg" width="160" alt="阿康AI探索号 WeChat QR code" />

## Known limitations

- `Fn` can conflict with macOS input-method switching; configurable modifier-key shortcuts are recommended.
- Some custom-drawn input controls do not support direct Accessibility insertion. In those cases, the result is copied to the clipboard.
- The default integration currently targets the Alibaba Cloud Model Studio Realtime service in China North 2 (Beijing).

For the complete issue list and technical background, see [Known issues](docs/known-issues.en.md).
