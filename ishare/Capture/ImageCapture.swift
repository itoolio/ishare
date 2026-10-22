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
    case LAST_REGION
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
    var image: CGImage
    let suffix: String?
    var geometry: CaptureGeometry?
    var isWindow = false
    var pointScale: CGFloat?
}

@MainActor
enum ImageCaptureFlow {
    static func capture(type: CaptureType, display: Int = 1) async -> CapturedImage? {
        await withCaptureContent { content in
            switch type {
            case .REGION:
                try await captureRegion(content: content)
            case .WINDOW:
                try await captureWindow(content: content)
            case .SCREEN:
                try await captureScreen(display: display, content: content)
            case .SCROLLING:
                try await ScrollingCapture.run(content: content)
            case .LAST_REGION:
                try await captureLastRegion(displayID: nil, content: content)
            }
        }
    }

    static func captureLastRegion(display: CGDirectDisplayID? = nil) async -> CapturedImage? {
        await withCaptureContent { content in
            try await captureLastRegion(displayID: display, content: content)
        }
    }

    private static func withCaptureContent(_ body: (SCShareableContent) async throws -> CapturedImage?) async -> CapturedImage? {
        guard ScreenshotEngine.ensurePermission() else {
            Log.capture.error("Screen recording permission is missing")
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return nil
        }
        do {
            let content = try await ScreenshotEngine.shareableContent()
            return try await body(content).map(finalize)
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
            return nil
        }
    }

    static func captureRegion(content: SCShareableContent) async throws -> CapturedImage? {
        let frontmost = frontmostAppName()
        let backdrops = await PrivacyFilter.redactBackdrops(ScreenshotEngine.backdrops(for: content), content: content)
        let lastRegions = LastRegionStore.regions(for: content.displays.map(\.displayID))
        let outcome = await RegionSelector.select(options: .init(backdrops: backdrops, showsMagnifier: Defaults[.showMagnifier], lastRegions: lastRegions))
        switch outcome {
        case let .region(screen, rect):
            guard let displayID = screen.displayID else { return nil }
            LastRegionStore.remember(rect, for: displayID)
            if let backdrop = backdrops[displayID] {
                let geometry = PrivacyFilter.geometry(displayID: displayID, region: rect, scale: CGFloat(backdrop.width) / screen.frame.width)
                return ScreenshotEngine.crop(backdrop, toPoints: rect, scale: geometry.scale).map {
                    CapturedImage(image: $0, suffix: frontmost, geometry: geometry)
                }
            }
            return try await captureDisplayImage(displayID: displayID, region: rect, content: content, suffix: frontmost)
        case let .fullScreen(screen):
            guard let displayID = screen.displayID else { return nil }
            if let backdrop = backdrops[displayID] {
                let geometry = PrivacyFilter.geometry(displayID: displayID, region: nil, scale: CGFloat(backdrop.width) / screen.frame.width)
                return CapturedImage(image: backdrop, suffix: screen.captureSuffix, geometry: geometry)
            }
            return try await captureScreen(screen: screen, content: content)
        case .switchToWindow:
            return try await captureWindow(content: content, allowsRegionMode: false)
        case .cancelled:
            return nil
        }
    }

    static func captureLastRegion(displayID: CGDirectDisplayID?, content: SCShareableContent) async throws -> CapturedImage? {
        let displayIDs = content.displays.map(\.displayID)
        guard let target = displayID ?? LastRegionStore.preferredDisplay(among: displayIDs, underMouse: NSScreen.underMouse?.displayID),
              displayIDs.contains(target),
              let rect = LastRegionStore.region(for: target)
        else {
            return try await captureRegion(content: content)
        }
        LastRegionStore.remember(rect, for: target)
        return try await captureDisplayImage(displayID: target, region: rect, content: content, suffix: frontmostAppName())
    }

    static func captureWindow(content: SCShareableContent, allowsRegionMode: Bool = true) async throws -> CapturedImage? {
        let outcome = await WindowPicker.pick(from: ScreenshotEngine.candidateWindows(in: content), allowsRegionMode: allowsRegionMode)
        switch outcome {
        case let .window(window):
            try await Task.sleep(for: .milliseconds(60))
            let image = try await ScreenshotEngine.captureWindow(window)
            let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
            return CapturedImage(
                image: PrivacyFilter.redactWindow(image, window: window, scale: scale),
                suffix: window.owningApplication?.applicationName ?? "window",
                isWindow: true,
                pointScale: scale
            )
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
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
        return try await captureDisplayImage(displayID: displayID, region: nil, content: content, suffix: screen.captureSuffix)
    }

    static func captureDisplayImage(displayID: CGDirectDisplayID, region: CGRect?, content: SCShareableContent, suffix: String?) async throws -> CapturedImage {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.displayNotFound }
        let image = try await ScreenshotEngine.captureDisplay(display, region: region, in: content)
        let geometry = PrivacyFilter.geometry(displayID: displayID, region: region, image: image)
        return CapturedImage(image: PrivacyFilter.redact(image, geometry: geometry, content: content), suffix: suffix, geometry: geometry)
    }

    static func finalize(_ captured: CapturedImage) -> CapturedImage {
        var result = captured
        result.image = PrivacyFilter.hideMenuBarIfNeeded(result.image, geometry: result.geometry)
        result.image = beautifyIfNeeded(result)
        return result
    }

    static func beautifyIfNeeded(_ captured: CapturedImage) -> CGImage {
        guard Defaults[.beautifyEnabled], captured.isWindow || !Defaults[.beautifyWindowsOnly] else { return captured.image }
        let scale = captured.pointScale ?? captured.geometry?.scale ?? NSScreen.main?.backingScaleFactor ?? 2
        let style = BeautifyStyle(
            background: Defaults[.beautifyBackground],
            solidColor: CaptureColor(hex: Defaults[.beautifySolidColor]) ?? CaptureColor(red: 0.12, green: 0.12, blue: 0.18),
            padding: Defaults[.beautifyPadding],
            cornerRadius: Defaults[.beautifyCornerRadius],
            shadow: Defaults[.beautifyShadow],
            scale: scale
        )
        return Beautifier.apply(to: captured.image, style: style) ?? captured.image
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
