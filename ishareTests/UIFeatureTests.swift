import AppKit
import Foundation
import Testing
@testable import ishare

struct ThumbnailKeyTests {
    @Test func bucketsPixelSizes() {
        #expect(ThumbnailKey.bucket(for: 1) == 64)
        #expect(ThumbnailKey.bucket(for: 64) == 64)
        #expect(ThumbnailKey.bucket(for: 65) == 128)
        #expect(ThumbnailKey.bucket(for: 440) == 512)
        #expect(ThumbnailKey.bucket(for: 5000) == 1024)
    }

    @Test func prefersTheLocalFileWhenItExists() {
        let item = HistoryItem(fileUrl: "https://cdn.example.com/a.png", localPath: "/tmp/shots/../shots/a.png")
        let key = ThumbnailKey.forItem(item, pointSize: 44, fileExists: { _ in true })
        #expect(key?.source == .file("/tmp/shots/a.png"))
        #expect(key?.pixelSize == 128)
        #expect(key?.cacheKey == "file:/tmp/shots/a.png@128")
    }

    @Test func fallsBackToTheRemoteURLWhenTheLocalFileIsGone() {
        let item = HistoryItem(fileUrl: "https://cdn.example.com/a.png", localPath: "/tmp/missing.png")
        let key = ThumbnailKey.forItem(item, pointSize: 160, fileExists: { _ in false })
        #expect(key?.source == .remote(URL(string: "https://cdn.example.com/a.png")!))
        #expect(key?.cacheKey == "remote:https://cdn.example.com/a.png@512")
    }

    @Test func skipsRemoteVideosAndNonHTTPURLs() {
        #expect(ThumbnailKey.forItem(HistoryItem(fileUrl: "https://cdn.example.com/a.mp4"), pointSize: 44, fileExists: { _ in false }) == nil)
        #expect(ThumbnailKey.forItem(HistoryItem(fileUrl: "ftp://cdn.example.com/a.png"), pointSize: 44, fileExists: { _ in false }) == nil)
        #expect(ThumbnailKey.forItem(HistoryItem(), pointSize: 44) == nil)
        let localVideo = HistoryItem(fileUrl: "https://cdn.example.com/a.mp4", localPath: "/tmp/a.mp4")
        #expect(ThumbnailKey.forItem(localVideo, pointSize: 44, fileExists: { _ in true })?.source == .file("/tmp/a.mp4"))
    }

    @Test func sharesKeysAcrossSizesInTheSameBucket() {
        let url = URL(fileURLWithPath: "/tmp/a.png")
        #expect(ThumbnailKey.forFile(url, pointSize: 40) == ThumbnailKey.forFile(url, pointSize: 64))
        #expect(ThumbnailKey.forFile(url, pointSize: 40) != ThumbnailKey.forFile(url, pointSize: 200))
        #expect(ThumbnailKey.forFile(url, pointSize: 40) != ThumbnailKey.forFile(URL(fileURLWithPath: "/tmp/b.png"), pointSize: 40))
    }

    @Test @MainActor func cachesGeneratedThumbnails() async throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 300, height: 200), hue: 0.4, title: "Cache"))
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try ImageEncoder.write(image, as: .PNG, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ThumbnailCache()
        let key = ThumbnailKey.forFile(url, pointSize: 32)
        #expect(cache.cachedImage(for: key) == nil)
        let generated = try #require(await cache.image(for: key))
        #expect(max(generated.size.width, generated.size.height) <= 64)
        #expect(cache.cachedImage(for: key) === generated)
        cache.removeAll()
        #expect(cache.cachedImage(for: key) == nil)
    }
}

struct UploadTrackerTests {
    let first = HistoryItem(fileUrl: "https://example.com/1.png")
    let second = HistoryItem(fileUrl: "https://example.com/2.png")
    let third = HistoryItem(fileUrl: "https://example.com/3.png")

    @Test func detectsSuccessFromANewHistoryItem() {
        var tracker = UploadTracker()
        tracker.begin(newestHistoryItem: first)
        #expect(tracker.isActive)
        tracker.update(progress: 1.4)
        #expect(tracker.activity == .uploading(progress: 1))
        let completion1 = tracker.complete(newestHistoryItem: second)
        #expect(completion1 == true)
        #expect(!tracker.isActive)
    }

    @Test func treatsAnUnchangedHistoryAsFailure() {
        var tracker = UploadTracker()
        tracker.begin(newestHistoryItem: first)
        let completion2 = tracker.complete(newestHistoryItem: first)
        #expect(completion2 == false)
        tracker.begin(newestHistoryItem: nil)
        let completion3 = tracker.complete(newestHistoryItem: nil)
        #expect(completion3 == false)
    }

