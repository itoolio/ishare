import Combine
import CoreGraphics
import Foundation
import QuartzCore

struct FrameThrottle: Equatable {
    enum Decision: Equatable {
        case renderNow
        case wait(TimeInterval)
    }

    var interval: TimeInterval
    private(set) var lastRender: TimeInterval?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func decision(at now: TimeInterval) -> Decision {
        guard let lastRender else { return .renderNow }
        let elapsed = now - lastRender
        return elapsed >= interval ? .renderNow : .wait(interval - elapsed)
    }

    mutating func didRender(at now: TimeInterval) {
        lastRender = now
    }

    mutating func reset() {
        lastRender = nil
    }
}

@MainActor
final class LiveEffectPreview: ObservableObject {
    struct Tile {
        var image: CGImage
        var rect: CGRect
    }

    static let framesPerSecond: Double = 30
    static let maximumSourcePixels: CGFloat = 1600
    static let minimumSourceScale: CGFloat = 0.1

    @Published private(set) var background: CGImage?
    @Published private(set) var tile: Tile?
    private(set) var annotationID: UUID?
    private(set) var sourceScale: CGFloat = 1
    private(set) var renderCount = 0
    private var source: CGImage?
    private var throttle = FrameThrottle(interval: 1 / LiveEffectPreview.framesPerSecond)
    private var pending: Annotation?
    private var trailingFrame: Task<Void, Never>?
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.clock = clock
    }

    var isActive: Bool { background != nil }
    var hasPendingFrame: Bool { pending != nil }

    static func sourceScale(for imageSize: CGSize, zoom: CGFloat) -> CGFloat {
        let longest = max(1, max(imageSize.width, imageSize.height))
        let capped = min(1, maximumSourcePixels / longest)
        return max(minimumSourceScale, min(capped, zoom))
    }

    func begin(for annotation: Annotation, background: CGImage, zoom: CGFloat) {
        end()
        annotationID = annotation.id
        self.background = background
        sourceScale = Self.sourceScale(for: CGSize(width: background.width, height: background.height), zoom: zoom)
        source = sourceScale < 1 ? ImageProcessing.resized(background, maxPixelSize: CGFloat(max(background.width, background.height)) * sourceScale) : background
        if let source {
            sourceScale = CGFloat(source.width) / CGFloat(max(1, background.width))
        }
        update(annotation)
    }

    func update(_ annotation: Annotation) {
        guard isActive, annotation.isEffect else { return }
        pending = annotation
        let now = clock()
        switch throttle.decision(at: now) {
        case .renderNow:
            renderPending(at: now)
        case let .wait(delay):
            scheduleTrailingFrame(after: delay)
        }
    }

    func flush() {
        renderPending(at: clock())
    }

    func end() {
        trailingFrame?.cancel()
        trailingFrame = nil
        pending = nil
        source = nil
        background = nil
        tile = nil
        annotationID = nil
        throttle.reset()
    }

    private func scheduleTrailingFrame(after delay: TimeInterval) {
        guard trailingFrame == nil else { return }
        trailingFrame = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.trailingFrame = nil
            self?.flush()
        }
    }

    private func renderPending(at now: TimeInterval) {
        guard let annotation = pending, let source else { return }
        pending = nil
        throttle.didRender(at: now)
        renderCount += 1
        tile = Self.tile(for: annotation, source: source, scale: sourceScale)
    }

    static func tile(for annotation: Annotation, source: CGImage, scale: CGFloat) -> Tile? {
        let region = annotation.bounds.standardized
        let sourceBounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let scaledRegion = CGRect(x: region.minX * scale, y: region.minY * scale, width: region.width * scale, height: region.height * scale)
        let visibleRegion = scaledRegion.intersection(sourceBounds)
        guard !visibleRegion.isNull, visibleRegion.width >= 1, visibleRegion.height >= 1 else { return nil }
        let margin = ceil(AnnotationRenderer.pixelBlockSize(for: region) * scale) + 4
        let tileRect = visibleRegion.insetBy(dx: -margin, dy: -margin).intersection(sourceBounds).integral
        guard let tileSource = source.cropping(to: tileRect) else { return nil }
        let localRegion = scaledRegion.offsetBy(dx: -tileRect.minX, dy: -tileRect.minY)
        let effected = AnnotationRenderer.applyingEffect(annotation, to: tileSource, parameterScale: scale, region: localRegion)
        let outputRect = visibleRegion.offsetBy(dx: -tileRect.minX, dy: -tileRect.minY).integral
        guard let cropped = effected.cropping(to: outputRect) else { return nil }
        let placed = outputRect.offsetBy(dx: tileRect.minX, dy: tileRect.minY)
        return Tile(image: cropped, rect: CGRect(x: placed.minX / scale, y: placed.minY / scale, width: placed.width / scale, height: placed.height / scale))
    }
}
