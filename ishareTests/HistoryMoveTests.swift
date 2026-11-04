import AppKit
import CoreImage
import Defaults
import Foundation
import ImageIO
import ishareCore
import Testing
@testable import ishare

struct HistoryMoveTests {
    let old = HistoryItem(
        fileUrl: "https://old.example/a.png", deletionUrl: "https://old.example/delete/a", localPath: "/tmp/a.png", date: Date(timeIntervalSince1970: 100),
        altText: "A cat", title: "Cat", keepForever: true)

    @Test func replacesTheOldEntryInPlaceAndKeepsItsDetails() throws {
        let newer = HistoryItem(fileUrl: "https://new.example/a.png", date: Date(timeIntervalSince1970: 500))
        let other = HistoryItem(fileUrl: "https://old.example/b.png", date: Date(timeIntervalSince1970: 50))
        let updated = try #require(HistoryMove.replacing(old, withUploadAt: "https://new.example/a.png", in: [newer, old, other]))
        #expect(updated.map(\.fileUrl) == ["https://new.example/a.png", "https://old.example/b.png"])
        #expect(updated[0].date == Date(timeIntervalSince1970: 100))
        #expect(updated[0].title == "Cat")
        #expect(updated[0].altText == "A cat")
        #expect(updated[0].keepForever == true)
        #expect(updated[0].localPath == "/tmp/a.png")
    }

    @Test func leavesHistoryAloneWhenTheNewUploadIsMissing() {
        #expect(HistoryMove.replacing(old, withUploadAt: "https://new.example/a.png", in: [old]) == nil)
        #expect(HistoryMove.replacing(old, withUploadAt: nil, in: [old]) == nil)
    }

    @Test func skipsItemsAlreadyOnTheTargetOrWithoutAFile() {
        let id = UUID()
        let onTarget = HistoryItem(fileUrl: "https://x/a.png", uploaderId: id)
        let noFile = HistoryItem(localPath: "/nonexistent/file.png")
        let movable = HistoryItem(fileUrl: "https://x/b.png")
        #expect(HistoryMove.movable([onTarget, noFile, movable], to: .custom(id)) == [movable])
    }
}

struct UploadProgressHUDLayoutTests {
    @Test func sitsBelowTheMenuBarIcon() {
        let frame = UploadProgressHUDLayout.frame(
            below: CGRect(x: 1000, y: 1050, width: 30, height: 24), on: CGRect(x: 0, y: 0, width: 1440, height: 1080),
            visible: CGRect(x: 0, y: 0, width: 1440, height: 1050))
        #expect(frame.midX == 1015)
        #expect(frame.maxY == 1050 - UploadProgressHUDLayout.gap)
    }

    @Test func staysOnScreenAndFallsBackToTheTopCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 1080)
        let edge = UploadProgressHUDLayout.frame(below: CGRect(x: 1430, y: 1050, width: 10, height: 24), on: screen, visible: screen)
        #expect(edge.maxX <= screen.maxX)
        let centered = UploadProgressHUDLayout.frame(below: nil, on: screen, visible: CGRect(x: 0, y: 0, width: 1440, height: 1040))
        #expect(centered.midX == 720)
        #expect(centered.maxY == 1040 - UploadProgressHUDLayout.gap)
    }
}

@MainActor
struct ViewCountHistoryTests {
    @Test func storesTheViewCountLinkFromTheUploadResponse() throws {
        let uploader = CustomUploader(
            name: "zipline", requestURL: "https://z.example/api/upload", headers: nil, formData: nil, fileFormName: "file",
            responseURL: "{{files[0].url}}")
        var withViews = uploader
        withViews.viewCount = ViewCountSpec(url: "https://z.example/api/user/files/{{files[0].id}}", path: "views")
        let response = Data(#"{"files": [{"id": "abc", "url": "https://z.example/u/abc.png"}]}"#.utf8)
        let outcome = try HTTPUploader.outcome(from: response, uploader: withViews)
        #expect(outcome.viewCountURL == "https://z.example/api/user/files/abc")
        #expect(try HTTPUploader.outcome(from: response, uploader: uploader).viewCountURL == nil)
        let item = UploadCoordinator.historyItem(for: outcome, target: .custom(withViews), localFileURL: nil, now: Date())
        #expect(item.viewCountUrl == "https://z.example/api/user/files/abc")
    }
}

struct ScriptHookRunnerTests {
    @Test func passesTheEventFileAndLinkToTheScript() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "hook-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appending(path: "out.txt")
        let script = folder.appending(path: "hook.sh")
        try "echo \"$1 $2 $3 $ISHARE_LINK\" > '\(output.path)'\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        let status = await ScriptHooks.run(script: script.path, event: .upload, file: "/tmp/a.png", link: "https://x/a.png")
        #expect(status == 3)
        #expect(try String(contentsOf: output, encoding: .utf8) == "upload /tmp/a.png https://x/a.png https://x/a.png\n")
    }
}

