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

ishare 5.3 and later require a Mac with Apple silicon running macOS 15 or later. Intel Macs stay on 5.2.1, and the update feed only offers newer versions to Apple silicon Macs.

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
- **Upload**: Imgur, custom HTTP uploaders with optional password-protected and expiring links, ShareX `.sxcu` import, S3-compatible storage (AWS S3, Cloudflare R2, DigitalOcean Spaces, Backblaze B2, MinIO) with expiring links and Keychain-stored secrets, and local destinations: a folder, iCloud Drive or a Photos album. Upload to several destinations, pick one per capture, upload text snippets, watch a folder, retry failed uploads, shorten links, rewrite them to a CDN host, reuse the link of a file you already uploaded, delete uploads from the server after a number of days, get warned when your default uploader stops working, and redact sensitive text. Upload presets get their own shortcuts. An Apple Intelligence assistant builds uploaders from a conversation.
- **Automate**: global keyboard shortcuts, Shortcuts actions, an `ishare` command-line tool with JSON output, `ishare://` URL actions with x-callback-url support, a [Raycast extension](integrations/raycast), a share menu extension, "Upload with ishare" in Finder and drag and drop onto the menu bar icon.
- **Share nearby**: QR codes for every link, and temporary links on your local network that devices on the same Wi-Fi can open without any uploader.
- **Everything else**: a customizable, keyboard-friendly menu with a ⌘K command palette and previews, a Recent Uploads widget, searchable upload history with server-side deletion, settings search and backup, sound options, a welcome guide, AirDrop, Photos, Messages and Mail sharing, 11 languages, and Liquid Glass on macOS 26.

## Custom uploaders

