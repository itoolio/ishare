import AppKit
import XCTest

final class UploadFlowTests: AppUITestCase {
    private var server: StubUploadServer!

    override func setUp() async throws {
        try await super.setUp()
        server = StubUploadServer()
        try server.start()
        NSPasteboard.general.clearContents()
        launch(scene: "menu", extraArguments: [
            "-ishareUITestCaptureSource", "fixture",
            "-ishareUITestUploadURL", server.uploadURL,
        ])
    }

    override func tearDown() async throws {
        try await super.tearDown()
        server?.stop()
        server = nil
    }

    func testCaptureUploadsToTheServerAndShowsTheLink() throws {
        let historyState = element("uitest.history.state")
        XCTAssertTrue(historyState.waitForExistence(timeout: 5), "The history probe is missing")
        XCTAssertEqual(Self.text(of: historyState), "history=0 latest=none")

        let regionTile = element("menu.capture.region")
        XCTAssertTrue(regionTile.waitForExistence(timeout: 5))
        regionTile.click()

        waitFor("the stub server received the upload", timeout: 20) { !self.server.uploads.isEmpty }
        let upload = try XCTUnwrap(server.uploads.first)
        XCTAssertEqual(upload.path, "/upload")
        XCTAssertGreaterThan(upload.bodySize, 1000, "The upload carried no image")

        let toastURL = app.descendants(matching: .any).matching(identifier: "toast.url").firstMatch
        XCTAssertTrue(toastURL.waitForExistence(timeout: 15), "The toast did not show the uploaded link")
        waitFor("the toast shows the returned URL", timeout: 5) {
            Self.text(of: toastURL).contains(upload.returnedURL)
        }

        waitFor("the clipboard holds the returned URL", timeout: 5) {
            NSPasteboard.general.string(forType: .string) == upload.returnedURL
        }

        waitFor("the history has the upload", timeout: 5) {
            Self.text(of: historyState) == "history=1 latest=\(upload.returnedURL)"
        }
        XCTAssertEqual(server.uploads.count, 1, "The capture was uploaded more than once")
    }

    private static func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }
}