@MainActor
struct ImageOperationsTests {
    @Test func trimsIntoANewFileNextToTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ops-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appending(path: "shot.png")
        try ImageEncoder.write(TestImages.solid(width: 40, height: 30, color: CaptureColor(red: 1, green: 1, blue: 1)), as: .PNG, to: input)
        let output = try await ImageOperations.apply(.trim, to: input)
        #expect(output == folder.appending(path: "shot-trimmed.png"))
        #expect(FileManager.default.fileExists(atPath: output.path))
        let again = try await ImageOperations.apply(.trim, to: input)
        #expect(again.lastPathComponent == "shot-trimmed-2.png")
    }

    @Test func mapsScriptingCodes() {
        #expect(ScriptingCodes.imageOperation(ScriptingCodes.fourCharCode("eFrm")) == .frame)
        #expect(ScriptingCodes.imageOperation(nil) == nil)
        #expect(ScriptingCodes.deviceFrame(nil) == .laptop)
        #expect(ScriptingCodes.deviceFrame(ScriptingCodes.fourCharCode("dPho")) == .phone)
    }
}

@MainActor
struct FeatureTourTests {
    @Test func everyStopOpensARealCommand() {
        let ids = Set(AppCommand.all().map(\.id))
        for stop in FeatureTour.stops {
            if let command = stop.commandID {
                #expect(ids.contains(command), "\(stop.id) points at \(command)")
            }
        }
        #expect(ids.contains("app.tour"))
    }
}

struct MenuSizeTests {
    @Test func compactMenusKeepOnlyCaptureAndRecentUploads() {
        #expect(MenuSize.sections(MenuSection.allCases, compact: true) == [.capture, .recentUploads])
        #expect(MenuSize.sections(MenuSection.allCases, compact: false) == MenuSection.allCases)
    }

    @Test func automaticallyCompactsOnShortScreens() {
        #expect(MenuSize.automatic.isCompact(visibleHeight: 760))
        #expect(!MenuSize.automatic.isCompact(visibleHeight: 1050))
        #expect(MenuSize.compact.isCompact(visibleHeight: 2000))
        #expect(!MenuSize.full.isCompact(visibleHeight: 400))
    }
}

@MainActor
struct BufferingIconTests {
    @Test func drawsAColoredBadgeOverTheMenuBarIcon() {
        let base = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        let icon = StatusIconRenderer.buffering(base: base)
        #expect(icon.size == StatusIconRenderer.size)
        #expect(!icon.isTemplate)
        #expect(icon.accessibilityDescription?.isEmpty == false)
    }
}

struct WindowShadowEditorTests {
    func shadowedWindow() -> CGImage {
        let context = CGContext(
            data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: CGColor(gray: 0, alpha: 0.5))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 40, y: 30, width: 120, height: 90))
        return context.makeImage()!
    }

    @Test func removesTheShadowAroundAWindow() throws {
        let removed = try #require(WindowShadowEditor.apply(.none, to: shadowedWindow()))
        #expect(removed.width == 120)
        #expect(removed.height == 90)
    }

    @Test func addsANewShadowWithRoomForIt() throws {
        let soft = try #require(WindowShadowEditor.apply(.soft, to: shadowedWindow(), scale: 1))
        #expect(soft.width == 120 + Int(WindowShadowStyle.soft.padding * 2))
    }
}

@MainActor
@Suite(.serialized)
struct EditorKindPreferenceTests {
    @Test func remembersTheToolAndColorPerKindOfImage() throws {
        Defaults[.editorKindPreferences] = [:]
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 400, height: 300), hue: 0.5, title: "Kind"))
        let web = URL(fileURLWithPath: "/tmp/ishare-2026-example.com.png")
        let first = EditorDocument(image: image, fileURL: web)
        #expect(first.kind == .webPage)
        first.select(tool: .measure)
        first.color = .blue
        let second = EditorDocument(image: image, fileURL: web)
        #expect(second.tool == .measure)
        #expect(second.color == .blue)
        let screenshot = EditorDocument(image: image, fileURL: URL(fileURLWithPath: "/tmp/ishare-2026-Safari.png"))
        #expect(screenshot.tool != .measure)
        Defaults[.editorKindPreferences] = [:]
    }
}

