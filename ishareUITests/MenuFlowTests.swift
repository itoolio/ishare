import XCTest

final class MenuFlowTests: AppUITestCase {
    static let tiles = [
        "menu.capture.region", "menu.capture.window", "menu.capture.screen", "menu.capture.scrolling",
        "menu.record.screen", "menu.record.region",
        "menu.destination", "menu.settings", "menu.more", "menu.history",
    ]
    static let seededUploaders = ["Imgur", "chibisafe", "cloudflare r2", "zipline"]

    override func setUp() async throws {
        try await super.setUp()
        launch(scene: "menu")
    }

    func testTilesExistAndAreHittable() {
        for identifier in Self.tiles {
            let tile = element(identifier)
            XCTAssertTrue(tile.waitForExistence(timeout: 5), "\(identifier) is missing")
            XCTAssertTrue(tile.isHittable, "\(identifier) is not hittable")
        }
    }

    func testFormatSwitchChangesTheRecordTiles() {
        XCTAssertTrue(element("menu.record.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("menu.record.region").exists)

        formatSegment("GIF").click()
        XCTAssertTrue(element("menu.record.gif").waitForExistence(timeout: 5))
        XCTAssertTrue(element("menu.record.regiongif").exists)
        assertDisappears(element("menu.record.screen"))
        XCTAssertFalse(element("menu.record.region").exists)

        formatSegment("Video").click()
        XCTAssertTrue(element("menu.record.screen").waitForExistence(timeout: 5))
        XCTAssertTrue(element("menu.record.region").exists)
        assertDisappears(element("menu.record.gif"))
        XCTAssertFalse(element("menu.record.regiongif").exists)
    }

    func testAfterCaptureChipsToggle() {
        assertToggles(chip: "Copy to Clipboard", startsOn: true)
        assertToggles(chip: "Open in Finder", startsOn: false)
        assertToggles(chip: "AirDrop", startsOn: true)
        assertToggles(chip: "Photos", startsOn: false)
    }

    func testDestinationPillListsTheUploaders() {
        let pill = element("menu.destination")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.click()
        for name in Self.seededUploaders {
            XCTAssertTrue(app.menuItems[name].waitForExistence(timeout: 5), "\(name) is not listed")
        }
        app.menuItems["zipline"].click()
        assertDisappears(app.menuItems["chibisafe"])
        let pillText = pill.staticTexts.matching(Self.mentioning("zipline")).firstMatch
        waitFor("the pill shows the selected uploader") {
            (pill.value as? String)?.contains("zipline") == true || pill.label.contains("zipline") || pill.title.contains("zipline") || pillText.exists
        }
    }

    private static func mentioning(_ text: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
    }

    private func formatSegment(_ title: String) -> XCUIElement {
        let picker = element("menu.record.format")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "The Video/GIF switch is missing")
        for candidate in [picker.radioButtons[title], picker.buttons[title], window.radioButtons[title]] where candidate.exists {
            return candidate
        }
        return picker.descendants(matching: .any)[title].firstMatch
    }

    private func afterCaptureSummary(mentions title: String) -> XCUIElement {
        window.staticTexts.matching(Self.mentioning(title)).firstMatch
    }

    private func assertToggles(chip title: String, startsOn: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let chip = window.buttons[title].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "\(title) chip is missing", file: file, line: line)
        XCTAssertTrue(chip.isHittable, "\(title) chip is not hittable", file: file, line: line)
        XCTAssertEqual(chip.isSelected, startsOn, "\(title) chip starts in the wrong state", file: file, line: line)
        XCTAssertEqual(afterCaptureSummary(mentions: title).exists, startsOn, file: file, line: line)

        let summary = afterCaptureSummary(mentions: title)
        for expected in [!startsOn, startsOn] {
            chip.click()
            waitFor("\(title) is \(expected ? "on" : "off")", file: file, line: line) {
                chip.isSelected == expected && summary.exists == expected
            }
        }
    }
}
