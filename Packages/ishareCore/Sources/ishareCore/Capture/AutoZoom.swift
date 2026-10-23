import CoreGraphics
import Foundation

public struct PointerSample: Hashable, Sendable {
    public var time: Double
    public var point: CGPoint

    public init(time: Double, point: CGPoint) {
        self.time = time
        self.point = point
    }
}

public struct ActivityEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case click
        case typing
    }

    public var time: Double
    public var point: CGPoint
    public var kind: Kind

    public static func collect(clicks: [PointerSample], keyTimes: [Double], pointer: [PointerSample]) -> [ActivityEvent] {
        let sortedClicks = clicks.sorted { $0.time < $1.time }
        let clickEvents = sortedClicks.map { ActivityEvent(time: $0.time, point: $0.point, kind: .click) }
        let typingEvents = keyTimes.compactMap { time -> ActivityEvent? in
            let anchor = sortedClicks.last { $0.time <= time }?.point ?? PointerTrack.nearestPoint(in: pointer, at: time)
            return anchor.map { ActivityEvent(time: time, point: $0, kind: .typing) }
        }
        return (clickEvents + typingEvents).sorted { $0.time < $1.time }
    }

    public init(time: Double, point: CGPoint, kind: Kind) {
        self.time = time
        self.point = point
        self.kind = kind
    }
}

public struct AutoZoomSettings: Hashable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 1.5 ... 3
    public static let easeRange: ClosedRange<Double> = 0.2 ... 2
    public static let holdRange: ClosedRange<Double> = 0.5 ... 5

    public var zoom: Double
    public var easeDuration: Double
    public var holdTime: Double
    public var followsPointer: Bool

    public init(zoom: Double = 2, easeDuration: Double = 0.6, holdTime: Double = 1.5, followsPointer: Bool = true) {
        self.zoom = zoom.clamped(to: Self.zoomRange)
        self.easeDuration = easeDuration.clamped(to: Self.easeRange)
        self.holdTime = holdTime.clamped(to: Self.holdRange)
        self.followsPointer = followsPointer
    }

}

struct CameraKeyframe: Hashable, Sendable {
    public var time: Double
    public var scale: Double
    public var center: CGPoint

    public init(time: Double, scale: Double, center: CGPoint) {
        self.time = time
        self.scale = scale
        self.center = center
    }
}

public struct ZoomSegment: Hashable, Sendable {
    public enum FocusMotion: Hashable, Sendable {
        case pan
        case track
    }

    public var start: Double
    public var peak: Double
    public var release: Double
    public var end: Double
    public var zoom: Double
    public var focus: [PointerSample]
    public var motion: FocusMotion
    public var panDuration: Double

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }

    public func scale(at time: Double) -> Double {
        guard contains(time) else { return 1 }
        let progress: Double =
            if time < peak {
                peak > start ? Easing.smoothstep((time - start) / (peak - start)) : 1
            } else if time >= release {
                end > release ? 1 - Easing.smoothstep((time - release) / (end - release)) : 0
            } else {
                1
            }
        return 1 + (zoom - 1) * progress
    }

    func focusPoint(at time: Double) -> CGPoint? {
        guard let first = focus.first else { return nil }
        guard time > first.time else { return first.point }
        guard let nextIndex = focus.firstIndex(where: { $0.time > time }) else { return focus.last?.point }
        let previous = focus[nextIndex - 1]
        let next = focus[nextIndex]
        switch motion {
        case .track:
            let fraction = (time - previous.time) / max(0.0001, next.time - previous.time)
            return previous.point.interpolated(to: next.point, fraction: fraction)
        case .pan:
            let moveStart = max(previous.time, next.time - panDuration)
            guard time > moveStart else { return previous.point }
            let fraction = Easing.smoothstep((time - moveStart) / max(0.0001, next.time - moveStart))
            return previous.point.interpolated(to: next.point, fraction: fraction)
        }
    }

    public init(start: Double, peak: Double, release: Double, end: Double, zoom: Double, focus: [PointerSample], motion: FocusMotion, panDuration: Double) {
        self.start = start
        self.peak = peak
        self.release = release
        self.end = end
        self.zoom = zoom
        self.focus = focus
        self.motion = motion
        self.panDuration = panDuration
    }
}

