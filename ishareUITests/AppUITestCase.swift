import XCTest

@MainActor
class AppUITestCase: XCTestCase {
    static let windowIdentifier = "ishare-uitest"

    var app: XCUIApplication!
    var window: XCUIElement!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
        app = nil
        window = nil
    }

    func launch(scene: String) {
        app = XCUIApplication()
        app.launchArguments = [
            "-ishareUITestMode", "-ishareSkipOnboarding", "-ishareScene", scene,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-NSInitialToolTipDelay", "600000",
        ]
        app.launch()
        window = app.windows[Self.windowIdentifier]
        XCTAssertTrue(window.waitForExistence(timeout: 20), "The \(scene) test window did not appear")
    }

    func element(_ identifier: String) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func waitFor(_ description: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: @escaping @MainActor () -> Bool) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting until \(description)", file: file, line: line)
    }

    func assertDisappears(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForNonExistence(timeout: timeout), "\(element) is still on screen", file: file, line: line)
    }
}
