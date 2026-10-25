import CoreGraphics
import Foundation

public struct RegionKeyframe: Hashable, Sendable, Codable {
    public var time: Double
    public var rect: CGRect
    public var isManual: Bool

    public init(time: Double, rect: CGRect, isManual: Bool = false) {
        self.time = time
        self.rect = rect
        self.isManual = isManual
    }
}

public struct RegionTrack: Hashable, Sendable, Codable {
    public static let keyframeTolerance = 1.0 / 60

    public private(set) var keyframes: [RegionKeyframe]

    public init(keyframes: [RegionKeyframe] = []) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { keyframes.isEmpty }

    public func rect(at time: Double) -> CGRect? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.rect }
        if time >= last.time { return last.rect }
        guard let nextIndex = keyframes.firstIndex(where: { $0.time >= time }), nextIndex > 0 else { return last.rect }
        let previous = keyframes[nextIndex - 1]
        let next = keyframes[nextIndex]
        if next.time == time { return next.rect }
        let span = next.time - previous.time
        let fraction = span > 0 ? (time - previous.time) / span : 1
        return RegionGeometry.interpolated(previous.rect, next.rect, fraction: fraction)
    }

    public mutating func setKeyframe(_ rect: CGRect, at time: Double, isManual: Bool = true) {
        let keyframe = RegionKeyframe(time: time, rect: RegionGeometry.clampedToUnit(rect), isManual: isManual)
        if let index = keyframes.firstIndex(where: { abs($0.time - time) <= Self.keyframeTolerance }) {
            keyframes[index] = keyframe
        } else {
            keyframes.append(keyframe)
            keyframes.sort { $0.time < $1.time }
        }
    }

    public mutating func removeKeyframe(near time: Double, tolerance: Double = keyframeTolerance) {
        keyframes.removeAll { abs($0.time - time) <= tolerance }
    }

    public mutating func replaceTracked(with tracked: [RegionKeyframe], guardInterval: Double = 0.15) {
        let manual = keyframes.filter(\.isManual)
        let automatic =
            tracked
            .filter { sample in !manual.contains { abs($0.time - sample.time) < guardInterval } }
            .map { RegionKeyframe(time: $0.time, rect: RegionGeometry.clampedToUnit($0.rect), isManual: false) }
        keyframes = (manual + automatic).sorted { $0.time < $1.time }
    }
}

public enum BlurRegionStyle: String, CaseIterable, Identifiable, Sendable, Codable {
    case blur
    case pixelate

    public var id: Self { self }
}

public struct BlurRegion: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var style: BlurRegionStyle
    public var start: Double
    public var end: Double
    public var track: RegionTrack

    public init(id: UUID = UUID(), style: BlurRegionStyle = .blur, start: Double, end: Double, track: RegionTrack) {
        self.id = id
        self.style = style
        self.start = min(start, end)
        self.end = max(start, end)
        self.track = track
    }

    public func rect(at time: Double) -> CGRect? {
        guard time >= start, time <= end else { return nil }
        return track.rect(at: time)
    }

    public mutating func setStart(_ time: Double) {
        start = min(time, end)
    }

    public mutating func setEnd(_ time: Double) {
        end = max(time, start)
    }

    public func retimed(_ map: (Double) -> Double?) -> BlurRegion? {
        let frames = track.keyframes.compactMap { keyframe in map(keyframe.time).map { RegionKeyframe(time: $0, rect: keyframe.rect, isManual: keyframe.isManual) } }
        guard let newStart = map(start) ?? frames.first?.time, let newEnd = map(end) ?? frames.last?.time, newEnd > newStart else { return nil }
        return BlurRegion(id: id, style: style, start: newStart, end: newEnd, track: RegionTrack(keyframes: frames))
    }
}

public enum RegionGeometry {
    public static func interpolated(_ from: CGRect, _ to: CGRect, fraction: Double) -> CGRect {
        let amount = CGFloat(fraction.clamped(to: 0 ... 1))
        return CGRect(
            x: from.minX + (to.minX - from.minX) * amount,
            y: from.minY + (to.minY - from.minY) * amount,
            width: from.width + (to.width - from.width) * amount,
            height: from.height + (to.height - from.height) * amount
        )
    }

