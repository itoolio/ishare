import AppKit
import BezelNotification
import Defaults
import Foundation
import ishareCore
@preconcurrency import ScreenCaptureKit

enum CaptureType: String, CaseIterable, Sendable {
    case REGION
    case WINDOW
    case SCREEN
    case SCROLLING
    case LAST_REGION
    case TEXT
    case MENU
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
    var source = CaptureSource()
    var additionalCaptures: [CapturedImage] = []
}

struct CaptureSource: Hashable, Sendable {
    var bundleIdentifier: String?
    var appName: String?
    var windowTitle: String?
}

@MainActor
enum ImageCaptureFlow {
    static func capture(type: CaptureType, display: Int = 1, delay: Int = 0) async -> CapturedImage? {
        if let fixture = ScreenshotMode.fixtureCapture() { return fixture }
        return await withCaptureContent { content in
            switch type {
            case .REGION:
                try await captureRegion(content: content, delay: delay, allowsMultipleRegions: true)
            case .TEXT:
                try await captureRegion(content: content, delay: delay)
            case .MENU:
                try await captureMenu(content: content)
            case .WINDOW:
                try await captureWindow(content: content, delay: delay)
            case .SCREEN:
                try await captureScreen(display: display, content: content, delay: delay)
            case .SCROLLING:
                try await ScrollingCapture.run(content: content)
            case .LAST_REGION:
                try await captureLastRegion(displayID: nil, content: content, delay: delay)
            }
        }
    }

    static func captureLastRegion(display: CGDirectDisplayID? = nil) async -> CapturedImage? {
        await withCaptureContent { content in
            try await captureLastRegion(displayID: display, content: content)
        }
    }

    static func captureForRecognition() async -> CGImage? {
        await withCaptureContent(finalizing: false) { content in
            try await captureRegion(content: content)
        }?.image
    }

    private static func withCaptureContent(finalizing: Bool = true, _ body: (SCShareableContent) async throws -> CapturedImage?) async -> CapturedImage? {
        guard ScreenshotEngine.ensurePermission() else {
            Log.capture.error("Screen recording permission is missing")
            BezelNotification.show(messageText: "Missing permission".localized(), icon: ToastIcon)
            return nil
        }
        do {
            let content = try await ScreenshotEngine.shareableContent()
            let captured = try await body(content)
            return finalizing ? captured.map(finalize) : captured
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
            return nil
        }
    }

    static func contentAfterCountdown(_ delay: Int, content: SCShareableContent) async throws -> SCShareableContent? {
        guard delay > 0 else { return content }
        guard await CaptureCountdown.run(seconds: delay) else { return nil }
        return try await ScreenshotEngine.shareableContent()
    }

    static func captureRegion(content: SCShareableContent, delay: Int = 0, allowsMultipleRegions: Bool = false) async throws -> CapturedImage? {
        let frontmost = frontmostAppName()
        let source = frontmostSource(in: content)
        let blursPrivateApps = CaptureSettings.current(for: source.bundleIdentifier).blursPrivateApps
        let loader = SelectionBackdropLoader(
            content: content, blursPrivateApps: blursPrivateApps, mode: SelectionFreezeMode(prefersFrozen: Defaults[.freezeScreenWhileSelecting]))
        loader.startIfFrozen()
        let lastRegions = LastRegionStore.regions(for: content.displays.map(\.displayID))
        let options = RegionSelector.Options(
            hint: "Select the area to capture".localized(), lastRegions: lastRegions, awaitsBackdrops: loader.mode.loadsBackdrops,
            allowsMultipleRegions: allowsMultipleRegions, allowsFreezeToggle: true, freezeMode: loader.mode,
            liveSampler: LiveMagnifierSampler(content: content),
            onFreezeModeChange: { mode in loader.change(to: mode) }
        )
        let selection = await RegionSelector.selectRegions(options: options)
        let imaging = RegionImaging(
            content: content, delay: delay, mode: loader.mode, backdrops: await loader.currentBackdrops(), frontmost: frontmost, source: source)
        switch selection {
        case let .regions(areas):
            if let last = areas.last, let displayID = last.screen.displayID {
                LastRegionStore.remember(last.rect, for: displayID)
            }
            return try await imaging.images(for: areas)
        case let .single(.region(screen, rect)):
            guard let displayID = screen.displayID else { return nil }
            LastRegionStore.remember(rect, for: displayID)
            return try await imaging.image(screen: screen, region: rect)
        case let .single(.fullScreen(screen)):
            return try await imaging.image(screen: screen, region: nil)
        case .single(.switchToWindow):
            return try await captureWindow(content: content, delay: delay)
        case .single(.cancelled):
            return nil
        }
    }

