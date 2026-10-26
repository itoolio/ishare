import CoreGraphics
import Defaults
import Foundation
import ishareCore
import Testing
@testable import ishare

@MainActor
struct SelectionOverlayTests {
    @Test func crosshairGuidesAreOnAndTheLastRegionOutlineIsOffByDefault() {
        #expect(Defaults.Keys.showSelectionGuides.defaultValue)
        #expect(!Defaults.Keys.showLastRegionOutline.defaultValue)
    }

    @Test func overlayPreferencesAreExportedWithTheSettings() {
        #expect(SettingsTransfer.preferenceNames.contains(Defaults.Keys.showSelectionGuides.name))
        #expect(SettingsTransfer.preferenceNames.contains(Defaults.Keys.showLastRegionOutline.name))
    }

    @Test func overlayPreferencesAreSearchable() {
        let keywords = CaptureSettingsView.searchEntries.flatMap(\.keywords)
        #expect(keywords.contains("Show crosshair guides while selecting"))
        #expect(keywords.contains("Outline the last region while selecting"))
    }

    @Test func selectionToolDefaultsKeepTodaysBehavior() {
        #expect(Defaults.Keys.selectionConstraint.defaultValue == .free)
        #expect(Defaults.Keys.customSelectionSize.defaultValue == nil)
        #expect(Defaults.Keys.freezeScreenWhileSelecting.defaultValue)
        #expect(Defaults.Keys.multiRegionResult.defaultValue == .combined)
        #expect(!Defaults.Keys.menuCaptureIncludesParentWindow.defaultValue)
    }

    @Test func selectionToolPreferencesAreExportedAndSearchable() {
        let keys: [Defaults.Keys] = [
            .selectionConstraint, .customSelectionSize, .freezeScreenWhileSelecting, .multiRegionResult, .menuCaptureIncludesParentWindow,
        ]
        for key in keys {
            #expect(SettingsTransfer.preferenceNames.contains(key.name))
        }
        let keywords = CaptureSettingsView.searchEntries.flatMap(\.keywords)
        for keyword in ["Freeze the screen while selecting", "Multiple regions", "Combine into one image", "Save as separate captures", "Aspect ratio", "Capture Menu"] {
            #expect(keywords.contains(keyword))
        }
    }

    @Test func selectionConstraintsSurviveTheSettingsArchive() throws {
        let suite = "ishare.tests.selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = Defaults.Key<SelectionConstraint>("selectionConstraint", default: .free, suite: defaults)
        let custom = FixedSelectionSize(width: 640, height: 480, unit: .points)
        Defaults[key] = .fixed(custom)
        #expect(Defaults[key] == .fixed(custom))
        let archive = SettingsTransfer.makeArchive(
            includeHistory: false, includeSecrets: false, defaults: defaults, shortcuts: .init(names: { [] }, get: { _ in nil }, set: { _, _ in }))
        #expect(archive.preferences["selectionConstraint"] != nil)
    }

    @Test func settingsListEveryPresetAndTheCustomSize() {
        let custom = FixedSelectionSize(width: 800, height: 600, unit: .points)
        let choices = CaptureSelectionSettings.choices(custom: custom)
        #expect(choices.first == .free)
        #expect(choices.contains(.aspect(.portrait)))
        #expect(choices.contains(.fixed(.socialCard)))
        #expect(choices.last == .fixed(custom))
        #expect(CaptureSelectionSettings.choices(custom: .hd).count == 1 + AspectRatio.presets.count + FixedSelectionSize.presets.count)
        #expect(CaptureSelectionSettings.title(for: .fixed(.socialCard)).contains("1200 × 630"))
    }

    @Test func menuCaptureIsReachableFromTheURLSchemeAndTheCommandLine() {
        let parsed = try? URLSchemeParser.parse(URL(string: "ishare://capture/menu")!, fileAccess: URLSchemeFileAccess { _ in true }).get()
        #expect(parsed?.command == .capture(.menu))
        #expect(CLICaptureMode.menu.captureType == .MENU)
        #expect(AppCommand.all().contains { $0.id == "capture.menu" })
        #expect(CaptureDelay.effectiveSeconds(for: .MENU, explicit: nil, setting: .five) == 0)
    }

    @Test func savingNeverOverwritesAnEarlierCapture() {
        let directory = URL(fileURLWithPath: "/tmp/captures", isDirectory: true)
        let url = directory.appending(path: "ishare-1700000000-notes.png")
        var existing: Set<String> = [url.path, directory.appending(path: "ishare-1700000000-notes-2.png").path]
        #expect(ImageCaptureFlow.availableURL(url) { existing.contains($0.path) }.lastPathComponent == "ishare-1700000000-notes-3.png")
        existing.removeAll()
        #expect(ImageCaptureFlow.availableURL(url) { existing.contains($0.path) } == url)
    }

    @Test func separateCapturesAreFinalizedTogether() throws {
        let image = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage())
        var captured = CapturedImage(image: image, suffix: "one")
        captured.additionalCaptures = [CapturedImage(image: image, suffix: "two"), CapturedImage(image: image, suffix: "three")]
        let finalized = ImageCaptureFlow.finalize(captured)
        #expect(finalized.additionalCaptures.map(\.suffix) == ["two", "three"])
    }
}