    public static func clampedToUnit(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        let width = min(max(standardized.width, 0.005), 1)
        let height = min(max(standardized.height, 0.005), 1)
        let x = standardized.minX.clamped(to: 0 ... 1 - width)
        let y = standardized.minY.clamped(to: 0 ... 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func intersectionOverUnion(_ first: CGRect, _ second: CGRect) -> Double {
        let intersection = first.intersection(second)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height + second.width * second.height - intersectionArea
        return unionArea > 0 ? Double(intersectionArea / unionArea) : 0
    }

    public static func deviation(_ first: CGRect, _ second: CGRect) -> Double {
        Double(max(abs(first.minX - second.minX), abs(first.minY - second.minY), abs(first.maxX - second.maxX), abs(first.maxY - second.maxY)))
    }

    public static func flippedVertically(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func padded(_ rect: CGRect, by fraction: CGFloat) -> CGRect {
        clampedToUnit(rect.insetBy(dx: -rect.width * fraction, dy: -rect.height * fraction))
    }
}

public enum TrackSmoothing {
    public static func smoothed(_ samples: [RegionKeyframe], radius: Int) -> [RegionKeyframe] {
        guard radius > 0, samples.count > 2 else { return samples }
        return samples.indices.map { index in
            let window = samples[max(0, index - radius) ... min(samples.count - 1, index + radius)]
            let count = CGFloat(window.count)
            let rect = CGRect(
                x: window.reduce(0) { $0 + $1.rect.minX } / count,
                y: window.reduce(0) { $0 + $1.rect.minY } / count,
                width: window.reduce(0) { $0 + $1.rect.width } / count,
                height: window.reduce(0) { $0 + $1.rect.height } / count
            )
            return RegionKeyframe(time: samples[index].time, rect: rect, isManual: samples[index].isManual)
        }
    }

    public static func simplified(_ samples: [RegionKeyframe], tolerance: Double) -> [RegionKeyframe] {
        guard samples.count > 2 else { return samples }
        var keep = Array(repeating: false, count: samples.count)
        keep[0] = true
        keep[samples.count - 1] = true
        var stack = [(0, samples.count - 1)]
        while let (low, high) = stack.popLast() {
            guard high - low > 1 else { continue }
            let first = samples[low]
            let last = samples[high]
            var worst = (index: low, deviation: 0.0)
            for index in low + 1 ..< high {
                let span = last.time - first.time
                let fraction = span > 0 ? (samples[index].time - first.time) / span : 0
                let predicted = RegionGeometry.interpolated(first.rect, last.rect, fraction: fraction)
                let deviation = RegionGeometry.deviation(predicted, samples[index].rect)
                if deviation > worst.deviation { worst = (index, deviation) }
            }
            if worst.deviation > tolerance {
                keep[worst.index] = true
                stack.append((low, worst.index))
                stack.append((worst.index, high))
            }
        }
        return samples.indices.filter { keep[$0] }.map { samples[$0] }
    }

    public static func keyframes(fromTracked samples: [RegionKeyframe], radius: Int = 2, tolerance: Double = 0.004) -> [RegionKeyframe] {
        simplified(smoothed(samples.sorted { $0.time < $1.time }, radius: radius), tolerance: tolerance)
    }
}

public struct RegionDetection: Hashable, Sendable {
    public var time: Double
    public var rects: [CGRect]

    public init(time: Double, rects: [CGRect]) {
        self.time = time
        self.rects = rects
    }
}

public enum RegionLinker {
    public static func link(_ detections: [RegionDetection], minimumOverlap: Double = 0.3, maximumGap: Double) -> [[RegionKeyframe]] {
        var open: [[RegionKeyframe]] = []
        var closed: [[RegionKeyframe]] = []
        for detection in detections.sorted(by: { $0.time < $1.time }) {
            let stale = open.filter { detection.time - ($0.last?.time ?? 0) > maximumGap }
            closed += stale
            open.removeAll { detection.time - ($0.last?.time ?? 0) > maximumGap }
            var claimed = Set<Int>()
            for rect in detection.rects {
                let match = open.indices
                    .filter { !claimed.contains($0) }
                    .map { ($0, RegionGeometry.intersectionOverUnion(open[$0].last?.rect ?? .null, rect)) }
                    .filter { $0.1 >= minimumOverlap }
                    .max { $0.1 < $1.1 }
                if let (index, _) = match {
                    open[index].append(RegionKeyframe(time: detection.time, rect: rect))
                    claimed.insert(index)
                } else {
                    open.append([RegionKeyframe(time: detection.time, rect: rect)])
                    claimed.insert(open.count - 1)
                }
            }
        }
        return (closed + open).sorted { ($0.first?.time ?? 0) < ($1.first?.time ?? 0) }
    }

    public static func regions(from detections: [RegionDetection], interval: Double, duration: Double, style: BlurRegionStyle, padding: CGFloat = 0.1) -> [BlurRegion] {
        link(detections, maximumGap: interval * 1.5).map { chain in
            let frames = chain.map { RegionKeyframe(time: $0.time, rect: RegionGeometry.padded($0.rect, by: padding)) }
            let start = max(0, (frames.first?.time ?? 0) - interval / 2)
            let end = min(duration, (frames.last?.time ?? 0) + interval / 2)
            return BlurRegion(style: style, start: start, end: end, track: RegionTrack(keyframes: frames))
        }
    }
}
