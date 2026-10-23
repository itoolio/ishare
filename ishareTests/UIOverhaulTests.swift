import AppKit
import Defaults
import Foundation
import Testing
@testable import ishare

struct DragExportPlanTests {
    let local = URL(fileURLWithPath: "/tmp/ishare-drag/shot.png")
    let remote = URL(string: "https://img.example.com/shot.png")!

    @Test func prefersTheLocalFileAndAddsTheLinkAsText() {
        let plan = DragExportPlan.make(localFile: local, remoteURL: remote, linkText: "https://is.gd/abc", fileName: "shot.png", isImage: true) { _ in true }
        #expect(plan.payload == .file(local))
        #expect(plan.link == "https://is.gd/abc")
        #expect(plan.suggestedName == "shot.png")
    }

    @Test func fallsBackToTheCachedRemoteImageWhenTheFileIsGone() {
        let plan = DragExportPlan.make(localFile: local, remoteURL: remote, linkText: nil, fileName: "shot.png", isImage: true) { _ in false }
        #expect(plan.payload == .image(ThumbnailKey(source: .remote(remote), requestedPixelSize: DragExportPlan.fallbackPixelSize)))
        #expect(plan.link == remote.absoluteString)
    }

    @Test func offersOnlyTheLinkForRemoteVideosAndNonHTTPLinks() {
        let video = DragExportPlan.make(localFile: nil, remoteURL: URL(string: "https://img.example.com/a.mp4"), linkText: nil, fileName: "a.mp4", isImage: false)
        #expect(video.payload == .none)
        #expect(video.link == "https://img.example.com/a.mp4")
        let ftp = DragExportPlan.make(localFile: nil, remoteURL: URL(string: "ftp://example.com/a.png"), linkText: nil, fileName: "a.png", isImage: true)
        #expect(ftp.payload == .none)
    }

    @Test func buildsAPlanFromAHistoryItem() {
        let item = HistoryItem(fileUrl: remote.absoluteString, localPath: local.path, shortUrl: "https://is.gd/x")
        let plan = DragExportPlan.make(for: item) { _ in true }
        #expect(plan.payload == .file(local))
        #expect(plan.link == "https://is.gd/x")
        let missing = DragExportPlan.make(for: item) { _ in false }
        #expect(missing.suggestedName == "shot.png")
        #expect(missing.payload == .image(ThumbnailKey(source: .remote(remote), requestedPixelSize: 1024)))
    }

    @MainActor @Test func registersTheFileAndTheLinkOnTheProvider() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "drag.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        let provider = DragExport.provider(for: .make(localFile: file, remoteURL: remote, linkText: nil, fileName: nil, isImage: true))
        #expect(provider.hasItemConformingToTypeIdentifier("public.file-url") || provider.hasItemConformingToTypeIdentifier("public.png"))
        #expect(provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text"))
        #expect(provider.suggestedName == "drag.png")
    }
}

struct MenuFavoritesTests {
    @Test func pinsUpToSixUniqueActions() {
        var favorites = MenuFavorites()
        for id in ["a", "b", "a", "c", "d", "e", "f", "g"] {
            favorites = favorites.pinning(id)
        }
        #expect(favorites.ids == ["a", "b", "c", "d", "e", "f"])
        #expect(favorites.isFull)
        #expect(!favorites.canPin("g"))
        #expect(MenuFavorites(["x", "x", "", "y"]).ids == ["x", "y"])
    }

    @Test func unpinsTogglesAndReorders() {
        let favorites = MenuFavorites(["a", "b", "c"])
        #expect(favorites.unpinning("b").ids == ["a", "c"])
        #expect(favorites.toggling("a").ids == ["b", "c"])
        #expect(favorites.toggling("z").ids == ["a", "b", "c", "z"])
        #expect(favorites.moving("c", by: -1).ids == ["a", "c", "b"])
        #expect(favorites.moving("a", by: -1) == favorites)
        #expect(favorites.moving("missing", by: 1) == favorites)
    }

    @Test func resolvesPinnedIDsAgainstAvailableCommandsInPinnedOrder() {
        let favorites = MenuFavorites(["record.gif", "gone", "capture.region"])
        let resolved = favorites.resolved(in: ["capture.region", "record.gif", "app.quit"]) { $0 }
        #expect(resolved == ["record.gif", "capture.region"])
    }

