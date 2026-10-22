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
