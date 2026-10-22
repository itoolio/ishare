import AppKit
import BezelNotification
import Defaults
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureType: String, CaseIterable, Sendable {
    case REGION
    case WINDOW
    case SCREEN
    case SCROLLING
}

enum FileType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case PNG = "png"
    case JPG = "jpg"
    case PDF = "pdf"
    case TIFF = "tiff"
    case HEIC = "heic"
    var id: Self { self }
}

struct CapturedImage {
    let image: CGImage
    let suffix: String?
}

@MainActor
enum ImageCaptureFlow {
    static func capture(type: CaptureType, display: Int = 1) async -> CapturedImage? {
        guard ScreenshotEngine.ensurePermission() else {
            Log.capture.error("Screen recording permission is missing")
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return nil
        }
        do {
            let content = try await ScreenshotEngine.shareableContent()
            switch type {
            case .REGION:
                return try await captureRegion(content: content)
            case .WINDOW:
                return try await captureWindow(content: content)
            case .SCREEN:
                return try await captureScreen(display: display, content: content)
            case .SCROLLING:
                return try await ScrollingCapture.run(content: content)
            }
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
            return nil
        }
    }

    static func captureRegion(content: SCShareableContent) async throws -> CapturedImage? {
        let frontmost = frontmostAppName()
        let backdrops = await ScreenshotEngine.backdrops(for: content)
        let outcome = await RegionSelector.select(options: .init(backdrops: backdrops, showsMagnifier: Defaults[.showMagnifier]))
        switch outcome {
        case let .region(screen, rect):
            guard let displayID = screen.displayID else { return nil }
            if let backdrop = backdrops[displayID] {
                let scale = CGFloat(backdrop.width) / screen.frame.width
                return ScreenshotEngine.crop(backdrop, toPoints: rect, scale: scale).map { CapturedImage(image: $0, suffix: frontmost) }
            }
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.displayNotFound }
            return try await CapturedImage(image: ScreenshotEngine.captureDisplay(display, region: rect, in: content), suffix: frontmost)
        case let .fullScreen(screen):
            guard let displayID = screen.displayID else { return nil }
            if let backdrop = backdrops[displayID] {
                return CapturedImage(image: backdrop, suffix: screen.captureSuffix)
            }
            return try await captureScreen(screen: screen, content: content)
        case .switchToWindow:
            return try await captureWindow(content: content, allowsRegionMode: false)
        case .cancelled:
            return nil
        }
    }

    static func captureWindow(content: SCShareableContent, allowsRegionMode: Bool = true) async throws -> CapturedImage? {
        let outcome = await WindowPicker.pick(from: ScreenshotEngine.candidateWindows(in: content), allowsRegionMode: allowsRegionMode)
        switch outcome {
        case let .window(window):
            try await Task.sleep(for: .milliseconds(60))
            let image = try await ScreenshotEngine.captureWindow(window)
            return CapturedImage(image: image, suffix: window.owningApplication?.applicationName ?? "window")
        case .switchToRegion:
            return try await captureRegion(content: content)
        case .cancelled:
            return nil
        }
    }

    static func captureScreen(display index: Int, content: SCShareableContent) async throws -> CapturedImage? {
        guard let screen = NSScreen.screens[safe: index - 1] ?? NSScreen.main else { throw CaptureError.displayNotFound }
        return try await captureScreen(screen: screen, content: content)
    }

    static func captureScreen(screen: NSScreen, content: SCShareableContent) async throws -> CapturedImage? {
        guard let display = ScreenshotEngine.display(for: screen, in: content) else { throw CaptureError.displayNotFound }
        let image = try await ScreenshotEngine.captureDisplay(display, in: content)
        return CapturedImage(image: image, suffix: screen.captureSuffix)
    }

    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static func save(_ captured: CapturedImage) throws -> URL {
        let fileType = Defaults[.captureFileType]
        let fileName = CaptureFileName.make(prefix: Defaults[.captureFileName], suffix: captured.suffix, ext: fileType.rawValue)
        let url = SaveLocation.fileURL(for: .captures, fileName: fileName)
        try ImageEncoder.write(captured.image, as: fileType, to: url)
        return url
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSScreen {
    var captureSuffix: String {
        let size = "\(Int(frame.width))x\(Int(frame.height))"
        guard let displayID else { return "screen" }
        return CGDisplayIsMain(displayID) != 0 ? "main-\(size)" : "display-\(size)"
    }
}