    @MainActor @Test func menuTileIDsExistAsCommands() {
        let ids = Set(AppCommand.all().map(\.id))
        let tiles = (0 ..< 4).compactMap(MenuFavoriteCommandID.capture)
            + [MenuFavoriteCommandID.footer(0), MenuFavoriteCommandID.footer(1), MenuFavoriteCommandID.history]
            + [false, true].flatMap { gif in [0, 1].map { MenuFavoriteCommandID.record($0, gif: gif) } }
        #expect(tiles.count == 11)
        #expect(tiles.allSatisfy(ids.contains))
        #expect(MenuFavoriteCommandID.capture(4) == nil)
    }

    @Test func focusRowsIncludeFavoritesBelowTheHeader() {
        let rows = MenuFocusLayout.rows(sections: [.capture], isRecording: false, chipCount: 0, recentCount: 0, favoriteCount: 2)
        #expect(rows.count == 3)
        #expect(rows[1] == [.favorite(0), .favorite(1)])
        let none = MenuFocusLayout.rows(sections: [.capture], isRecording: false, chipCount: 0, recentCount: 0)
        #expect(none.count == 2)
    }
}

struct MenuSectionDragTests {
    @Test func roundTripsSectionPayloadsAndRejectsForeignText() {
        for section in MenuSection.allCases {
            #expect(MenuSectionDrag.section(from: MenuSectionDrag.payload(for: section)) == section)
        }
        #expect(MenuSectionDrag.section(from: "capture") == nil)
        #expect(MenuSectionDrag.section(from: MenuSectionDrag.prefix + "nope") == nil)
    }

    @Test func dropsASectionOntoAnother() {
        let layout = MenuLayout()
        #expect(layout.moving(.footer, onto: .capture).order == [.footer, .capture, .record, .afterCapture, .recentUploads])
        #expect(layout.moving(.capture, onto: .afterCapture).order == [.record, .afterCapture, .capture, .recentUploads, .footer])
        #expect(layout.moving(.record, onto: .record) == layout)
    }
}

struct QuickAnnotateGeometryTests {
    @Test func fitsTheImageInsideTheCanvasKeepingItsAspectRatio() {
        let geometry = QuickAnnotateGeometry(imageSize: CGSize(width: 2000, height: 1000), canvasSize: CGSize(width: 360, height: 240))
        #expect(geometry.fittedRect == CGRect(x: 0, y: 30, width: 360, height: 180))
        #expect(abs(geometry.imagePixelsPerPoint - 2000.0 / 360.0) < 0.0001)
    }

    @Test func mapsThumbnailPointsToFullResolutionPixels() {
        let geometry = QuickAnnotateGeometry(imageSize: CGSize(width: 2000, height: 1000), canvasSize: CGSize(width: 360, height: 240))
        #expect(geometry.toImage(CGPoint(x: 0, y: 30)) == .zero)
        let center = geometry.toImage(CGPoint(x: 180, y: 120))
        #expect(abs(center.x - 1000) < 0.001 && abs(center.y - 500) < 0.001)
        let corner = geometry.toImage(CGPoint(x: 360, y: 210))
        #expect(abs(corner.x - 2000) < 0.001 && abs(corner.y - 1000) < 0.001)
    }

    @Test func clampsPointsOutsideTheImage() {
        let geometry = QuickAnnotateGeometry(imageSize: CGSize(width: 2000, height: 1000), canvasSize: CGSize(width: 360, height: 240))
        #expect(geometry.toImage(CGPoint(x: -20, y: 5)) == .zero)
        #expect(geometry.toImage(CGPoint(x: 500, y: 300)) == CGPoint(x: 2000, y: 1000))
    }

    @Test func roundTripsBetweenViewAndImage() {
        let geometry = QuickAnnotateGeometry(imageSize: CGSize(width: 800, height: 1600), canvasSize: CGSize(width: 360, height: 240))
        let fitted = geometry.fittedRect
        #expect(abs(fitted.width - 120) < 0.001 && abs(fitted.minX - 120) < 0.001)
        let point = CGPoint(x: 400, y: 900)
        let back = geometry.toImage(geometry.toView(point))
        #expect(abs(back.x - point.x) < 0.001 && abs(back.y - point.y) < 0.001)
        #expect(geometry.imageToView.concatenating(.identity) == geometry.imageToView)
        let viewPoint = point.applying(geometry.imageToView)
        #expect(abs(viewPoint.x - geometry.toView(point).x) < 0.001)
    }

