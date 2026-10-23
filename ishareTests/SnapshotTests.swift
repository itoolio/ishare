import AppKit
import Defaults
import SwiftUI
import Testing
@testable import ishare

@MainActor
@Suite(.serialized, .enabled(if: SnapshotStore.isAvailable, "No reference snapshots for this macOS version; record them with ISHARE_RECORD_SNAPSHOTS=1"))
struct SnapshotTests {
    enum Subject: String, CaseIterable {
        case menu
        case toast
        case editorToolbar
        case generalSettings

        @MainActor var size: CGSize {
            switch self {
            case .menu: CGSize(width: 360, height: 420)
            case .toast: CGSize(width: ToastCardView.width + 24, height: 120)
            case .editorToolbar: CGSize(width: 1000, height: 600)
            case .generalSettings: CGSize(width: 620, height: 760)
            }
        }

        var crop: CGRect? {
            self == .editorToolbar ? CGRect(x: 0, y: 0, width: 1000, height: 56) : nil
        }
    }

    nonisolated static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    nonisolated static let languages = ["en", "de", "ja"]

    nonisolated static let cases: [(Subject, String, String)] = Subject.allCases.flatMap { subject in
        appearances.flatMap { appearance in languages.map { (subject, appearance.0, $0) } }
    }

    init() {
        Defaults.reset(
            .uploadHistory, .copyToClipboard, .openInFinder, .saveToDisk, .uploadMedia, .openEditorAfterCapture, .uploadType,
            .activeCustomUploader, .uploadDestination, .builtInShare, .menuRecordsGIF, .aussieMode, .toastTimeout, .menuBarIcon,
            .copyImageToClipboard, .captureSound, .uploadCompleteSound, .historyLimit, .historyRetention, .savedCustomUploaders
        )
    }

    func view(for subject: Subject) -> AnyView {
        switch subject {
        case .menu:
            return AnyView(MainMenuView().appModel())
        case .toast:
            let image = ScreenshotMode.sampleImage(size: CGSize(width: 320, height: 200), hue: 0.58, title: "Toast").map { NSImage(cgImage: $0, size: CGSize(width: 160, height: 100)) }
            let model = ToastModel(fileURL: URL(fileURLWithPath: "/tmp/ishare-1800000000.png"), isImage: true, thumbnail: image)
            return AnyView(ToastCardView(model: model).padding(12))
        case .editorToolbar:
            let image = ScreenshotMode.sampleImage(size: CGSize(width: 1600, height: 1000), hue: 0.6, title: "Snapshot")!
            let document = EditorDocument(image: image, fileURL: nil)
            return AnyView(EditorView(document: document, onDone: {}, onDiscard: {}, onCopy: {}))
        case .generalSettings:
            return AnyView(GeneralSettingsView().appModel())
        }
    }

    @Test(arguments: cases)
    func matchesTheReference(subject: Subject, appearance: String, language: String) throws {
        let appearanceName = try #require(Self.appearances.first { $0.0 == appearance }?.1)
        let rendered = LanguageOverride.with(language) {
            SnapshotRenderer.render(view(for: subject).environment(\.locale, Locale(identifier: language)), size: subject.size, appearance: appearanceName)
        }
        var image = try #require(rendered)
        if let crop = subject.crop {
            image = try #require(SnapshotRenderer.crop(image, toPoints: crop))
        }
        let name = "\(subject.rawValue)-\(appearance)-\(language)"
        switch try SnapshotStore.verify(image, named: name) {
        case .matched, .recorded:
            break
        case let .missingReference(actual):
            Issue.record("No reference for \(name); the rendering is at \(actual). Record references with ISHARE_RECORD_SNAPSHOTS=1.")
        case let .sizeChanged(actual):
            Issue.record("\(name) changed size; the rendering is at \(actual)")
        case let .different(pixels, actual):
            Issue.record("\(name) differs from its reference in \(pixels) pixels; the rendering is at \(actual)")
        }
    }

    @Test func languageOverrideSwitchesTheStrings() {
        let german = LanguageOverride.with("de") { "Capture".localized() }
        let english = LanguageOverride.with("en") { "Capture".localized() }
        #expect(english == "Capture")
        #expect(german != english)
    }
}

@MainActor
struct OffscreenRenderingTests {
    @Test func theEditorCanvasRendersOffScreen() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 1600, height: 1000), hue: 0.6, title: "Canvas"))
        let document = EditorDocument(image: image, fileURL: nil)
        document.add(Annotation(shape: .rectangle(CGRect(x: 236, y: 258, width: 860, height: 62)), color: .red, lineWidth: 8))
        let rendered = try #require(SnapshotRenderer.render(EditorView(document: document, onDone: {}, onDiscard: {}, onCopy: {}), size: CGSize(width: 1000, height: 600), appearance: .darkAqua))
        let pixels = try #require(PixelBuffer(rendered))
        #expect(pixels.width == 2000)
        let canvas = CGRect(x: 400, y: 300, width: 1200, height: 600)
        #expect(pixels.variance(in: canvas) > 100)
    }

    @Test func pixelComparisonHonoursTheTolerance() throws {
        let image = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 64, height: 40), hue: 0.3, title: ""))
        let other = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 64, height: 40), hue: 0.8, title: ""))
        let first = try #require(PixelBuffer(image))
        #expect(first.differentPixels(from: first, channelTolerance: 0) == 0)
        #expect((first.differentPixels(from: try #require(PixelBuffer(other)), channelTolerance: 24) ?? 0) > 100)
        let smaller = try #require(ScreenshotMode.sampleImage(size: CGSize(width: 32, height: 20), hue: 0.3, title: ""))
        #expect(first.differentPixels(from: try #require(PixelBuffer(smaller)), channelTolerance: 24) == nil)
    }

    @Test func pixelComparisonForgivesOnePixelShifts() throws {
        let reference = try #require(Self.stripe(at: 20))
        let shifted = try #require(Self.stripe(at: 21))
        #expect((shifted.differentPixels(from: reference, channelTolerance: 24) ?? 0) > 0)
        #expect(shifted.differentPixels(from: reference, channelTolerance: 24, searchRadius: SnapshotStore.searchRadius) == 0)
        let moved = try #require(Self.stripe(at: 30))
        #expect((moved.differentPixels(from: reference, channelTolerance: 24, searchRadius: SnapshotStore.searchRadius) ?? 0) > 0)
    }

    private static func stripe(at x: Int) -> PixelBuffer? {
        guard let context = CGContext(
            data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 2, height: 40))
        return context.makeImage().flatMap(PixelBuffer.init)
    }
}
