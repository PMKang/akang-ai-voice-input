# Repository layout

The repository preserves the original macOS Swift package at the root and contains the Windows port in one isolated top-level directory.

```text
akang-ai-voice-input/
├── Package.swift                    # macOS package manifest
├── Sources/                         # macOS application sources
├── Tests/                           # macOS tests
├── windows/
│   ├── AkangVoiceInput.Windows.sln  # Windows solution
│   ├── src/                         # Windows application and libraries
│   ├── tests/                       # Windows-only tests
│   ├── scripts/                     # Windows packaging scripts
│   └── README.md                    # Windows build and usage guide
└── docs/                            # shared and platform-specific design docs
```

## Why macOS is not moved into `macos/`

The macOS client predates the Windows port. Moving it would change Swift Package paths, build scripts, documentation links, and release automation without improving runtime isolation. Such a migration should only happen in a dedicated mechanical PR with both platform build pipelines available.

## Change rules

- Windows feature or bug fix: edit `windows/` and, when needed, add a Windows-specific document under `docs/`.
- macOS feature or bug fix: edit the root Swift package paths; do not edit `windows/` unless parity is explicitly requested.
- Shared product behavior: document the intended parity first, then implement each platform in its own source tree.
- Never place generated `bin/`, `obj/`, publish output, API keys, or recordings in Git.
