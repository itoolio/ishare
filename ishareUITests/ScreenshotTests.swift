import XCTest

final class ScreenshotTests: XCTestCase {
    static let scenes = ["menu", "editor", "uploaders", "assistant", "recording", "history"]

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["ISHARE_LANGUAGE"] ?? "en"
        let requested = environment["ISHARE_SCENES"].map { $0.split(separator: ",").map(String.init) } ?? Self.scenes
        for (index, scene) in requested.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-ishareScreenshotMode", "-ishareScene", scene, "-ishareLanguage", language, "-AppleLanguages", "(\(language))"]
            app.launch()
            let window = app.windows["ishare-screenshot"]
            XCTAssertTrue(window.waitForExistence(timeout: 20), "The \(scene) scene did not appear")
            Thread.sleep(forTimeInterval: 2.5)
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = String(format: "%02d_%@", index + 1, scene)
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