ishare imports `.iscu` files: JSON documents that describe an HTTP, S3, WebDAV, SFTP, Dropbox, Google Drive, OneDrive or GitHub uploader, or a local destination such as a folder, iCloud Drive or a Photos album. HTTP uploaders can declare `linkOptions` so you can protect each link with a password or let it expire. Any uploader can rewrite its links with `linkRewrite` and delete uploads after a number of days with `autoDeleteAfterDays`. The full specification is on the [website](https://ishare.itoolio.dev/docs/iscu/), and ready-made uploaders for chibisafe, copyparty, Discord webhooks, lumen, Zipline (also with password and expiry headers), S3, WebDAV, SFTP, Dropbox, Google Drive, OneDrive, GitHub, a folder and Photos are in [examples](examples).

## Command line and URL actions

Install the bundled command-line tool from **Settings → Advanced → Command-Line Tool**, then:

```bash
ishare upload ~/Desktop/diagram.png
ishare upload ~/Desktop/diagram.png --reuse
ishare capture region --upload --json
ishare record start
ishare uploaders list
ishare history --limit 10 --json
```

Apps and scripts can also open `ishare://capture/region`, `ishare://record/toggle`, `ishare://upload?path=…`, `ishare://uploader/select?name=…` and `ishare://open/history`, with optional `x-success` and `x-error` callbacks. The full reference is on the [website](https://ishare.itoolio.dev/docs/automation/).

## Verifying downloads

Every release carries a signed build provenance attestation for `ishare.dmg`, the dSYM zips and a software bill of materials, `ishare-<version>-sbom.spdx.json`, which lists every Swift package the app was built with, the local `ishareCore` package and the Go modules of the release tooling in SPDX 2.3 format. Verify a download with the [GitHub CLI](https://cli.github.com):

```bash
gh attestation verify ishare.dmg --repo itoolio/ishare
gh attestation verify ishare-<version>-sbom.spdx.json --repo itoolio/ishare
```

The command checks that the file was built by this repository's release workflow from the tagged commit; it fails for files that were modified or built anywhere else.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open ishare.xcodeproj
```

- The `ishare` scheme builds the sandboxed App Store app, and the `GitHub` scheme builds the direct download app with Sparkle and runs the unit tests.
- Pure ISCU decoding, request building and capture math live in the local `ishareCore` Swift package in `Packages/ishareCore`; run its tests without launching the app with `swift test --package-path Packages/ishareCore`.
- Swift sources are formatted with `swift format` and the `.swift-format` configuration; run `git config core.hooksPath scripts/hooks` once to lint staged Swift files before every commit.
- The `UITests` scheme runs the menu, editor and upload flow UI tests against a deterministic test mode of the app; the upload flow captures a generated fixture image (`-ishareUITestCaptureSource fixture`, no screen recording permission needed), uploads it to a stub HTTP server the test starts on `127.0.0.1` and checks the toast, the clipboard and the history.
- Snapshot tests compare the menu, toast, editor toolbar and General settings with references in `ishareTests/Snapshots/macOS<major>/` and skip on macOS versions without references. Run the Snapshots workflow manually to render the references on the macOS runner and commit them straight to `dev`.
- Built-in sign-in for Dropbox, Google Drive and OneDrive needs one app registration per provider. Paste the client IDs into `Config.xcconfig` (`DROPBOX_CLIENT_ID`, `GOOGLE_CLIENT_ID`, `ONEDRIVE_CLIENT_ID`); `project.yml` applies it to the Debug and Release configurations and both `ishare/Info.plist` and `ishare/Info-GitHub.plist` expand them into `ISHAREDropboxClientID`, `ISHAREGoogleClientID` and `ISHAREOneDriveClientID`. A provider with a client ID appears directly in **Settings → Uploaders → Create**, the others stay under "With your own app". None of the apps uses a client secret; every sign-in uses PKCE and `ASWebAuthenticationSession`, so no URL scheme has to be added to the Info.plist.
  - **Dropbox** ([App Console](https://www.dropbox.com/developers/apps)): create a "Scoped access" app with "App folder" or "Full Dropbox" access. On **Settings**, add the redirect URI `ishare-oauth://dropbox` and set "Allow public clients (Implicit Grant & PKCE)" to Allow. On **Permissions**, enable `account_info.read`, `files.content.write`, `files.content.read`, `sharing.write` and `sharing.read` and submit. The App key goes into `DROPBOX_CLIENT_ID`. ishare asks for `token_access_type=offline` to get a refresh token. Apply for production status before shipping, because development apps are limited to 500 users.
  - **Google Drive** ([Google Cloud console](https://console.cloud.google.com/apis/credentials)): enable the Google Drive API, configure the OAuth consent screen with the `https://www.googleapis.com/auth/drive.file` scope (a non-sensitive scope, so no verification audit is needed), then create an OAuth client ID of type **iOS** (Google's type for native Apple apps, including macOS) with the bundle ID `dev.adrian.ishare`; if its advanced settings offer "Enable custom URI scheme", turn it on. The redirect URI is the reversed client ID, `com.googleusercontent.apps.<CLIENT_ID_PREFIX>:/oauth2redirect`; it needs no registration. Put the full client ID (`<CLIENT_ID_PREFIX>.apps.googleusercontent.com`) into `GOOGLE_CLIENT_ID`. Don't use the "Desktop app" type: it only allows loopback redirects, which would need a local server. ishare sends `access_type=offline` and `prompt=consent` to get a refresh token.
  - **OneDrive** ([Microsoft Entra admin center](https://entra.microsoft.com) → App registrations): register an app for "Accounts in any organizational directory and personal Microsoft accounts", because ishare signs in through the `/common` endpoint so that personal OneDrive and OneDrive for Business both work. Under **Authentication**, add the "Mobile and desktop applications" platform with the custom redirect URI `ishare-oauth://onedrive`. Under **API permissions**, add the delegated Microsoft Graph permissions `Files.ReadWrite`, `User.Read` and `offline_access`. The Application (client) ID goes into `ONEDRIVE_CLIENT_ID`.
  - `OAuthRegistrationTests` checks the exact authorize URLs ishare builds for each provider and that the client IDs reach the built Info.plist.
- The S3 integration tests in `ishareTests/S3IntegrationTests.swift` run only when `ISHARE_S3_ENDPOINT` is set. Start a local MinIO server (`brew install minio && MINIO_DOMAIN=localhost minio server /tmp/minio --address "[::]:9000"`) and run `TEST_RUNNER_ISHARE_S3_ENDPOINT=http://127.0.0.1:9000 xcodebuild test -scheme GitHub -destination platform=macOS,arch=arm64 -only-testing:ishareTests/NetworkSuite`; set `TEST_RUNNER_ISHARE_S3_VIRTUAL_HOST_ENDPOINT=http://localhost:9000` to cover virtual-hosted URLs; macOS resolves every `*.localhost` bucket name to loopback, and App Transport Security allows plain HTTP to it. The `s3-integration` CI job does this on every pull request. The S3, WebDAV and SFTP integration tests also upload a file, let it expire and check that the auto-delete runner removes it from the server.
- Release and maintenance tasks live in one Go CLI, `go run ./tools/cmd/ishare-tools <command>`:
  - `set-version <version>` writes the marketing version and build number to `Config.xcconfig`;
  - `release-notes [file]` turns release markdown on stdin into App Store release notes, merging several releases into one set of notes;
  - `release-check [--app ishare.app] [--release-notes file]` checks entitlements against `fastlane/entitlements-allowlist.json`, usage descriptions, the App Review notes in `fastlane/review_notes.txt`, the committed screenshots of every locale, the localized metadata and the release notes;
  - `metadata [--check]` renders the App Store listing (name, subtitle, keywords, promotional text, description and release notes) of every supported locale into `fastlane/metadata/<locale>/` from the `fastlane/metadata/Metadata.xcstrings` catalog, checking the App Store limits; release notes get localized section headings and keep English entries unless the catalog has a translation for them. Edit the English listing in the catalog, not in `fastlane/metadata/en-US`, and rerun the command;
  - `app-store-plan --report status.json --releases releases.json` decides whether to wait, submit or report a rejection from `fastlane mac status` and the GitHub releases;
  - `register-bundle-id [identifier...]` registers bundle identifiers with App Store Connect;
  - `merge-translations <base> <incoming> <output>` keeps only new Crowdin translations in a string catalog;
  - `symbolicate <crash.ips|report.crash> --dsyms <ishare-<version>-dSYMs.zip>` symbolicates a crash report from a user: it reads the binary images and frames of an `.ips` (JSON) or legacy `.crash` report, matches the image UUIDs against the dSYMs from `dwarfdump --uuid`, and resolves every frame of ishare, its widgets and its share extension with `atos`. Download the dSYM zip attached to the matching GitHub release (`ishare-<version>-dSYMs.zip` for the direct download, `ishare-<version>-AppStore-dSYMs.zip` for the App Store build), or pass a folder of `.dSYM` bundles, and add `--output file` to write the result to a file;
  - `package-dsyms <archive.xcarchive> <output.zip>` checks that an archive contains the dSYMs of the app, the widgets and the share extension with UUIDs that match the archived binaries, and zips them for the release;
  - `sbom --version <version> --package-resolved <Package.resolved> --package-dir Packages/ishareCore --go-mod tools/go.mod --output <file>` writes a deterministic SPDX 2.3 SBOM of the resolved Swift packages, the local package and the Go modules; `SOURCE_DATE_EPOCH` or `--created` sets its timestamp;
  - `docc-symbols <derived-data> <output>` reduces the app's symbol graph to the types the DocC catalog documents (the `Uploader` protocol, its conformances and the upload model), so the published documentation stays small;
  - `coverage [--min Area=percent]... <xccov.json>` turns `xcrun xccov view --report --json` output into a Markdown summary per area (Capture, Recording, Http, ISCU, Editor, Views, Util and so on), writes it to the job summary and fails when an area falls below its minimum. The `app` CI job enforces minimums for the capture, upload and ISCU code, and the Coverage Comment workflow posts the summary as a single, updated comment on pull requests;
  - `screenshots [all | locale[:language]...]` renders the App Store screenshots through the `Screenshots` UI test scheme into `fastlane/screenshots` as 2880×1800 JPEGs. Run it on a Mac with a Retina display (the scenes are 1440×900 points) and commit the result, or pass `--ci` to create a 1680×1050 point HiDPI virtual display first (a CI-only helper in `tools/virtualdisplay`); the App Store workflow's "regenerate screenshots" option does that on a runner and commits the checked screenshots, including the website copies, straight to `dev`, so no extra branches are created. Releases upload the committed screenshots, and the App Store workflow replaces them on a version already in review.
  - `guide-clips [--ci] [all | capture editor region shelf]` records the short clips of the [feature guide](https://ishare.itoolio.dev/guide/) through the `GuideClipTests` UI test: screenshot mode plays a scripted scene frame by frame, the test encodes the window into an H.264 MP4 with a poster frame, and the tool copies them to `website/public/guide`. The Feature guide workflow runs it on the virtual display after every release or on demand and commits the clips to `dev`;
  - `automation --app <ishare.app>` launches a build with `-ishareAutomationTestMode YES`, which swaps in a fixture capture source, a stubbed recorder and a local folder uploader, then runs every `ishare://` action through `open` and every command of the bundled `Contents/Helpers/ishare` with a timeout each, checking the reply files and the `--json` output. The `automation` CI job builds with `-DAUTOMATION_TESTS`, which lets the command-line tool read its mailbox from `ISHARE_AUTOMATION_MAILBOX`;
- Releases are cut automatically from `main` with semantic-release, so use [Conventional Commits](https://www.conventionalcommits.org). Each release:
  - signs and notarizes the DMG;
  - attaches the dSYMs of the direct download and the App Store build to the GitHub release as `ishare-<version>-dSYMs.zip` and `ishare-<version>-AppStore-dSYMs.zip` (the App Store export also uploads its symbols to App Store Connect);
  - attaches the SBOM `ishare-<version>-sbom.spdx.json` and attests the build provenance of the DMG, both dSYM zips and the SBOM;
  - updates the Sparkle appcast;
  - uploads the App Store build to App Store Connect and runs the release checklist.
- Submitting for review is decoupled from releases: the App Store Sync workflow runs after every release and every three hours. It always submits the newest processed release with the combined notes of every release since the live version, superseding an unsubmitted, rejected or still queued version (a submission waiting for review is withdrawn first, and kept until the newer build has finished processing); reviews that have started and approved versions awaiting release are never interrupted, and the job summary notes the pending release instead. It opens an "App Store rejected <version>" issue when a rejection has no newer release yet; the issue closes itself once that version is approved or superseded.
- Dependabot opens weekly, grouped pull requests against `dev` for GitHub Actions, the Go tools, the website and fastlane; minor and patch updates are squash-merged automatically once the required checks pass. Swift packages are declared in `project.yml` with up-to-next-major requirements and no committed `Package.resolved`, so every build already resolves their newest minor and patch versions; major versions are raised in `project.yml` by hand.
- The developer documentation is a DocC catalog in `ishare/ishare.docc` with articles about the ISCU format and the `Uploader` protocol. The Website workflow builds it and publishes it at [/docs/documentation/ishare/](https://ishare.itoolio.dev/docs/documentation/ishare/); to build it locally, build the app with `xcodebuild build -scheme GitHub -destination generic/platform=macOS -derivedDataPath build/docs CODE_SIGNING_ALLOWED=NO "OTHER_SWIFT_FLAGS=\$(inherited) -emit-symbol-graph -emit-symbol-graph-dir $PWD/build/raw-symbol-graphs -symbol-graph-minimum-access-level internal"` (create `build/raw-symbol-graphs` first), keep only the upload types with `go run ./tools/cmd/ishare-tools docc-symbols build/raw-symbol-graphs build/symbol-graphs`, and run `xcrun docc preview ishare/ishare.docc --additional-symbol-graph-dir build/symbol-graphs`. Write documentation in the catalog's articles and extension files, not as comments in the Swift sources.
- Translations of the app (`ishare/Localizable.xcstrings`) and of the App Store listing (`fastlane/metadata/Metadata.xcstrings`) are managed on [Crowdin](https://crowdin.com/project/isharemac). Its pull requests are merged automatically, and every change to either catalog on `main` is uploaded back to Crowdin, sources and translations, by the Crowdin upload workflow.

## Contributors

[![Contributors](https://contrib.rocks/image?repo=itoolio/ishare)](https://github.com/itoolio/ishare/graphs/contributors)

## Credits

- [Inna Strazhnik](https://www.behance.net/strazhnik) for the original app icon

## License

Released under [GPL-3.0](LICENSE) by [@castdrian](https://github.com/castdrian).