    @Test func attributesConcurrentUploadsOnce() {
        var tracker = UploadTracker()
        tracker.begin(newestHistoryItem: first)
        tracker.begin(newestHistoryItem: first)
        let completion4 = tracker.complete(newestHistoryItem: second)
        #expect(completion4 == true)
        #expect(tracker.isActive)
        let completion5 = tracker.complete(newestHistoryItem: second)
        #expect(completion5 == false)
        tracker.begin(newestHistoryItem: second)
        #expect(tracker.activity == .uploading(progress: 0))
        let completion6 = tracker.complete(newestHistoryItem: third)
        #expect(completion6 == true)
    }
}

struct MenuFocusNavigatorTests {
    let rows: [[MenuFocusTarget]] = [
        [.destination, .settings],
        [.capture(0), .capture(1), .capture(2), .capture(3)],
        [.record(0), .record(1)],
        [.footer(0), .footer(1)],
    ]

    @Test func startsOnTheFirstCaptureTile() {
        #expect(MenuFocusNavigator.move(from: nil, .down, in: rows) == .capture(0))
        #expect(MenuFocusNavigator.move(from: .chip(4), .left, in: rows) == .capture(0))
        #expect(MenuFocusNavigator.move(from: nil, .down, in: [[.footer(0)]]) == .footer(0))
        #expect(MenuFocusNavigator.move(from: nil, .down, in: []) == nil)
    }

    @Test func movesWithinARowAndClampsAtTheEdges() {
        #expect(MenuFocusNavigator.move(from: .capture(1), .right, in: rows) == .capture(2))
        #expect(MenuFocusNavigator.move(from: .capture(3), .right, in: rows) == .capture(3))
        #expect(MenuFocusNavigator.move(from: .capture(0), .left, in: rows) == .capture(0))
    }

    @Test func movesBetweenRowsKeepingTheHorizontalPosition() {
        #expect(MenuFocusNavigator.move(from: .capture(3), .down, in: rows) == .record(1))
        #expect(MenuFocusNavigator.move(from: .capture(1), .down, in: rows) == .record(0))
        #expect(MenuFocusNavigator.move(from: .record(1), .up, in: rows) == .capture(3))
        #expect(MenuFocusNavigator.move(from: .settings, .down, in: rows) == .capture(3))
        #expect(MenuFocusNavigator.move(from: .destination, .up, in: rows) == .destination)
        #expect(MenuFocusNavigator.move(from: .footer(1), .down, in: rows) == .footer(1))
    }

    @Test func mapsNumberKeysToCaptureTiles() {
        #expect(MenuFocusNavigator.captureIndex(forKey: "1") == 0)
        #expect(MenuFocusNavigator.captureIndex(forKey: "4") == 3)
        #expect(MenuFocusNavigator.captureIndex(forKey: "5") == nil)
        #expect(MenuFocusNavigator.captureIndex(forKey: "0") == nil)
        #expect(MenuFocusNavigator.captureIndex(forKey: "a") == nil)
    }

    @Test func flipsDirectionsForTheRotatedMenu() {
        #expect(MenuFocusDirection.up.flipped == .down)
        #expect(MenuFocusDirection.left.flipped == .right)
    }
}

@MainActor
struct SettingsSearchTests {
    @Test func listsEveryPaneWithoutAQuery() {
        #expect(SettingsSearchIndex.matches(for: "  ").map(\.pane) == SettingsPane.allCases)
    }

    @Test func matchesPaneTitlesAndKeywords() {
        #expect(SettingsSearchIndex.matches(for: "uploaders", localize: { $0 }) == [SettingsSearchMatch(pane: .uploaders, keyword: nil)])
        #expect(SettingsSearchIndex.matches(for: "hevc", localize: { $0 }) == [SettingsSearchMatch(pane: .recording, keyword: "HEVC")])
        #expect(SettingsSearchIndex.matches(for: "Toast", localize: { $0 }).first?.pane == .general)
        #expect(SettingsSearchIndex.matches(for: "Capture Region", localize: { $0 }).map(\.pane).contains(.keybinds))
        #expect(SettingsSearchIndex.matches(for: "zzzz", localize: { $0 }).isEmpty)
    }

    @Test func ignoresCaseDiacriticsAndTrailingColons() {
        #expect(SettingsSearchIndex.matches(for: "MAGNÏFIER", localize: { $0 }).map(\.pane) == [.capture])
        #expect(SettingsSearchIndex.matches(for: "client id:", localize: { $0 }).map(\.pane) == [.advanced])
    }

