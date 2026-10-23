import XCTest

final class MenuAccessibilityTests: AppUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        launch(scene: "menu")
    }

    func testIconOnlyControlsAreReachableByLabel() {
        for label in ["Open History Window", "Upload Destination", "More"] {
            let control = window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(label) is not reachable by its accessibility label")
        }
    }

    func testAfterCaptureChipsReportTheirState() {
        for title in ["Copy to Clipboard", "Open in Finder"] {
            let chip = window.buttons[title].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(title) chip is missing")
            let value = chip.value as? String
            XCTAssertTrue(value == "On" || value == "Off", "\(title) chip reports \(String(describing: value)) instead of On or Off")
            XCTAssertEqual(value == "On", chip.isSelected, "\(title) chip value and selection disagree")
        }
    }
}

final class EditorAccessibilityTests: AppUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        launch(scene: "editor")
    }

    func testToolsAreReachableByLabelAndReportTheSelection() {
        for (identifier, label) in [("rectangle", "Rectangle"), ("arrow", "Arrow"), ("text", "Text")] {
            let tool = element("editor.tool.\(identifier)")
            XCTAssertTrue(tool.waitForExistence(timeout: 5), "\(identifier) tool is missing")
            XCTAssertEqual(tool.label, label)
            tool.click()
            waitFor("\(label) is reported as selected") { tool.isSelected }
        }
    }

    func testPanelTogglesAreLabeled() {
        for label in ["Layers", "Image Actions"] {
            let control = window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(label) is not reachable by its accessibility label")
        }
    }
}
