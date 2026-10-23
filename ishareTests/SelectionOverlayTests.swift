import Defaults
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
}