    @Test func sizesTheCanvasForWideAndTallImages() {
        #expect(QuickAnnotateGeometry.canvasSize(for: CGSize(width: 2000, height: 1000), maxWidth: 360, maxHeight: 240) == CGSize(width: 360, height: 180))
        #expect(QuickAnnotateGeometry.canvasSize(for: CGSize(width: 1000, height: 2000), maxWidth: 360, maxHeight: 240) == CGSize(width: 120, height: 240))
    }

    @MainActor @Test func drawsAtFullResolution() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 1600, height: 1000), hue: 0.4, title: "Quick"))
        let session = QuickAnnotateSession(image: image, fileURL: URL(fileURLWithPath: "/tmp/quick.png"))
        session.select(.rectangle)
        let start = session.geometry.toView(CGPoint(x: 200, y: 200))
        let end = session.geometry.toView(CGPoint(x: 800, y: 600))
        session.dragChanged(from: start, to: end)
        #expect(session.draft != nil)
        session.dragEnded(from: start, to: end)
        #expect(session.draft == nil)
        let annotation = try #require(session.document.annotations.first)
        guard case let .rectangle(rect) = annotation.shape else {
            Issue.record("Expected a rectangle")
            return
        }
        #expect(abs(rect.minX - 200) < 1 && abs(rect.maxX - 800) < 1 && abs(rect.maxY - 600) < 1)
        let rendered = try #require(session.render())
        #expect(rendered.width == 1600 && rendered.height == 1000)
    }

    @MainActor @Test func ignoresClicksWithoutADragAndPlacesTextOnClick() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 800, height: 500), hue: 0.1, title: ""))
        let session = QuickAnnotateSession(image: image, fileURL: URL(fileURLWithPath: "/tmp/quick.png"))
        session.dragEnded(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50))
        #expect(session.document.annotations.isEmpty)
        session.select(.text)
        session.dragEnded(from: CGPoint(x: 90, y: 60), to: CGPoint(x: 90, y: 60))
        let edit = try #require(session.document.editingText)
        #expect(edit.origin == session.geometry.toImage(CGPoint(x: 90, y: 60)))
        session.document.editingText?.text = "Hi"
        session.select(.arrow)
        #expect(session.document.annotations.count == 1)
    }
}

struct UploadReplacementTests {
    let old = HistoryItem(fileUrl: "https://img.example.com/old.png", deletionUrl: "https://img.example.com/delete/old", date: Date(timeIntervalSince1970: 1))
    let new = HistoryItem(fileUrl: "https://img.example.com/new.png", deletionUrl: "https://img.example.com/delete/new", date: Date(timeIntervalSince1970: 2))
    let other = HistoryItem(fileUrl: "https://img.example.com/other.png", date: Date(timeIntervalSince1970: 0))

    @Test func replacesTheOldItemInPlace() {
        #expect(UploadReplacement.history([new, other, old], replacing: old, with: new) == [other, new])
        #expect(UploadReplacement.history([new, old, other], replacing: old, with: new) == [new, other])
        #expect(UploadReplacement.history([other], replacing: old, with: new) == [new, other])
        #expect(UploadReplacement.history([old], replacing: old, with: old) == [old])
    }

    @Test func offersServerDeletionOnlyForDeletableReplacedUploads() {
        #expect(UploadReplacement.offersServerDeletion(of: old, replacedBy: new))
        #expect(!UploadReplacement.offersServerDeletion(of: old, replacedBy: nil))
        #expect(!UploadReplacement.offersServerDeletion(of: other, replacedBy: new))
        #expect(!UploadReplacement.offersServerDeletion(of: old, replacedBy: old))
    }
}

struct GlassRenderingTests {
    @Test func usesSolidFillsWhenTransparencyIsReduced() {
        #expect(GlassRendering.resolve(glassAvailable: true, reduceTransparency: true, fallback: .material) == .solid)
        #expect(GlassRendering.resolve(glassAvailable: false, reduceTransparency: true, fallback: .fill(0.1)) == .solid)
    }

