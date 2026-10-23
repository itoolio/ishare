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

<table>
  <tr>
    <td><img src="website/public/screenshots/02_editor.jpg" alt="Editor"></td>
    <td><img src="website/public/screenshots/05_recording.jpg" alt="Recording settings"></td>
  </tr>
  <tr>
    <td><img src="website/public/screenshots/03_uploaders.jpg" alt="Uploaders"></td>
    <td><img src="website/public/screenshots/06_history.jpg" alt="History"></td>
  </tr>
</table>

## Features

- **Capture**: regions with a pixel magnifier, coordinates, colors and a measuring tool, windows with or without shadows, whole displays, your last region and scrolling pages, all through ScreenCaptureKit. Optional gradient backgrounds for window captures, privacy blur for chosen apps, text recognition, QR links, self-timer, interval capture and per-app profiles.
- **Record**: displays, windows or a region you draw, as video or GIF, with a webcam bubble, click and keystroke overlays, system audio and microphone meters, trimming, chapter markers, on-device captions and exports to MP4, MOV, GIF or audio.
- **Annotate**: arrows in several styles, lines, shapes, highlights, pen, marker, text, speech balloons, numbered steps, emoji and symbol stamps, magnifier, spotlight, blur, pixelate, smart eraser, crop with handles and aspect presets, rotate, flip, zoom and pan, a layers sidebar and templates. Done runs your after-capture actions.
- **Upload**: Imgur, custom HTTP uploaders, ShareX `.sxcu` import and S3-compatible storage (AWS S3, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, MinIO) with expiring links and Keychain-stored secrets. Upload to several destinations, pick one per capture, upload text snippets, watch a folder, retry failed uploads, shorten links and redact sensitive text. Upload presets get their own shortcuts. An Apple Intelligence assistant builds uploaders from a conversation.
- **Automate**: global keyboard shortcuts, Shortcuts actions, a share menu extension, "Upload with ishare" in Finder and drag and drop onto the menu bar icon.
- **Everything else**: a customizable, keyboard-friendly menu with a ⌘K command palette and previews, a Recent Uploads widget, searchable upload history with server-side deletion, settings search and backup, sound options, a welcome guide, AirDrop, Photos, Messages and Mail sharing, 11 languages, and Liquid Glass on macOS 26.

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
  - `release-notes [file]` turns release markdown on stdin into App Store release notes, merging several releases into one set of notes;
  - `release-check [--app ishare.app] [--release-notes file]` checks entitlements against `fastlane/entitlements-allowlist.json`, usage descriptions, the App Review notes in `fastlane/review_notes.txt`, the committed screenshots and the release notes;
  - `app-store-plan --report status.json --releases releases.json` decides whether to wait, submit or report a rejection from `fastlane mac status` and the GitHub releases;
  - `register-bundle-id [identifier...]` registers bundle identifiers with App Store Connect;
  - `merge-translations <base> <incoming> <output>` keeps only new Crowdin translations in a string catalog;
  - `screenshots [locale[:language]...]` renders the App Store screenshots through the `Screenshots` UI test scheme into `fastlane/screenshots` as 2880×1800 JPEGs. Run it on a Mac with a Retina display (the scenes are 1440×900 points) and commit the result, or pass `--ci` to create a 1680×1050 point HiDPI virtual display first (a CI-only helper in `tools/virtualdisplay`); the App Store workflow's "regenerate screenshots" option does that on a runner and commits the checked screenshots, including the website copies, straight to `dev`, so no extra branches are created. Releases upload the committed screenshots, and the App Store workflow replaces them on a version already in review.
- Releases are cut automatically from `main` with semantic-release, so use [Conventional Commits](https://www.conventionalcommits.org). Each release:
  - signs and notarizes the DMG;
  - updates the Sparkle appcast;
  - uploads the App Store build to App Store Connect and runs the release checklist.
- Submitting for review is decoupled from releases: the App Store Sync workflow runs after every release and every three hours. It never interrupts an active review, submits the newest processed release with the combined notes of every release since the live version (superseding an unsubmitted or rejected version), and opens an "App Store rejected <version>" issue when a rejection has no newer release yet; the issue closes itself once that version is approved or superseded.
- Translations are managed on [Crowdin](https://crowdin.com/project/isharemac), and its pull requests are merged automatically.

## Contributors

[![Contributors](https://contrib.rocks/image?repo=itoolio/ishare)](https://github.com/itoolio/ishare/graphs/contributors)

## Credits

- [Inna Strazhnik](https://www.behance.net/strazhnik) for the original app icon

## License

Released under [GPL-3.0](LICENSE) by [@castdrian](https://github.com/castdrian).