@MainActor
struct RedactionReviewTests {
    @Test func previewsEachRedactionWithSomeContext() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 800, height: 600), hue: 0.4, title: "Review"))
        let document = EditorDocument(image: image, fileURL: nil)
        document.add(Annotation(shape: .blur(CGRect(x: 100, y: 100, width: 200, height: 50)), color: .red, lineWidth: 2))
        document.add(Annotation(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)), color: .red, lineWidth: 2))
        #expect(document.redactions.count == 1)
        let preview = try #require(document.redactionPreview(for: document.redactions[0], rendered: document.render()))
        #expect(preview.width == 360)
        #expect(EditorDocument.reviewRect(for: CGRect(x: 0, y: 0, width: 10, height: 10), in: document.imageBounds).minX == 0)
    }
}

@MainActor
struct AnnotationFromTextTests {
    @Test func resolvesRequestsWithoutTheModel() async {
        let result = await AnnotationFromText.resolve("box around Export", labels: ["File", "Export…", "Share"])
        #expect(result?.0 == .rectangle)
        #expect(result?.1 == 1)
    }

    @Test func placesEachKindAroundTheTarget() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 800, height: 600), hue: 0.3, title: "Text"))
        let document = EditorDocument(image: image, fileURL: nil)
        let target = CGRect(x: 600, y: 500, width: 100, height: 30)
        for kind in AnnotationCommandKind.allCases {
            let annotation = AnnotationFromText.makeAnnotation(kind, around: target, document: document)
            #expect(annotation.bounds.intersects(target.insetBy(dx: -20, dy: -20)) || kind == .arrow)
        }
    }
}

@MainActor
struct ExportPresetRunnerTests {
    @Test func encodesAtThePresetSize() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 2000, height: 1000), hue: 0.2, title: "Preset"))
        let small = ExportPreset.builtIn[3]
        let data = try ExportPresetRunner.data(for: image, preset: small, pointScale: 2)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 1000)
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
    }
}

struct PointerHighlightTests {
    @Test func aHighlightRendersThePointerAfterRecording() {
        #expect(PointerEffectSettings(highlight: .halo).rendersPointer)
        #expect(!PointerEffectSettings().rendersPointer)
        #expect(!PointerEffectSettings(recordsPointer: false, highlight: .spotlight).rendersPointer)
        #expect(PointerHighlight.spotlight.radius > PointerHighlight.halo.radius)
    }
}

struct WebcamLayoutCompositionTests {
    @Test func composesTheWebcamBesideTheScreen() throws {
        let size = CGSize(width: 400, height: 200)
        let screen = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(origin: .zero, size: size))
        let webcam = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        var layout = OverlayCompositionLayout(videoSize: size, pixelsPerPoint: 1, webcamFrame: CGRect(x: 300, y: 20, width: 60, height: 60))
        layout.webcamLayout = .sideBySide
        let composed = OverlayImageRenderer().compose(screen: screen, webcam: webcam, time: 1, timeline: OverlayTimeline(), layout: layout)
        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(composed, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 395, y: 100, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(pixel[0] > 200 && pixel[2] < 50)
    }
}

struct FolderArchiveTests {
    @Test func zipsAFolderIntoOneFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Project \(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("one".utf8).write(to: folder.appending(path: "a.txt"))
        try Data("two".utf8).write(to: folder.appending(path: "nested/b.txt"))
        #expect(FolderArchive.isFolder(folder))
        let archive = try await FolderArchive.zipped(folder)
        defer { FolderArchive.discard(archive) }
        #expect(archive.lastPathComponent == folder.lastPathComponent + ".zip")
        let data = try Data(contentsOf: archive)
        #expect(data.prefix(2) == Data("PK".utf8))
        #expect(!FolderArchive.isFolder(archive))
    }
}

@MainActor
struct RecentUploadFactsTests {
    @Test func listsHostSizeViewsAndExpiry() {
        var item = HistoryItem(fileUrl: "https://files.example.com/a.png", date: Date())
        item.uploadedSize = 2_048_000
        item.viewCount = 1260
        item.expiresAt = Date().addingTimeInterval(3 * 86400)
        let facts = RecentUploadPreview.facts(for: item, fileSize: { _ in nil })
        #expect(facts.first == "files.example.com")
        #expect(facts.count == 4)
        #expect(facts[2].contains("1.3K"))
        item.keepForever = true
        #expect(RecentUploadPreview.facts(for: item, fileSize: { _ in nil }).last == "Kept forever")
    }
}

struct CaptureRulesTests {
    @Test func routesAnAppsCapturesToItsUploaderWithRedaction() {
        let id = UUID()
        var profile = CaptureProfile(bundleIdentifier: "com.apple.dt.Xcode", appName: "Xcode")
        profile.uploadDestination = .custom(id)
        profile.redactsSensitiveText = true
        profile.opensEditor = true
        let options = CaptureRules.applying(profile, to: .standard)
        #expect(options.ruleDestination == .custom(id))
        #expect(options.forceUpload)
        #expect(options.openEditor)
        #expect(options.redactsSensitiveText == true)
    }