    @Test func searchesLocalizedKeywords() {
        let entries = [SettingsSearchEntry(pane: .general, keywords: ["Sounds"])]
        let matches = SettingsSearchIndex.matches(for: "klänge", entries: entries, localize: { $0 == "Sounds" ? "Klänge" : $0 })
        #expect(matches == [SettingsSearchMatch(pane: .general, keyword: "Sounds")])
    }

    @Test func extendsWithExtraEntries() {
        let entries = SettingsSearchIndex.entries + [SettingsSearchEntry(pane: .advanced, keywords: ["Telemetry"])]
        #expect(SettingsSearchIndex.matches(for: "telemetry", entries: entries, localize: { $0 }).map(\.pane) == [.advanced])
    }
}

struct OnboardingTests {
    @Test func presentsOnlyOnTheFirstRegularLaunch() {
        #expect(Onboarding.shouldPresent(hasCompleted: false, screenshotMode: false, arguments: []))
        #expect(!Onboarding.shouldPresent(hasCompleted: true, screenshotMode: false, arguments: []))
        #expect(!Onboarding.shouldPresent(hasCompleted: false, screenshotMode: true, arguments: []))
        #expect(!Onboarding.shouldPresent(hasCompleted: false, screenshotMode: false, arguments: ["ishare", "-ishareSkipOnboarding"]))
        #expect(!Onboarding.shouldPresent(hasCompleted: false, screenshotMode: false, arguments: [], environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
    }

    @Test func walksThroughAllSteps() {
        #expect(OnboardingStep.allCases == [.permission, .uploader, .shortcuts, .tryCapture, .tryEditor, .tryPalette, .afterCapture])
    }
}

struct SoundPlayerTests {
    @Test func listsSoundFilesSortedWithoutExtensions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["Pop.aiff", "Glass.aiff", "Basso.caf", "notes.txt", "Glass.wav"] {
            try Data().write(to: directory.appending(path: name))
        }
        #expect(SoundPlayer.soundNames(in: directory) == ["Basso", "Glass", "Pop"])
    }

    @Test @MainActor func offersNoneAndBeepBeforeSystemSounds() {
        let choices = SoundPlayer.choices
        #expect(Array(choices.prefix(2)) == [.none, .beep])
        #expect(choices.dropFirst(2).allSatisfy { if case .system = $0 { true } else { false } })
    }

    @Test func roundTripsThroughCodable() throws {
        for choice in [SoundChoice.none, .beep, .system("Glass")] {
            let data = try JSONEncoder().encode(choice)
            #expect(try JSONDecoder().decode(SoundChoice.self, from: data) == choice)
        }
    }
}

struct ExternalUploadTests {
    @Test func keepsOnlyExistingRegularFiles() throws {
        let file = try Fixtures.temporaryFile(named: "drop.png", contents: Data([1, 2, 3]))
        let directory = file.deletingLastPathComponent()
        let missing = directory.appending(path: "missing.png")
        let web = URL(string: "https://example.com/a.png")!
        #expect(ExternalUpload.uploadableFiles([file, directory, missing, web]) == [file])
    }

    @Test func readsFileURLsFromThePasteboard() throws {
        let file = try Fixtures.temporaryFile(named: "service.png", contents: Data([1, 2, 3]))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ishare.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        #expect(ExternalUpload.payload(from: pasteboard) == .files([file]))
    }

    @Test func readsImageDataFromThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ishare.tests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.setData(png, forType: .png)
        #expect(ExternalUpload.payload(from: pasteboard) == .imageData(png))
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        #expect(ExternalUpload.payload(from: pasteboard) == nil)
    }
}

@MainActor
struct ToastLayoutTests {
    @Test func stacksToastsFromTheTopRightCorner() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frames = ToastController.targetFrames(for: [96, 120], in: screen)
        #expect(frames.count == 2)
        #expect(frames[0] == CGRect(x: 1440 - ToastCardView.width - 16, y: 900 - 16 - 96, width: ToastCardView.width, height: 96))
        #expect(frames[1].maxY == frames[0].minY - ToastController.spacing)
        #expect(frames[1].height == 120)
    }

    @Test func resolvesTheUploadStateOfAModel() {
        let model = ToastModel(fileURL: URL(fileURLWithPath: "/tmp/a.png"), isImage: true)
        #expect(model.uploadState == .none)
        #expect(model.kind == .image)
        let uploaded = ToastModel(fileURL: URL(fileURLWithPath: "/tmp/a.mov"), isImage: false, historyItem: HistoryItem(fileUrl: "https://example.com/a.mov"))
        #expect(uploaded.uploadState == .uploaded)
        #expect(uploaded.kind == .video)
    }
}
