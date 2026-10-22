import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    static let scenes = ["menu", "editor", "uploaders", "assistant", "recording", "history"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["ISHARE_LANGUAGE"] ?? "en"
        let requested = environment["ISHARE_SCENES"].map { $0.split(separator: ",").map(String.init) } ?? Self.scenes
        let outputDirectory = environment["ISHARE_SCREENSHOT_DIR"]
        for (index, scene) in requested.enumerated() {
            let name = String(format: "%02d_%@", index + 1, scene)
            let app = XCUIApplication()
            app.launchArguments = [
                "-ishareScreenshotMode", "-ishareScene", scene,
                "-AppleLanguages", "(\(language))", "-NSInitialToolTipDelay", "600000",
            ]
            if let outputDirectory {
                app.launchArguments += ["-ishareScreenshotOutput", "\(outputDirectory)/\(name).png"]
            }
            app.launch()
            let window = app.windows["ishare-screenshot"]
            XCTAssertTrue(window.waitForExistence(timeout: 20), "The \(scene) scene did not appear")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.99)).hover()
            Thread.sleep(forTimeInterval: outputDirectory == nil ? 2.5 : 4)
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