    static func captureLastRegion(displayID: CGDirectDisplayID?, content: SCShareableContent, delay: Int = 0) async throws -> CapturedImage? {
        let displayIDs = content.displays.map(\.displayID)
        guard let target = displayID ?? LastRegionStore.preferredDisplay(among: displayIDs, underMouse: NSScreen.underMouse?.displayID),
            displayIDs.contains(target),
            let rect = LastRegionStore.region(for: target)
        else {
            return try await captureRegion(content: content, delay: delay)
        }
        LastRegionStore.remember(rect, for: target)
        guard let live = try await contentAfterCountdown(delay, content: content) else { return nil }
        return try await captureDisplayImage(displayID: target, region: rect, content: live, suffix: frontmostAppName())
    }

    static func captureWindow(content: SCShareableContent, delay: Int = 0) async throws -> CapturedImage? {
        let outcome = await WindowPicker.pick(from: ScreenshotEngine.pickableWindows(in: content))
        switch outcome {
        case let .window(picked):
            guard await CaptureCountdown.run(seconds: delay) else { return nil }
            try await Task.sleep(for: .milliseconds(60))
            if picked.kind == .popup {
                return try await capturePopup(picked.window, content: content)
            }
            let window = picked.window
            let source = windowSource(window)
            let settings = CaptureSettings.current(for: source.bundleIdentifier)
            let image = try await ScreenshotEngine.captureWindow(window, includesShadow: settings.includesWindowShadow)
            let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
            return CapturedImage(
                image: settings.blursPrivateApps ? PrivacyFilter.redactWindow(image, window: window, scale: scale) : image,
                suffix: window.owningApplication?.applicationName ?? "window",
                isWindow: true,
                pointScale: scale,
                source: source
            )
        case .switchToRegion:
            return try await captureRegion(content: content, delay: delay)
        case .cancelled:
            return nil
        }
    }

    static let menuCaptureCountdown = 3

    static func captureMenu(content: SCShareableContent) async throws -> CapturedImage? {
        guard await CaptureCountdown.run(seconds: menuCaptureCountdown) else { return nil }
        let live = try await ScreenshotEngine.shareableContent()
        let pickables = ScreenshotEngine.pickableWindows(in: live)
        let pointer = ScreenGeometry.cocoaPointToQuartz(NSEvent.mouseLocation, primaryScreenHeight: NSScreen.primaryHeight)
        guard let index = WindowClassifier.menuTarget(at: pointer, in: pickables.map(\.classified)) else {
            BezelNotification.show(messageText: "No open menu found".localized(), icon: ToastIcon)
            return nil
        }
        return try await capturePopup(pickables[index].window, content: live)
    }

    static func capturePopup(_ window: SCWindow, content: SCShareableContent) async throws -> CapturedImage? {
        let live = (try? await ScreenshotEngine.shareableContent()) ?? content
        let pickables = ScreenshotEngine.pickableWindows(in: live)
        let classified = pickables.map(\.classified)
        let source = windowSource(window)
        let settings = CaptureSettings.current(for: source.bundleIdentifier)
        let suffix = window.owningApplication?.applicationName ?? "menu"
        var windows = [window]
        if let index = pickables.firstIndex(where: { $0.window.windowID == window.windowID }) {
            var indices = WindowClassifier.relatedPopups(of: index, in: classified)
            if Defaults[.menuCaptureIncludesParentWindow], let parent = WindowClassifier.parentWindow(of: index, in: classified) {
                indices.append(parent)
            }
            windows = indices.isEmpty ? [window] : indices.map { pickables[$0].window }
        }
        if windows.count > 1, let display = ScreenshotEngine.display(containing: window.frame, in: live),
            let composite = try await ScreenshotEngine.captureComposite(of: windows, on: display)
        {
            let geometry = PrivacyFilter.geometry(displayID: display.displayID, region: composite.region, image: composite.image)
            let image = settings.blursPrivateApps ? PrivacyFilter.redact(composite.image, geometry: geometry, content: live) : composite.image
            return CapturedImage(image: image, suffix: suffix, isWindow: true, pointScale: geometry.scale, source: source)
        }
        let image = try await ScreenshotEngine.captureWindow(window, includesShadow: true)
        let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
        return CapturedImage(
            image: settings.blursPrivateApps ? PrivacyFilter.redactWindow(image, window: window, scale: scale) : image,
            suffix: suffix, isWindow: true, pointScale: scale, source: source
        )
    }

