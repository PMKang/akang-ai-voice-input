# Platform parity

Status values: **MVP** is implemented for the first Windows release, **Later** is deliberately deferred, and **macOS only** remains platform-specific.

| Capability | macOS | Windows MVP | Notes |
| --- | --- | --- | --- |
| Global recording toggle | Multiple configurable shortcuts | **MVP** fixed `Ctrl+Alt+Space` | Configurable shortcuts later |
| Tray/menu-bar control | Menu bar extra | **MVP** notification-area icon | Open, start/stop, exit |
| Single instance | Terminates duplicate copies | **MVP** named mutex | Second launch activates existing app where possible |
| Audio | 16 kHz PCM16 mono streaming | **MVP** 16 kHz PCM16 mono streaming | No recordings saved |
| Qwen Realtime | Supported | **MVP** | Fixed model `qwen3.5-omni-flash-realtime` |
| Live transcript preview | Floating panel | **MVP** compact floating window | Snapshot updates are not appended |
| Final text insertion | Accessibility + paste fallback | **MVP** foreground restore + clipboard + `Ctrl+V` | UIPI limitations documented |
| Secure API key | Keychain | **MVP** Windows Credential Manager | Current Windows user |
| Connection test | Supported for active providers | **MVP** Qwen session handshake | Sends no audio |
| History and usage analytics | Local history, charts, token usage | **Later** | No history persistence in MVP |
| Dictionary / hotwords | Local dictionary and provider sync | **Later** | Core prompt remains fixed |
| Expression profiles | Presets and custom prompts | **Later** | MVP uses the default smart prompt |
| Multiple model providers | Qwen, FunASR, Doubao | **Later** | Windows UI exposes only the required Qwen model |
| Update workflow | Sparkle/custom UI | **Later** | Packaging/update channel not in MVP |
| Custom brand and icon themes | Supported | **Later** | Uses Windows-native shell styling first |
| Native IME/TSF integration | Not applicable | **Later** | Explicitly outside MVP scope |
