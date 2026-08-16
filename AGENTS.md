# Repository platform boundaries

This repository contains two independently built desktop clients.

## macOS ownership

The existing macOS Swift package remains rooted at the repository root:

- `Package.swift`
- `Sources/`
- root `Tests/`
- macOS build, packaging, and release scripts

Do not move or modify these paths while doing Windows-only work unless the task explicitly requests a cross-platform change.

## Windows ownership

All Windows implementation, projects, tests, packaging scripts, and Windows-specific documentation belong under `windows/`.

Windows-only work must not add .NET files to the repository root, `Sources/`, or root `Tests/`. The Windows solution must continue to build independently from `windows/AkangVoiceInput.Windows.sln`.

## Shared documentation

Shared platform comparisons and repository-organization documents may live under `docs/`. Prefer new platform-specific documents over rewriting macOS documentation during Windows-only work.

Before publishing platform work, verify the other platform's source roots are unchanged.