    static func windowSource(_ window: SCWindow) -> CaptureSource {
        CaptureSource(
            bundleIdentifier: window.owningApplication?.bundleIdentifier,
            appName: window.owningApplication?.applicationName,
            windowTitle: window.title
        )
    }

    static func captureScreen(display index: Int, content: SCShareableContent, delay: Int = 0) async throws -> CapturedImage? {
        guard let screen = NSScreen.screens[safe: index - 1] ?? NSScreen.main else { throw CaptureError.displayNotFound }
        guard let live = try await contentAfterCountdown(delay, content: content) else { return nil }
        return try await captureScreen(screen: screen, content: live)
    }

    static func captureScreen(screen: NSScreen, content: SCShareableContent) async throws -> CapturedImage? {
        guard let displayID = screen.displayID else { throw CaptureError.displayNotFound }
        return try await captureDisplayImage(displayID: displayID, region: nil, content: content, suffix: screen.captureSuffix)
    }

    static func captureDisplayImage(
        displayID: CGDirectDisplayID, region: CGRect?, content: SCShareableContent, suffix: String?, source: CaptureSource? = nil
    ) async throws -> CapturedImage {
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.displayNotFound }
        let source = source ?? frontmostSource(in: content)
        let image = try await ScreenshotEngine.captureDisplay(display, region: region, in: content)
        let geometry = PrivacyFilter.geometry(displayID: displayID, region: region, image: image)
        let redacted =
            CaptureSettings.current(for: source.bundleIdentifier).blursPrivateApps
            ? PrivacyFilter.redact(image, geometry: geometry, content: content)
            : image
        return CapturedImage(image: redacted, suffix: suffix, geometry: geometry, source: source)
    }

    static func finalize(_ captured: CapturedImage) -> CapturedImage {
        var result = captured
        result.additionalCaptures = result.additionalCaptures.map(finalize)
        result.image = PrivacyFilter.hideMenuBarIfNeeded(result.image, geometry: result.geometry)
        result.image = beautifyIfNeeded(result)
        return result
    }

    static func beautifyIfNeeded(_ captured: CapturedImage) -> CGImage {
        let addsBackground = CaptureSettings.current(for: captured.source.bundleIdentifier).addsBackground
        guard addsBackground, captured.isWindow || !Defaults[.beautifyWindowsOnly] else { return captured.image }
        let scale = captured.pointScale ?? captured.geometry?.scale ?? NSScreen.main?.backingScaleFactor ?? 2
        let style = BeautifyStyle.current(scale: scale, windowTitle: captured.source.windowTitle)
        return Beautifier.apply(to: captured.image, style: style) ?? captured.image
    }

    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    static func frontmostSource(in content: SCShareableContent) -> CaptureSource {
        guard let app = NSWorkspace.shared.frontmostApplication else { return CaptureSource() }
        let zOrder = ScreenshotEngine.windowZOrder()
        let title = content.windows
            .filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.isOnScreen }
            .sorted { (zOrder[$0.windowID] ?? .max) < (zOrder[$1.windowID] ?? .max) }
            .compactMap(\.title)
            .first { !$0.isEmpty }
        return CaptureSource(bundleIdentifier: app.bundleIdentifier, appName: app.localizedName, windowTitle: title)
    }

    static func fileName(for captured: CapturedImage, ext: String) -> String {
        let prefix = CaptureSettings.current(for: captured.source.bundleIdentifier).fileNamePrefix
        guard Defaults[.nameFilesAfterWindowTitle] else {
            return CaptureFileName.make(prefix: prefix, suffix: captured.suffix, ext: ext)
        }
        return WindowTitleName.fileName(
            title: captured.source.windowTitle, appName: captured.source.appName,
            fallbackPrefix: prefix, fallbackSuffix: captured.suffix, ext: ext
        )
    }

    static func save(_ captured: CapturedImage) throws -> URL {
        let fileType = Defaults[.captureFileType]
        let url = availableURL(SaveLocation.fileURL(for: .captures, fileName: fileName(for: captured, ext: fileType.rawValue)))
        try ImageEncoder.write(captured.image, as: fileType, to: url)
        return url
    }

    static func availableURL(_ url: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        guard exists(url) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        for index in 2 ... 999 {
            let candidate = directory.appending(path: ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)", directoryHint: .notDirectory)
            if !exists(candidate) {
                return candidate
            }
        }
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