public struct CameraPath: Hashable, Sendable {
    public var frameSize: CGSize
    public var segments: [ZoomSegment]

    public var isEmpty: Bool { segments.isEmpty }

    public func segment(at time: Double) -> ZoomSegment? {
        segments.first { $0.contains(time) }
    }

    public func scale(at time: Double) -> Double {
        segment(at: time)?.scale(at: time) ?? 1
    }

    public func visibleRect(at time: Double) -> CGRect {
        let full = CGRect(origin: .zero, size: frameSize)
        guard let segment = segment(at: time), let focus = segment.focusPoint(at: time) else { return full }
        return Self.clampedRect(center: focus, scale: segment.scale(at: time), in: frameSize)
    }

    var keyframes: [CameraKeyframe] {
        segments.flatMap { segment -> [CameraKeyframe] in
            let focusTimes = segment.focus.map(\.time).filter { $0 > segment.peak && $0 < segment.release }
            let times = [segment.start, segment.peak] + focusTimes + [segment.release, segment.end]
            return times.map { time in
                let probe = min(time, segment.end - 0.0001)
                let rect = time >= segment.end ? CGRect(origin: .zero, size: frameSize) : visibleRect(at: probe)
                return CameraKeyframe(time: time, scale: time >= segment.end ? 1 : segment.scale(at: probe), center: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    static func clampedRect(center: CGPoint, scale: Double, in frameSize: CGSize) -> CGRect {
        let factor = CGFloat(max(1, scale))
        let size = CGSize(width: frameSize.width / factor, height: frameSize.height / factor)
        let x = (center.x - size.width / 2).clamped(to: 0 ... max(0, frameSize.width - size.width))
        let y = (center.y - size.height / 2).clamped(to: 0 ... max(0, frameSize.height - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    public init(frameSize: CGSize, segments: [ZoomSegment]) {
        self.frameSize = frameSize
        self.segments = segments
    }
}

public enum CameraPlanner {
    static let followSampleInterval: Double = 0.1
    static let followTimeConstant: Double = 0.35
    static let deadZoneFraction: CGFloat = 0.3

    public static func plan(activity: [ActivityEvent], pointer: [PointerSample], duration: Double, frameSize: CGSize, settings: AutoZoomSettings) -> CameraPath {
        guard duration > 0, frameSize.width > 0, frameSize.height > 0 else { return CameraPath(frameSize: frameSize, segments: []) }
        let bounds = CGRect(origin: .zero, size: frameSize)
        let events =
            activity
            .filter { $0.time >= 0 && $0.time <= duration }
            .map { ActivityEvent(time: $0.time, point: $0.point.clamped(to: bounds), kind: $0.kind) }
            .sorted { $0.time < $1.time }
        let clusters = merged(clusters(events, frameSize: frameSize, settings: settings), frameSize: frameSize, settings: settings)
        var segments: [ZoomSegment] = []
        for (index, cluster) in clusters.enumerated() {
            let next = index + 1 < clusters.count ? clusters[index + 1] : nil
            let previousEnd = segments.last?.end ?? 0
            guard let segment = segment(for: cluster, next: next, previousEnd: previousEnd, pointer: pointer, duration: duration, frameSize: frameSize, settings: settings) else {
                continue
            }
            segments.append(segment)
        }
        return CameraPath(frameSize: frameSize, segments: segments)
    }

    static func farDistance(frameSize: CGSize, zoom: Double) -> CGFloat {
        max(frameSize.width, frameSize.height) / CGFloat(zoom)
    }

    static func clusters(_ events: [ActivityEvent], frameSize: CGSize, settings: AutoZoomSettings) -> [[ActivityEvent]] {
        let far = farDistance(frameSize: frameSize, zoom: settings.zoom)
        var clusters: [[ActivityEvent]] = []
        for event in events {
            if let last = clusters.last?.last,
                event.time - last.time <= settings.holdTime,
                event.point.distance(to: last.point) <= far
            {
                clusters[clusters.count - 1].append(event)
            } else {
                clusters.append([event])
            }
        }
        return clusters
    }

    public static func merged(_ clusters: [[ActivityEvent]], frameSize: CGSize, settings: AutoZoomSettings) -> [[ActivityEvent]] {
        let far = farDistance(frameSize: frameSize, zoom: settings.zoom)
        let bridge = settings.holdTime + 2 * settings.easeDuration
        var result: [[ActivityEvent]] = []
        for cluster in clusters {
            if let previous = result.last, let last = previous.last, let first = cluster.first,
                first.time - last.time < bridge, first.point.distance(to: last.point) <= far
            {
                result[result.count - 1].append(contentsOf: cluster)
            } else {
                result.append(cluster)
            }
        }
        return result
    }

    private static func segment(
        for cluster: [ActivityEvent], next: [ActivityEvent]?, previousEnd: Double, pointer: [PointerSample], duration: Double, frameSize: CGSize, settings: AutoZoomSettings
    ) -> ZoomSegment? {
        guard let first = cluster.first, let last = cluster.last else { return nil }
        let ease = settings.easeDuration
        let start = max(0, previousEnd, first.time - ease)
        var desiredRelease = last.time + settings.holdTime
        if let nextFirst = next?.first {
            desiredRelease = max(last.time, min(desiredRelease, nextFirst.time - 2 * ease))
        }
        var peak = start + ease
        var release = max(desiredRelease, peak)
        let end = min(duration, release + ease)
        guard end > start else { return nil }
        if release + ease > end {
            let available = end - start
            if available < 2 * ease {
                peak = start + available / 2
                release = peak
            } else {
                release = end - ease
            }
        }
        let focus = focusKeyframes(for: cluster, pointer: pointer, start: start, end: end, frameSize: frameSize, settings: settings)
        return ZoomSegment(
            start: start,
            peak: peak,
            release: release,
            end: end,
            zoom: settings.zoom,
            focus: focus.samples,
            motion: focus.motion,
            panDuration: ease
        )
    }

    private static func focusKeyframes(for cluster: [ActivityEvent], pointer: [PointerSample], start: Double, end: Double, frameSize: CGSize, settings: AutoZoomSettings) -> (
        samples: [PointerSample], motion: ZoomSegment.FocusMotion
    ) {
        let eventFocus = deduplicated(cluster.map { PointerSample(time: $0.time, point: $0.point) })
        guard settings.followsPointer else { return (eventFocus, .pan) }
        let window = pointer.filter { $0.time >= start && $0.time <= end }
        guard window.count >= 2 else { return (eventFocus, .pan) }
        let resampled = PointerSmoother.resample(window, interval: followSampleInterval)
        let viewport = CGSize(width: frameSize.width / CGFloat(settings.zoom), height: frameSize.height / CGFloat(settings.zoom))
        let held = deadZoned(resampled, initial: cluster[0].point, viewport: viewport)
        return (PointerSmoother.smooth(held, timeConstant: followTimeConstant), .track)
    }

    static func deadZoned(_ samples: [PointerSample], initial: CGPoint, viewport: CGSize) -> [PointerSample] {
        let halfWidth = viewport.width * deadZoneFraction
        let halfHeight = viewport.height * deadZoneFraction
        var center = initial
        return samples.map { sample in
            let dx = sample.point.x - center.x
            let dy = sample.point.y - center.y
            if abs(dx) > halfWidth { center.x += dx - (dx > 0 ? halfWidth : -halfWidth) }
            if abs(dy) > halfHeight { center.y += dy - (dy > 0 ? halfHeight : -halfHeight) }
            return PointerSample(time: sample.time, point: center)
        }
    }

    private static func deduplicated(_ samples: [PointerSample]) -> [PointerSample] {
        samples.reduce(into: [PointerSample]()) { result, sample in
            if let last = result.last, last.point.distance(to: sample.point) < 1 { return }
            result.append(sample)
        }
    }
}

enum Easing {
    static func smoothstep(_ value: Double) -> Double {
        let x = value.clamped(to: 0 ... 1)
        return x * x * (3 - 2 * x)
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CGPoint {
    public func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func interpolated(to other: CGPoint, fraction: Double) -> CGPoint {
        let t = CGFloat(fraction.clamped(to: 0 ... 1))
        return CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    public func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: x.clamped(to: rect.minX ... rect.maxX), y: y.clamped(to: rect.minY ... rect.maxY))
    }
}