    @Test func leavesExplicitChoicesAndDisabledRulesAlone() {
        var profile = CaptureProfile(bundleIdentifier: "app", appName: "App")
        profile.uploadDestination = .builtIn(.IMGUR)
        var handled = CaptureOptions()
        handled.resultHandler = { _ in }
        #expect(CaptureRules.applying(profile, to: handled).ruleDestination == nil)
        profile.isEnabled = false
        #expect(CaptureRules.applying(profile, to: .standard).forceUpload == false)
    }
}

struct PointerResultHUDLayoutTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func appearsBelowAndRightOfThePointer() {
        let frame = PointerResultHUDLayout.frame(near: CGPoint(x: 500, y: 500), in: visible)
        #expect(frame.minX == 518)
        #expect(frame.maxY == 482)
    }

    @Test func flipsAwayFromScreenEdges() {
        let corner = PointerResultHUDLayout.frame(near: CGPoint(x: 1430, y: 20), in: visible)
        #expect(corner.maxX <= visible.maxX)
        #expect(corner.minY >= visible.minY)
        #expect(ResultPresentation.pointer.showsToast == false && ResultPresentation.pointer.postsNotification == false)
    }
}

@MainActor
struct SettingsSearchHitTests {
    @Test func listsEachMatchingSettingUnderItsPane() {
        let hits = SettingsSearchIndex.hits(for: "halo", in: .recording)
        #expect(hits.map(\.anchor) == ["recording.pointerHighlight"])
        #expect(SettingsSearchIndex.hits(for: "token", in: .advanced).first?.anchor == "advanced.localAPI")
        #expect(SettingsSearchIndex.hits(for: "", in: .capture).isEmpty)
        #expect(SettingsSearchIndex.hits(for: "e", in: .capture).count <= SettingsSearchIndex.maximumHits)
    }
}

struct HistoryGroupingSectionTests {
    func item(_ app: String?, _ title: String?) -> HistoryItem {
        var item = HistoryItem(fileUrl: "https://x/\(UUID().uuidString).png", date: Date())
        item.sourceApp = app
        item.sourceTitle = title
        return item
    }

    @Test func groupsByAppAndByProject() {
        let items = [item("Xcode", "ishare — App.swift"), item("Safari", "Docs"), item("Xcode", "website — main.ts"), item(nil, nil)]
        let byApp = HistoryTimeline.sections(for: items, groupedBy: .app, localize: { $0 })
        #expect(byApp.map(\.title) == ["Xcode", "Safari", "Other"])
        #expect(byApp[0].items.count == 2)
        let byProject = HistoryTimeline.sections(for: items, groupedBy: .project, localize: { $0 })
        #expect(byProject.map(\.title) == ["ishare", "Docs", "website", "Other"])
    }
}

@MainActor
@Suite(.serialized)
struct HistoryBulkEditTests {
    @Test func keepsAndExpiresManyUploadsAtOnce() {
        let id = UUID()
        let items = (0..<3).map { HistoryItem(fileUrl: "https://x/\($0).png", deletionUrl: "https://x/d/\($0)", uploaderId: id, date: Date(timeIntervalSince1970: Double($0))) }
        Defaults[.uploadHistory] = items
        HistoryBulkEdit.setKeepForever(Array(items.prefix(2)), true)
        #expect(Defaults[.uploadHistory].map(\.keepForever) == [true, true, nil])
        HistoryBulkEdit.setExpiry(items, days: 7)
        #expect(Defaults[.uploadHistory].allSatisfy { $0.expiresAt != nil && $0.keepForever == nil })
        Defaults[.uploadHistory] = []
    }
}

struct StorageScannerTests {
    @Test func countsOnlyCapturesIshareNamed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "storage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 1000).write(to: folder.appending(path: "ishare-1800000000.png"))
        try Data(count: 3000).write(to: folder.appending(path: "ishare-1800000001.mov"))
        try Data(count: 500).write(to: folder.appending(path: "holiday.png"))
        let plan = LocalCaptureCleanupPlan(directories: [folder], prefixes: ["ishare"], cutoff: .distantFuture, protectedPaths: [])
        let files = StorageScanner.files(in: plan)
        let summary = StorageSummary(files: files.map(\.file))
        #expect(summary.imageCount == 1 && summary.videoCount == 1)
        #expect(summary.localBytes == 4000)
        #expect(StorageScanner.size(of: folder) == 4500)
    }
}
