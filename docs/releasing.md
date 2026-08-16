# Unified macOS and Windows releases

Noboard uses one public product version for both desktop platforms. A GitHub
Release is complete only when it contains both macOS and Windows packages.

## Version policy

- `VERSION` is the single source of truth for the public product version.
- macOS and Windows may be developed and committed independently.
- A platform may have no functional changes in a release, but both clients are
  rebuilt from the same tag and carry the same public version.
- Do not create platform-specific `latest` releases or public version suffixes
  such as `-windows-preview.1`.
- Preview or stability information belongs in the release notes, not in one
  platform's version number.

## Publish a release

1. Merge the intended macOS and Windows changes into `main`.
2. Update `VERSION` once and document platform-specific changes.
3. Verify the Windows tests and the relevant macOS tests.
4. Run the release workflow manually on `main`. This builds and validates both
   packages without publishing a Release:

   ```bash
   gh workflow run release.yml --ref main
   ```

5. Create and push the matching tag, for example:

   ```bash
   git tag -a v1.6.0 -m "Noboard v1.6.0"
   git push origin v1.6.0
   ```

6. The `Release macOS and Windows` workflow builds both native clients.
7. The workflow publishes one GitHub Release only after both builds succeed.

The completed Release contains:

- `Noboard-vX.Y.Z-macos.dmg`
- `Noboard-vX.Y.Z-macos.zip`
- `Noboard-vX.Y.Z-macos.sha256`
- `Noboard-vX.Y.Z-windows-x64.zip`
- `Noboard-vX.Y.Z-windows-x64.zip.sha256`

If either platform fails, fix the failure and rerun the workflow. Do not publish
a partial Release manually.
