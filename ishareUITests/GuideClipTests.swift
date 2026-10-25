import AppKit
import XCTest

@MainActor
final class GuideClipTests: XCTestCase {
    static let scenes = ["capture", "editor", "region", "shelf"]
    static let fallbackFrameCounts = ["capture": 98, "editor": 90, "region": 90, "shelf": 98]
    static let framesPerSecond: Int32 = 15
    static let clipSize = CGSize(width: 1280, height: 800)
    static let posterSize = CGSize(width: 1280, height: 800)

    override func setUp() async throws {
        continueAfterFailure = false
    }

    nonisolated static func frameCount(in value: String?) -> Int? {
        guard let value, let range = value.range(of: "of=") else { return nil }
        return Int(value[range.upperBound...].prefix { $0.isNumber })
    }

    nonisolated static func frame(in value: String?) -> Int? {
        guard let value, let range = value.range(of: "frame=") else { return nil }
        return Int(value[range.upperBound...].prefix { $0.isNumber })
    }

    func testRecordGuideClips() async throws {
        let environment = ProcessInfo.processInfo.environment
        let requested = environment["ISHARE_GUIDE_SCENES"].map { $0.split(separator: ",").map(String.init) } ?? Self.scenes
        for scene in requested {
            try await record(scene)
        }
    }

    private func record(_ scene: String) async throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ishareScreenshotMode", "-ishareGuideScene", scene,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-NSInitialToolTipDelay", "600000",
        ]
        app.launch()
        defer { app.terminate() }
        let window = app.windows["ishare-screenshot"]
        XCTAssertTrue(window.waitForExistence(timeout: 20), "The \(scene) guide scene did not appear")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.995)).hover()
        try await Task.sleep(for: .seconds(2))
        let reported = Self.frameCount(in: window.value as? String)
        let total = try XCTUnwrap(reported ?? Self.fallbackFrameCounts[scene], "The \(scene) scene has no frame count")
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-guide", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clip = directory.appending(path: "guide-\(scene).mp4")
        let encoder = try ClipEncoder(url: clip, size: Self.clipSize, framesPerSecond: Self.framesPerSecond)
        let posterFrame = total * 7 / 10
        var poster: CGImage?
        for frame in 0 ... total {
            let image = try XCTUnwrap(window.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil), "Frame \(frame) of \(scene) has no image")
            try encoder.append(image)
            if frame == posterFrame {
                poster = image
            }
            if frame < total {
                window.typeKey("]", modifierFlags: [])
            }
            if frame == 1, reported != nil {
                XCTAssertEqual(Self.frame(in: window.value as? String), 2, "The \(scene) scene does not advance when the test presses ]")
            }
        }
        try await encoder.finish()
        if reported != nil {
            XCTAssertEqual(Self.frame(in: window.value as? String), total, "The \(scene) scene did not reach its last frame")
        }
        let clipAttachment = XCTAttachment(contentsOfFile: clip, uniformTypeIdentifier: "public.mpeg-4")
        clipAttachment.name = "guide-\(scene)"
        clipAttachment.lifetime = .keepAlways
        add(clipAttachment)
        if let poster, let data = ClipEncoder.jpeg(poster, size: Self.posterSize) {
            let posterAttachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
            posterAttachment.name = "guide-\(scene)-poster"
            posterAttachment.lifetime = .keepAlways
            add(posterAttachment)
        }
    }
}