    @Test func fallsBackBeforeMacOS26() {
        #expect(GlassRendering.resolve(glassAvailable: true, reduceTransparency: false, fallback: .material) == .glass)
        #expect(GlassRendering.resolve(glassAvailable: false, reduceTransparency: false, fallback: .material) == .material)
        #expect(GlassRendering.resolve(glassAvailable: false, reduceTransparency: false, fallback: .fill(0.07)) == .fill(0.07))
    }

    @Test func strengthensBordersForHighContrast() {
        #expect(GlassRendering.borderOpacity(for: .glass, contrast: .standard) == 0)
        #expect(GlassRendering.borderOpacity(for: .glass, contrast: .high) == MenuContrast.high.borderOpacity)
        #expect(GlassRendering.borderOpacity(for: .solid, contrast: .standard) > 0)
    }
}

struct SettingsAnchorSearchTests {
    @MainActor @Test func searchResultsCarryTheAnchorOfTheMatchingSetting() {
        let toast = SettingsSearchIndex.matches(for: "toast timeout", localize: { $0 })
        #expect(toast.first == SettingsSearchMatch(pane: .general, keyword: "Toast Timeout", anchor: SettingsAnchor.toastTimeout))
        let sounds = SettingsSearchIndex.matches(for: "beep", localize: { $0 })
        #expect(sounds.first?.anchor == SettingsAnchor.sounds)
        #expect(SettingsSearchIndex.matches(for: "general", localize: { $0 }).first?.anchor == nil)
    }

    @MainActor @Test func extraEntriesCanDeclareTheirOwnAnchors() {
        let entries = [SettingsSearchEntry(pane: .advanced, keywords: ["Telemetry"], anchor: "advanced.telemetry")]
        #expect(SettingsSearchIndex.matches(for: "telemetry", entries: entries, localize: { $0 }) == [SettingsSearchMatch(pane: .advanced, keyword: "Telemetry", anchor: "advanced.telemetry")])
    }

    @MainActor @Test func everyGeneralEntryIsAnchoredUniquely() {
        let anchors = SettingsSearchIndex.entries.filter { $0.pane == .general }.map(\.anchor)
        #expect(anchors.allSatisfy { $0 != nil })
        #expect(Set(anchors.compactMap { $0 }).count == anchors.count)
    }

    @MainActor @Test func revealPublishesARequestAndHighlightExpires() async throws {
        let navigator = SettingsNavigator()
        navigator.reveal("general.sounds", in: .general)
        #expect(navigator.pane == .general)
        #expect(navigator.anchorRequest?.anchor == "general.sounds")
        let first = try #require(navigator.anchorRequest)
        navigator.reveal("general.sounds")
        #expect(navigator.anchorRequest != first)
        navigator.highlight("general.sounds", duration: .milliseconds(20))
        #expect(navigator.highlightedAnchor == "general.sounds")
        try await Task.sleep(for: .milliseconds(200))
        #expect(navigator.highlightedAnchor == nil)
    }
}

struct OnboardingProgressTests {
    @Test func resumesAtTheSavedStep() {
        #expect(OnboardingStep.resumed(from: OnboardingStep.tryEditor.rawValue) == .tryEditor)
        #expect(OnboardingStep.resumed(from: 99) == .permission)
        #expect(OnboardingStep.resumed(from: -1) == .permission)
    }

    @Test func interactiveStepsHaveTrials() {
        #expect(OnboardingStep.allCases.compactMap(\.trial) == [.capture, .editor, .palette])
        #expect(OnboardingStep.permission.trial == nil)
    }

    @MainActor @Test func remembersCompletedTrials() {
        Defaults[.onboardingTrials] = []
        defer { Defaults.reset(.onboardingTrials) }
        let model = OnboardingTrialModel(completed: [])
        model.closePalette()
        #expect(model.isCompleted(.palette))
        #expect(Defaults[.onboardingTrials] == ["palette"])
        #expect(OnboardingTrialModel().isCompleted(.palette))
    }

    @MainActor @Test func showsTheCaptureInsteadOfFinishingIt() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 64, height: 40), hue: 0.2, title: ""))
        let source = FileManager.default.temporaryDirectory.appending(path: "onboarding-\(UUID().uuidString).png")
        try ImageEncoder.write(image, as: .PNG, to: source)
        let model = OnboardingTrialModel(completed: [])
        defer { Defaults.reset(.onboardingTrials) }
        model.receive(source)
        let shown = try #require(model.captureURL)
        defer { try? FileManager.default.removeItem(at: shown) }
        #expect(shown.deletingLastPathComponent().standardizedFileURL == OnboardingTrialModel.directory.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(model.preview != nil)
        #expect(model.isCompleted(.capture))
    }
}

