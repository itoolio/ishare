import XCTest

final class EditorFlowTests: AppUITestCase {
    override func setUp() async throws {
        try await super.setUp()
        launch(scene: "editor")
        XCTAssertTrue(state.waitForExistence(timeout: 10), "The editor state probe is missing")
        assertState("annotations=0 undo=false redo=false")
    }

    private var state: XCUIElement {
        element("uitest.editor.state")
    }

    func testSelectingToolsHighlightsThem() {
        for tool in ["rectangle", "ellipse", "pen", "text", "select", "arrow"] {
            let button = element("editor.tool.\(tool)")
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tool) tool is missing")
            button.click()
            assertState("tool=\(tool)")
        }
    }

    func testDrawingARectangleCanBeUndoneAndRedone() {
        drawRectangle()
        assertState("annotations=1 undo=true redo=false")

        undo()
        assertState("annotations=0 undo=false redo=true")

        redo()
        assertState("annotations=1 undo=true redo=false")
    }

    func testDrawingALibraryShapeAndAMeasurement() {
        for tool in ["shapes", "measure"] {
            element("editor.tool.\(tool)").click()
            assertState("tool=\(tool)")
            drag(from: CGVector(dx: 0.35, dy: 0.35), to: CGVector(dx: 0.5, dy: 0.5))
        }
        assertState("annotations=2")
        assertState("kinds=shape,measure")
    }

    func testCopiedAnnotationsPasteAsNewOnes() {
        drawRectangle()
        element("editor.tool.select").click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49)).click()
        assertState("selected=1")
        window.typeKey("c", modifierFlags: [.command, .shift])
        window.typeKey("v", modifierFlags: [.command, .shift])
        assertState("annotations=2")
        assertState("kinds=rectangle,rectangle")
    }

    func testTheGridCanBeShown() {
        assertState("grid=false")
        let menu = element("editor.grid")
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The grid menu is missing")
        menu.click()
        let item = app.menuItems["Show Grid"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Show Grid is missing")
        item.click()
        assertState("grid=true")
    }

    func testArrangingNeedsASelection() {
        let arrange = element("editor.arrange")
        XCTAssertTrue(arrange.waitForExistence(timeout: 5), "The arrange menu is missing")
        XCTAssertFalse(arrange.isEnabled)
        drawRectangle()
        element("editor.tool.select").click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49)).click()
        assertState("selected=1")
        XCTAssertTrue(arrange.isEnabled)
    }

    func testDiscardClosesTheEditor() {
        drawRectangle()
        let discard = element("editor.discard")
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        window.typeKey(.delete, modifierFlags: .command)
        assertDisappears(window)
    }

    func testDoneClosesTheEditor() {
        drawRectangle()
        let done = element("editor.done")
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        window.typeKey(.return, modifierFlags: .command)
        assertDisappears(window)
    }

    private func drawRectangle(file: StaticString = #filePath, line: UInt = #line) {
        element("editor.tool.rectangle").click()
        assertState("tool=rectangle", file: file, line: line)
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.58))
        start.click(forDuration: 0.2, thenDragTo: end)
        assertState("annotations=1", file: file, line: line)
    }

    private func drag(from start: CGVector, to end: CGVector) {
        window.coordinate(withNormalizedOffset: start).click(forDuration: 0.2, thenDragTo: window.coordinate(withNormalizedOffset: end))
    }

    private func undo() {
        historyButton(identifier: "editor.undo", label: "Undo", key: "z", modifiers: .command)
    }

    private func redo() {
        historyButton(identifier: "editor.redo", label: "Redo", key: "z", modifiers: [.command, .shift])
    }

    private func historyButton(identifier: String, label: String, key: String, modifiers: XCUIElement.KeyModifierFlags) {
        for candidate in [element(identifier), window.buttons[label].firstMatch] where candidate.exists && candidate.isHittable {
            candidate.click()
            return
        }
        window.typeKey(key, modifierFlags: modifiers)
    }

    private func assertState(_ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        let probe = state
        waitFor("the editor state contains \(fragment)", file: file, line: line) {
            Self.describe(probe).contains(fragment)
        }
    }

    private static func describe(_ probe: XCUIElement) -> String {
        guard probe.exists else { return "" }
        return [probe.value as? String, probe.label].compactMap(\.self).joined(separator: " ")
    }
}
