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

struct PickableWindow: @unchecked Sendable {
    let window: SCWindow
    let classified: ClassifiedWindow

    var kind: WindowKind {
        classified.kind
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

    static func shareableContent(listing windowIDs: Set<CGWindowID>, timeout: Duration = .milliseconds(500)) async -> SCShareableContent? {
        let deadline = ContinuousClock.now + timeout
        while true {
            guard let content = try? await shareableContent() else { return nil }
            if windowIDs.isSubset(of: Set(content.windows.map(\.windowID))) || ContinuousClock.now >= deadline {
                return content
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
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
        let captures = content.displays.map { display in
            (display.displayID, Task { @MainActor in try? await captureDisplay(display, in: content, showsCursor: false) })
        }
        var images: [CGDirectDisplayID: CGImage] = [:]
        for (displayID, capture) in captures {
            images[displayID] = await capture.value
        }
        return images
    }

    static func prewarm() {
        guard hasPermission else { return }
        Task {
            _ = try? await shareableContent()
        }
    }

    static func candidateWindows(in content: SCShareableContent) -> [SCWindow] {
        pickableWindows(in: content).map(\.window)
    }

    static func pickableWindows(in content: SCShareableContent) -> [PickableWindow] {
        let classifier = windowClassifier(for: content)
        let zOrder = windowZOrder()
        return content.windows
            .compactMap { window -> PickableWindow? in
                let descriptor = windowDescriptor(window)
                return classifier.kind(of: descriptor).map { PickableWindow(window: window, classified: ClassifiedWindow(descriptor: descriptor, kind: $0)) }
            }
            .sorted { (zOrder[$0.window.windowID] ?? .max) < (zOrder[$1.window.windowID] ?? .max) }
    }

    static func windowDescriptor(_ window: SCWindow) -> WindowDescriptor {
        WindowDescriptor(
            id: window.windowID, layer: window.windowLayer, frame: window.frame, isOnScreen: window.isOnScreen,
            ownerPID: window.owningApplication?.processID, ownerBundleID: window.owningApplication?.bundleIdentifier, title: window.title
        )
    }

    static func windowClassifier(for content: SCShareableContent) -> WindowClassifier {
        let strips = NSScreen.screens.map { screen in
            let quartzFrame = ScreenGeometry.quartzToCocoa(screen.frame, primaryScreenHeight: NSScreen.primaryHeight)
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return WindowClassifier.menuBarStrip(forDisplay: quartzFrame, height: height)
        }
        return WindowClassifier(
            ownBundleID: Bundle.main.bundleIdentifier, ignoredBundleIDs: Set(Defaults[.ignoredBundleIdentifiers]),
            displayFrames: content.displays.map(\.frame), menuBarStrips: strips
        )
    }

    static func display(containing frame: CGRect, in content: SCShareableContent) -> SCDisplay? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return content.displays.first { $0.frame.contains(center) }
            ?? content.displays.first { $0.frame.intersects(frame) }
    }

    static let compositeShadowMargin: CGFloat = 28

    static func captureComposite(of windows: [SCWindow], on display: SCDisplay) async throws -> (image: CGImage, region: CGRect)? {
        guard let bounds = WindowClassifier.captureBounds(of: windows.map(\.frame), shadowMargin: compositeShadowMargin, within: display.frame) else { return nil }
        let region = bounds.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let filter = SCContentFilter(display: display, including: windows)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = baseConfiguration(pixelSize: CGSize(width: region.width * scale, height: region.height * scale), showsCursor: false)
        configuration.sourceRect = region
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, region)
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
