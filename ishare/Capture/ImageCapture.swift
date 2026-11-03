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
    case ALL_DISPLAYS
}

enum FileType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case PNG = "png"
    case JPG = "jpg"
    case PDF = "pdf"
    case TIFF = "tiff"
    case HEIC = "heic"
    case WEBP = "webp"
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
            case .ALL_DISPLAYS:
                try await captureAllDisplays(content: content, delay: delay)
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
            let prefetched = await SelectionPrefetch.takeContent()
            let content = if let prefetched { prefetched } else { try await ScreenshotEngine.shareableContent() }
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
        let started = ProcessInfo.processInfo.systemUptime
        var order = SelectionOrderLog(expectsFreezeFrames: loader.mode.loadsBackdrops)
        let backdrops = await loader.captureBeforeSelectionIfFrozen()
        if !backdrops.isEmpty {
            order.record(.freezeFramesReady(at: ProcessInfo.processInfo.systemUptime))
        }
        let readyMilliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        let lastRegions = LastRegionStore.regions(for: content.displays.map(\.displayID))
        let options = RegionSelector.Options(
            backdrops: backdrops, hint: "Select the area to capture".localized(), lastRegions: lastRegions,
            snapWindowFrames: ScreenshotEngine.candidateWindows(in: content).map(\.frame),
            allowsMultipleRegions: allowsMultipleRegions, allowsFreezeToggle: true, freezeMode: loader.mode,
            liveSampler: LiveMagnifierSampler(content: content),
            onFreezeModeChange: { mode in loader.change(to: mode) }
        )
        var shownOptions = options
        shownOptions.onShown = {
            let shown = ProcessInfo.processInfo.systemUptime
            order.record(.selectorShown(at: shown))
            Log.capture.info(
                "Region selector shown \(Int((shown - started) * 1000)) ms after the shortcut, freeze-frames took \(readyMilliseconds) ms"
            )
            if let violation = order.violation {
                Log.capture.error("Region selector order is wrong: \(violation, privacy: .public)")
            }
        }
        let selection = await RegionSelector.selectRegions(options: shownOptions)
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
            CaptureAgain.remember(.region(displayID: displayID, rect: rect))
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
        if delay == 0, let frozen = await frozenLastRegion(rect, displayID: target, content: content) {
            return frozen
        }
        guard let live = try await contentAfterCountdown(delay, content: content) else { return nil }
        return try await captureDisplayImage(displayID: target, region: rect, content: live, suffix: frontmostAppName())
    }

    private static func frozenLastRegion(_ rect: CGRect, displayID: CGDirectDisplayID, content: SCShareableContent) async -> CapturedImage? {
        guard let backdrops = await SelectionPrefetch.take(), let frame = backdrops[displayID], let screen = NSScreen.screen(for: displayID) else { return nil }
        let source = frontmostSource(in: content)
        let raw = CaptureSettings.current(for: source.bundleIdentifier).blursPrivateApps ? PrivacyFilter.redactBackdrops([displayID: frame], content: content)[displayID] ?? frame : frame
        let scale = CGFloat(raw.width) / max(1, screen.frame.width)
        guard let cropped = ScreenshotEngine.crop(raw, toPoints: rect, scale: scale) else { return nil }
        let geometry = PrivacyFilter.geometry(displayID: displayID, region: rect, image: cropped)
        Log.capture.info("Captured the last region from the frame taken when the shortcut was pressed")
        return CapturedImage(image: cropped, suffix: frontmostAppName(), geometry: geometry, pointScale: scale, source: source)
    }

    static func captureAllDisplays(content: SCShareableContent, delay: Int = 0) async throws -> CapturedImage? {
        guard let live = try await contentAfterCountdown(delay, content: content) else { return nil }
        CaptureAgain.remember(.allDisplays)
        let images = await ScreenshotEngine.backdrops(for: live)
        let source = frontmostSource(in: live)
        let entries = live.displays.compactMap { display in images[display.displayID].map { (display, $0) } }
        guard let first = entries.first else { return nil }
        if entries.count == 1 {
            return CapturedImage(image: first.1, suffix: "displays", pointScale: CGFloat(first.1.width) / max(1, CGFloat(first.0.width)), source: source)
        }
        let scale = entries.map { CGFloat($0.1.width) / max(1, CGFloat($0.0.width)) }.max() ?? 2
        guard let arrangement = DisplayArrangement.layout(frames: entries.map { ($0.0.displayID, CGDisplayBounds($0.0.displayID)) }, scale: scale),
            let context = CGContext(
                data: nil, width: Int(arrangement.pixelSize.width), height: Int(arrangement.pixelSize.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        for (display, image) in entries {
            guard let placement = arrangement.placements.first(where: { $0.id == display.displayID }) else { continue }
            let rect = placement.pixelRect
            context.draw(image, in: CGRect(x: rect.minX, y: arrangement.pixelSize.height - rect.maxY, width: rect.width, height: rect.height))
        }
        guard let combined = context.makeImage() else { return nil }
        return CapturedImage(image: combined, suffix: "displays", pointScale: scale, source: source)
    }

    static func captureAgain(_ recipe: CaptureRecipe) async -> CapturedImage? {
        await withCaptureContent { content in
            switch recipe {
            case let .region(displayID, rect):
                guard content.displays.contains(where: { $0.displayID == displayID }) else { return nil }
                return try await captureDisplayImage(displayID: displayID, region: rect, content: content, suffix: frontmostAppName())
            case let .screen(displayID):
                return try await captureDisplayImage(displayID: displayID, region: nil, content: content, suffix: NSScreen.screen(for: displayID)?.captureSuffix)
            case .allDisplays:
                return try await captureAllDisplays(content: content)
            case let .window(windowID, bundleID, title):
                let candidates = ScreenshotEngine.candidateWindows(in: content)
                let match = CaptureRecipe.windowMatch(
                    windowID, bundleID: bundleID, title: title,
                    among: candidates.map { (id: $0.windowID, bundleID: $0.owningApplication?.bundleIdentifier, title: $0.title) })
                guard let match, let window = candidates.first(where: { $0.windowID == match }) else { return nil }
                return try await captureWindowImage(window, content: content)
            case .appWindows, .webPage:
                return nil
            }
        }
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
            CaptureAgain.remember(.window(windowID: picked.window.windowID, bundleID: picked.window.owningApplication?.bundleIdentifier, title: picked.window.title))
            return try await captureWindowImage(picked.window, content: content)
        case .switchToRegion:
            return try await captureRegion(content: content, delay: delay)
        case .cancelled:
            return nil
        }
    }

    static func captureWindowImage(_ window: SCWindow, content: SCShareableContent? = nil) async throws -> CapturedImage? {
        let source = windowSource(window)
        let settings = CaptureSettings.current(for: source.bundleIdentifier)
        if let grouped = try await captureWithChildWindows(window, content: content, includesShadow: settings.includesWindowShadow) {
            return CapturedImage(image: grouped.image, suffix: window.owningApplication?.applicationName ?? "window", isWindow: true, pointScale: grouped.scale, source: source)
        }
        let image = try await ScreenshotEngine.captureWindow(window, includesShadow: settings.includesWindowShadow)
        let scale = max(1, (CGFloat(image.width) / max(1, window.frame.width)).rounded())
        return CapturedImage(
            image: settings.blursPrivateApps ? PrivacyFilter.redactWindow(image, window: window, scale: scale) : image,
            suffix: window.owningApplication?.applicationName ?? "window",
            isWindow: true,
            pointScale: scale,
            source: source
        )
    }

    private static func captureWithChildWindows(_ window: SCWindow, content: SCShareableContent?, includesShadow: Bool) async throws -> (image: CGImage, scale: CGFloat)? {
        guard Defaults[.windowCaptureIncludesChildWindows], let content else { return nil }
        let related = ChildWindowPlan.related(to: ScreenshotEngine.windowDescriptor(window), in: content.windows.map(ScreenshotEngine.windowDescriptor))
        guard !related.isEmpty,
            let display = content.displays.first(where: { CGDisplayBounds($0.displayID).intersects(window.frame) })
        else { return nil }
        let ids = Set(related.map(\.id)).union([window.windowID])
        let windows = content.windows.filter { ids.contains($0.windowID) }
        let rect = ChildWindowPlan.captureRect(
            main: window.frame, related: related.map(\.frame), within: CGDisplayBounds(display.displayID), includesShadow: includesShadow)
        let image = try await ScreenshotEngine.captureWindows(windows, on: display, globalRect: rect)
        Log.capture.info("Captured the window with \(related.count) attached windows")
        return (image, CGFloat(image.width) / max(1, rect.width))
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
        CaptureAgain.remember(.screen(displayID: displayID))
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
        if !result.isWindow {
            result.image = BorderTrimmer.trimIfEnabled(result.image)
        }
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
        try ImageEncoder.write(captured.image, as: fileType, to: url, pointScale: captured.pointScale ?? captured.geometry?.scale)
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
