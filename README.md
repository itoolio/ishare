<p align="center">
  <img src="website/public/icon.png" alt="ishare" width="128">
</p>

<h1 align="center">ishare</h1>

<p align="center">The definitive screen capture utility for macOS, designed with simplicity and efficiency in mind.</p>

<p align="center">
  <a href="https://ishare.itoolio.dev">Website</a> ·
  <a href="https://apps.apple.com/app/ishare-screen-capture/id6499066314">Mac App Store</a> ·
  <a href="https://github.com/itoolio/ishare/releases/latest/download/ishare.dmg">Download DMG</a> ·
  <a href="https://crowdin.com/project/isharemac">Translate</a> ·
  <a href="https://discord.gg/sX4KYzu5pX">Discord</a>
</p>

<p align="center">
  <a href="https://github.com/itoolio/ishare/actions/workflows/release.yml"><img src="https://github.com/itoolio/ishare/actions/workflows/release.yml/badge.svg" alt="Release"></a>
  <a href="https://github.com/itoolio/ishare/releases"><img src="https://img.shields.io/github/v/release/itoolio/ishare?sort=semver&color=8b5cf6" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-8b5cf6" alt="License"></a>
  <a href="https://github.com/sponsors/castdrian"><img src="https://img.shields.io/badge/sponsor-30363D?logo=GitHub-Sponsors&logoColor=white" alt="Sponsor"></a>
</p>

```bash
brew install --cask ishare
```

![ishare](website/public/screenshots/01_menu.jpg)

## Features

- **Capture**: regions with a magnifier, windows with or without shadows, whole displays and scrolling pages, all through ScreenCaptureKit.
- **Record**: displays, windows or a region you draw, at the resolution and frame rate you choose, as video or GIF.
- **Annotate**: arrows, lines, shapes, highlights, pen, marker, text, speech balloons, numbered steps, magnifier, spotlight, blur, pixelate, smart eraser, cursor stamps, crop, rotate and flip.
- **Upload**: Imgur, custom HTTP uploaders and S3-compatible storage (AWS S3, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, MinIO), with an Apple Intelligence assistant that builds uploaders for you.
- **Automate**: global keyboard shortcuts, Shortcuts actions and a share menu extension.
- **Everything else**: upload history, AirDrop, Photos, Messages and Mail sharing, 11 languages, and Liquid Glass on macOS 26.

## Custom uploaders

ishare imports `.iscu` files: JSON documents that describe an HTTP or S3 uploader. The full specification is on the [website](https://ishare.itoolio.dev/docs/iscu/), and ready-made uploaders for chibisafe, copyparty, Discord webhooks, lumen, Zipline and S3 are in [examples](examples).

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open ishare.xcodeproj
```

- The `ishare` scheme builds the sandboxed App Store app, and the `GitHub` scheme builds the direct download app with Sparkle and runs the unit tests.
- The `UITests` scheme runs the menu and editor UI tests against a deterministic test mode of the app.
- Release and maintenance tasks live in one Go CLI, `go run ./tools/cmd/ishare-tools <command>`:
  - `set-version <version>` writes the marketing version and build number to `Config.xcconfig`;
  - `release-notes [file]` turns release markdown on stdin into App Store release notes;
  - `register-bundle-id [identifier...]` registers bundle identifiers with App Store Connect;
  - `merge-translations <base> <incoming> <output>` keeps only new Crowdin translations in a string catalog;
  - `screenshots [locale[:language]...]` renders the App Store screenshots through the `Screenshots` UI test scheme into `fastlane/screenshots`.
- Releases are cut automatically from `main` with semantic-release, so use [Conventional Commits](https://www.conventionalcommits.org). Each release:
  - signs and notarizes the DMG;
  - updates the Sparkle appcast;
  - uploads the App Store build, metadata, screenshots and release notes, and submits it for review.
- Translations are managed on [Crowdin](https://crowdin.com/project/isharemac), and its pull requests are merged automatically.

## Contributors

[![Contributors](https://contrib.rocks/image?repo=itoolio/ishare)](https://github.com/itoolio/ishare/graphs/contributors)

## Credits

- [Inna Strazhnik](https://www.behance.net/strazhnik) for the original app icon

## License

Released under [GPL-3.0](LICENSE) by [@castdrian](https://github.com/castdrian).
