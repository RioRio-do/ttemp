# Ttemp

[日本語](README.md)

Press both Shift keys for a scratch note.

- Copies to the clipboard when closed
- Supports text and images
- Restores after relaunch
- 日本語 / English

## Install

[Download Ttemp.dmg](https://github.com/RioRio-do/ttemp/releases/latest/download/Ttemp.dmg), then drag Ttemp to Applications.

Ttemp is self-signed. If macOS blocks the first launch, right-click Ttemp in Applications and choose Open.

## Input Monitoring

It is used only to detect both Shift keys. Events received through Input Monitoring are never stored or sent.
Notes are stored only on your Mac. Ttemp also works from the menu bar without this permission.

## Requirements

- macOS 14 or later
- Build: Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
xcodegen generate
xcodebuild -project Ttemp.xcodeproj -scheme Ttemp -configuration Release build
```

## Release

A push to main runs tests, signs the app, builds the DMG/ZIP/appcast, and creates a GitHub Release.
See [docs/SIGNING.md](docs/SIGNING.md) for keys and verification.

## Docs

- [SPEC.md](SPEC.md) — Specification
- [docs/SIGNING.md](docs/SIGNING.md) — Signing, updates, and releases
