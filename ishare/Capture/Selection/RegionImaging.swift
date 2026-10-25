import AppKit
import Defaults
import ishareCore
@preconcurrency import ScreenCaptureKit

@MainActor
final class SelectionBackdropLoader {
    private let content: SCShareableContent
    private let blursPrivateApps: Bool
    private(set) var mode: SelectionFreezeMode
    private var task: Task<[CGDirectDisplayID: CGImage], Never>?
    private var generation = 0

    init(content: SCShareableContent, blursPrivateApps: Bool, mode: SelectionFreezeMode) {
        self.content = content
        self.blursPrivateApps = blursPrivateApps
        self.mode = mode
    }

    func startIfFrozen() {
        if mode.loadsBackdrops {
            load()
        }
    }

    func change(to mode: SelectionFreezeMode) {
        self.mode = mode
        if mode.loadsBackdrops {
            load()
        } else {
            generation += 1
            task = nil
        }
    }

    func currentBackdrops() async -> [CGDirectDisplayID: CGImage] {
        guard mode.loadsBackdrops, let task else { return [:] }
        return await task.value
    }

    private func load() {
        generation += 1
        let expected = generation
        let content = content
        let blursPrivateApps = blursPrivateApps
        task = Task { [weak self] in
            let live = await ScreenshotEngine.shareableContent(listing: RegionSelector.panelWindowIDs) ?? content
            let raw = await ScreenshotEngine.backdrops(for: live)
            let backdrops = blursPrivateApps ? PrivacyFilter.redactBackdrops(raw, content: live) : raw
            if self?.generation == expected {
                RegionSelector.provide(backdrops: backdrops)
            }
            return backdrops
        }
    }
}

@MainActor
final class RegionImaging {
    private let content: SCShareableContent
    private let delay: Int
    private let mode: SelectionFreezeMode
    private let backdrops: [CGDirectDisplayID: CGImage]
    private let frontmost: String?
    private let source: CaptureSource
    private var liveContent: SCShareableContent?
    private var preparedLiveContent = false

    init(
        content: SCShareableContent, delay: Int, mode: SelectionFreezeMode, backdrops: [CGDirectDisplayID: CGImage], frontmost: String?,
        source: CaptureSource
    ) {
        self.content = content
        self.delay = delay
        self.mode = mode
        self.backdrops = backdrops
        self.frontmost = frontmost
        self.source = source
    }

    func image(screen: NSScreen, region: CGRect?) async throws -> CapturedImage? {
        guard let displayID = screen.displayID else { return nil }
        let backdrop = backdrops[displayID]
        if let backdrop, SelectionFreezePolicy.imageSource(mode: mode, hasBackdrop: true, delay: delay) == .backdrop {
            return cropped(backdrop, screen: screen, displayID: displayID, region: region)
        }
        guard let live = try await liveContentForCapture() else { return nil }
        guard let region else {
            return try await ImageCaptureFlow.captureScreen(screen: screen, content: live)
        }
        return try await ImageCaptureFlow.captureDisplayImage(displayID: displayID, region: region, content: live, suffix: frontmost, source: source)
    }

    func images(for areas: [RegionSelector.Area]) async throws -> CapturedImage? {
        var images: [CapturedImage] = []
        for area in areas {
            if let image = try await image(screen: area.screen, region: area.rect) {
                images.append(image)
            }
        }
        guard let first = images.first else { return nil }
        guard images.count > 1 else { return first }
        switch Defaults[.multiRegionResult] {
        case .separate:
            var result = first
            result.additionalCaptures = Array(images.dropFirst())
            return result
        case .combined:
            let pieces = images.map { PrivacyFilter.hideMenuBarIfNeeded($0.image, geometry: $0.geometry) }
            guard let combined = ImageCombiner.combine(pieces, style: CombineStyle()) else { return first }
            return CapturedImage(image: combined, suffix: frontmost, pointScale: images.compactMap(\.geometry?.scale).max(), source: source)
        }
    }

    private func cropped(_ backdrop: CGImage, screen: NSScreen, displayID: CGDirectDisplayID, region: CGRect?) -> CapturedImage? {
        let scale = CGFloat(backdrop.width) / screen.frame.width
        guard let region else {
            let geometry = PrivacyFilter.geometry(displayID: displayID, region: nil, scale: scale)
            return CapturedImage(image: backdrop, suffix: screen.captureSuffix, geometry: geometry, source: source)
        }
        let geometry = PrivacyFilter.geometry(displayID: displayID, region: region, scale: scale)
        return ScreenshotEngine.crop(backdrop, toPoints: region, scale: geometry.scale).map {
            CapturedImage(image: $0, suffix: frontmost, geometry: geometry, source: source)
        }
    }

    private func liveContentForCapture() async throws -> SCShareableContent? {
        if preparedLiveContent { return liveContent }
        preparedLiveContent = true
        switch SelectionFreezePolicy.imageSource(mode: mode, hasBackdrop: false, delay: delay) {
        case .afterCountdown:
            liveContent = try await ImageCaptureFlow.contentAfterCountdown(delay, content: content)
        case let .liveCapture(settle) where settle > .zero:
            try await Task.sleep(for: settle)
            liveContent = try await ScreenshotEngine.shareableContent()
        case .liveCapture, .backdrop:
            liveContent = content
        }
        return liveContent
    }
}