struct WhatsNewTests {
    static let changelog = """
    ## [5.3.0](https://github.com/itoolio/ishare/compare/v5.2.1...v5.3.0) (2026-11-01)

    ### Features

    * **menu:** favourites and drag reorder ([abc1234](https://github.com/itoolio/ishare/commit/abc1234def))
    * quick annotate on the toast, closes [#12](https://github.com/itoolio/ishare/issues/12)

    ### Bug Fixes

    * **toast:** keep the [link](https://example.com) readable ([0123456](https://github.com/itoolio/ishare/commit/0123456))

    ### Miscellaneous Chores

    * bump dependencies

    ## [5.2.1](https://github.com/itoolio/ishare/compare/v5.2.0...v5.2.1) (2026-10-23)

    ### Bug Fixes

    * **app-store:** declare the keychain group ([bc5e28b](https://github.com/itoolio/ishare/commit/bc5e28b))

    ## 5.2.0 (2026-10-22)

    ### Features

    * text capture

    ### ⚠ BREAKING CHANGES

    * nothing user facing
    """

    @Test func parsesOnlyUserFacingSectionsWithoutHashesOrLinks() {
        let releases = ChangelogParser.parse(Self.changelog)
        #expect(releases.map(\.version) == ["5.3.0", "5.2.1", "5.2.0"])
        #expect(releases[0].sections.map(\.title) == ["Features", "Bug Fixes"])
        #expect(releases[0].sections[0].items == ["Favourites and drag reorder", "Quick annotate on the toast"])
        #expect(releases[0].sections[1].items == ["Keep the link readable"])
        #expect(releases[2].sections.map(\.title) == ["Features"])
    }

    @Test func comparesVersionsNumerically() {
        #expect(AppVersion("5.10.0")! > AppVersion("5.9.9")!)
        #expect(AppVersion("5.2")! == AppVersion("5.2.0")!)
        #expect(AppVersion("v5.3.1")?.description == "5.3.1")
        #expect(AppVersion("5.3.1")?.majorMinor == "5.3")
        #expect(AppVersion("abc") == nil)
    }

    @Test func picksTheReleasesSinceTheLastLaunch() {
        let releases = ChangelogParser.parse(Self.changelog)
        #expect(WhatsNew.releases(in: releases, after: "5.2.0", upTo: "5.3.0").map(\.version) == ["5.3.0", "5.2.1"])
        #expect(WhatsNew.releases(in: releases, after: "5.2.1", upTo: "5.2.1").isEmpty)
        #expect(WhatsNew.releases(in: releases, after: nil, upTo: "5.2.1").map(\.version) == ["5.2.1", "5.2.0"])
    }

    @Test func showsOnlyAfterAnUpdate() {
        #expect(WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: "5.2.1", hasCompletedOnboarding: true, showsWhatsNew: true, isSuppressed: false))
        #expect(WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: nil, hasCompletedOnboarding: true, showsWhatsNew: true, isSuppressed: false))
        #expect(!WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: nil, hasCompletedOnboarding: false, showsWhatsNew: true, isSuppressed: false))
        #expect(!WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: "5.3.0", hasCompletedOnboarding: true, showsWhatsNew: true, isSuppressed: false))
        #expect(!WhatsNew.shouldPresent(current: "5.2.0", lastLaunched: "5.3.0", hasCompletedOnboarding: true, showsWhatsNew: true, isSuppressed: false))
        #expect(!WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: "5.2.1", hasCompletedOnboarding: true, showsWhatsNew: false, isSuppressed: false))
        #expect(!WhatsNew.shouldPresent(current: "5.3.0", lastLaunched: "5.2.1", hasCompletedOnboarding: true, showsWhatsNew: true, isSuppressed: true))
    }

    @Test func bundlesTheChangelog() {
        let releases = WhatsNew.bundledReleases()
        #expect(!releases.isEmpty)
        #expect(releases.allSatisfy { !$0.sections.isEmpty })
        #expect(releases.flatMap(\.sections).flatMap(\.items).allSatisfy { !$0.contains("](") && !$0.contains("**") })
    }
}
