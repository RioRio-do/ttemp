# Ttemp

[日本語](README.md)

Press both Shift keys for a scratch note.

- Copies to the clipboard when closed
- Supports text and images
- Restores after relaunch
- 日本語 / English

## Install

[Download Ttemp.dmg](https://github.com/RioRio-do/ttemp/releases/latest/download/Ttemp.dmg), then drag Ttemp to Applications.

Ttemp is self-signed and not notarized. Download it only from the official GitHub Release.
If macOS blocks the first launch, follow [Apple's guidance](https://support.apple.com/en-us/102445): System Settings → Privacy & Security → Open Anyway.

## Input Monitoring

It is used only to detect both Shift keys. Events received through Input Monitoring are never stored or sent.
Notes are stored only on your Mac. Ttemp also works from the menu bar without this permission.

## Requirements

- macOS 14 or later (Apple Silicon / Intel)
- Build: Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Debug build
```

Debug builds use a separate app ID and note storage.
Verify the release pipeline with a dedicated app ID, disposable keys, and isolated data: `./scripts/test-release.sh`
Check actual menu-bar visibility [separately](docs/SIGNING.md#ローカル検証公開しない).

## Release

A push to main runs tests, signs the app, builds the DMG/ZIP/appcast, and creates a GitHub Release.
Include [short Japanese and English release notes](release-notes/README.md) with your changes. Publishing without new notes is blocked.
See [docs/SIGNING.md](docs/SIGNING.md) for keys and verification.

## Docs

- [SPEC.md](SPEC.md) — Specification
- [docs/SIGNING.md](docs/SIGNING.md) — Signing, updates, and releases
- [SECURITY.md](SECURITY.md) — Private vulnerability reporting

## License

[MIT-0](LICENSE)
