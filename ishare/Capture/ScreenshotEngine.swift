import AppKit
import Defaults
import ishareCore
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "ishare needs screen recording permission"
        case .displayNotFound: "The selected display is no longer available"
        case .windowNotFound: "The selected window is no longer available"
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    static var primaryHeight: CGFloat {
        primary?.frame.height ?? 0
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

@MainActor
enum ScreenshotEngine {
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        PermissionGuide.show(.screenRecording)
        return false
    }

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func excludedApplications(in content: SCShareableContent) -> [SCRunningApplication] {
        let ignored = Set(Defaults[.ignoredBundleIdentifiers])
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.applications.filter { app in
            app.bundleIdentifier == ownBundleID || ignored.contains(app.bundleIdentifier)
        }
    }

    static func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == screen.displayID }
    }

    static func baseConfiguration(pixelSize: CGSize, showsCursor: Bool) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let size = CGSize(width: max(1, pixelSize.width.rounded()), height: max(1, pixelSize.height.rounded()))
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.shouldBeOpaque = false
        return configuration
    }

    static func captureDisplay(_ display: SCDisplay, region: CGRect? = nil, in content: SCShareableContent, showsCursor: Bool? = nil) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications(in: content), exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let bounds = CGRect(origin: .zero, size: CGSize(width: display.width, height: display.height))
        let sourceRect = region.map { ScreenGeometry.clamp($0, to: bounds) } ?? bounds
        let configuration = baseConfiguration(
            pixelSize: CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale),
            showsCursor: showsCursor ?? Defaults[.screenshotShowsCursor]
        )
        configuration.sourceRect = sourceRect
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func captureWindow(_ window: SCWindow, includesShadow: Bool? = nil) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let includesShadow = includesShadow ?? Defaults[.windowShadow]
        let contentSize = filter.contentRect.size
        let configuration = baseConfiguration(
            pixelSize: CGSize(width: contentSize.width * scale, height: contentSize.height * scale),
            showsCursor: false
        )
        configuration.ignoreShadowsSingleWindow = !includesShadow
        if !includesShadow {
            configuration.width = Int((window.frame.width * scale).rounded())
            configuration.height = Int((window.frame.height * scale).rounded())
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func backdrops(for content: SCShareableContent) async -> [CGDirectDisplayID: CGImage] {
        var images: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            if let image = try? await captureDisplay(display, in: content, showsCursor: false) {
                images[display.displayID] = image
            }
        }
        return images
    }

    static func candidateWindows(in content: SCShareableContent) -> [SCWindow] {
        let ignored = Set(Defaults[.ignoredBundleIdentifiers])
        let ownBundleID = Bundle.main.bundleIdentifier
        let zOrder = windowZOrder()
        return content.windows
            .filter { window in
                guard window.isOnScreen, window.windowLayer == 0, window.frame.width >= 40, window.frame.height >= 40,
                    let app = window.owningApplication
                else { return false }
                return app.bundleIdentifier != ownBundleID && !ignored.contains(app.bundleIdentifier)
            }
            .sorted { (zOrder[$0.windowID] ?? .max) < (zOrder[$1.windowID] ?? .max) }
    }

    static func windowZOrder() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var order: [CGWindowID: Int] = [:]
        for (index, info) in list.enumerated() {
            if let number = info[kCGWindowNumber as String] as? CGWindowID {
                order[number] = index
            }
        }
        return order
    }

    static func crop(_ image: CGImage, toPoints rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = ScreenGeometry.pixelRect(for: rect, scale: scale)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return image.cropping(to: ScreenGeometry.clamp(pixelRect, to: bounds))
    }
}
