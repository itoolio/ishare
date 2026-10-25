import Foundation

public enum RetimingAction: Hashable, Sendable {
    case keep
    case remove
    case speed(Double)

    public var rate: Double? {
        switch self {
        case .keep: 1
        case .remove: nil
        case let .speed(factor): max(1, factor)
        }
    }

    public var keepsAudio: Bool { self == .keep }
}

public struct RetimingSegment: Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var action: RetimingAction

    public init(start: Double, end: Double, action: RetimingAction) {
        self.start = start
        self.end = end
        self.action = action
    }

    public var duration: Double { max(0, end - start) }

    public var outputDuration: Double {
        action.rate.map { duration / $0 } ?? 0
    }
}

public struct RetimingPlan: Hashable, Sendable {
    public private(set) var segments: [RetimingSegment]

    public init(segments: [RetimingSegment]) {
        self.segments = Self.normalized(segments)
    }

    public static func identity(duration: Double) -> RetimingPlan {
        RetimingPlan(segments: [RetimingSegment(start: 0, end: max(0, duration), action: .keep)])
    }

    public var sourceDuration: Double { segments.last?.end ?? 0 }

    public var outputDuration: Double { segments.reduce(0) { $0 + $1.outputDuration } }

    public var isIdentity: Bool { segments.allSatisfy { $0.action == .keep } }

    public var changedSegments: [RetimingSegment] { segments.filter { $0.action != .keep } }

    public var hasSpeedChanges: Bool {
        segments.contains { segment in
            if case .speed = segment.action { return true }
            return false
        }
    }

    public func outputTime(forSource time: Double) -> Double? {
        var elapsed = 0.0
        for segment in segments {
            if time < segment.end || segment == segments.last {
                guard time >= segment.start - 0.000_1, let rate = segment.action.rate else { return nil }
                return elapsed + (min(max(time, segment.start), segment.end) - segment.start) / rate
            }
            elapsed += segment.outputDuration
        }
        return nil
    }

    public func sourceTime(forOutput time: Double) -> Double {
        var elapsed = 0.0
        for segment in segments {
            guard let rate = segment.action.rate else { continue }
            let length = segment.outputDuration
            if time <= elapsed + length {
                return segment.start + max(0, time - elapsed) * rate
            }
            elapsed += length
        }
        return segments.last { $0.action.rate != nil }?.end ?? 0
    }

    public func restricted(to range: ClosedRange<Double>) -> RetimingPlan {
        var clipped: [RetimingSegment] = []
        for segment in segments {
            let pieces = [
                RetimingSegment(start: segment.start, end: min(segment.end, range.lowerBound), action: .remove),
                RetimingSegment(start: max(segment.start, range.lowerBound), end: min(segment.end, range.upperBound), action: segment.action),
                RetimingSegment(start: max(segment.start, range.upperBound), end: segment.end, action: .remove),
            ]
            clipped += pieces.filter { $0.duration > 0 }
        }
        return RetimingPlan(segments: clipped)
    }

    private static func normalized(_ segments: [RetimingSegment]) -> [RetimingSegment] {
        var merged: [RetimingSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.duration > 0 {
            if var last = merged.last, last.action == segment.action, abs(last.end - segment.start) < 0.000_1 {
                last.end = segment.end
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}

public struct LevelSeries: Hashable, Sendable {
    public var start: Double
    public var step: Double
    public var values: [Double]

    public init(start: Double = 0, step: Double, values: [Double]) {
        self.start = start
        self.step = step
        self.values = values
    }

    public var end: Double { start + step * Double(values.count) }

    public func value(at time: Double) -> Double? {
        guard step > 0, !values.isEmpty else { return nil }
        let index = Int(((time - start) / step).rounded(.down))
        return values[index.clamped(to: 0 ... values.count - 1)]
    }

    public static func loudest(_ series: [LevelSeries]) -> LevelSeries? {
        guard let first = series.first else { return nil }
        guard series.count > 1 else { return first }
        let step = series.map(\.step).min() ?? first.step
        let start = series.map(\.start).min() ?? 0
        let end = series.map(\.end).max() ?? 0
        let count = max(0, Int(((end - start) / step).rounded(.up)))
        let values = (0 ..< count).map { index -> Double in
            let time = start + (Double(index) + 0.5) * step
            return series.compactMap { $0.contains(time) ? $0.value(at: time) : nil }.max() ?? -.infinity
        }
        return LevelSeries(start: start, step: step, values: values)
    }

    func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

public enum SilenceSpeed: Int, CaseIterable, Identifiable, Sendable, Codable {
    case remove = 0
    case double = 2
    case quadruple = 4
    case octuple = 8

    public var id: Self { self }

    public var action: RetimingAction {
        self == .remove ? .remove : .speed(Double(rawValue))
    }
}

public struct SilenceDetectionSettings: Hashable, Sendable {
    public static let audioThresholdRange: ClosedRange<Double> = -70 ... -20
    public static let motionThresholdRange: ClosedRange<Double> = 0.001 ... 0.1
    public static let minimumDurationRange: ClosedRange<Double> = 0.5 ... 30
    public static let paddingRange: ClosedRange<Double> = 0 ... 2

    public var audioThreshold: Double
    public var motionThreshold: Double
    public var minimumDuration: Double
    public var padding: Double
    public var speed: SilenceSpeed

    public init(audioThreshold: Double = -45, motionThreshold: Double = 0.01, minimumDuration: Double = 2, padding: Double = 0.3, speed: SilenceSpeed = .remove) {
        self.audioThreshold = audioThreshold.clamped(to: Self.audioThresholdRange)
        self.motionThreshold = motionThreshold.clamped(to: Self.motionThresholdRange)
        self.minimumDuration = minimumDuration.clamped(to: Self.minimumDurationRange)
        self.padding = padding.clamped(to: Self.paddingRange)
        self.speed = speed
    }
}

public enum SilencePlanner {
    static let resolution = 0.05

    public static func quietRanges(audio: LevelSeries?, motion: LevelSeries?, duration: Double, settings: SilenceDetectionSettings) -> [ClosedRange<Double>] {
        guard duration > 0 else { return [] }
        let step = min(resolution, audio?.step ?? resolution, motion?.step ?? resolution)
        let count = Int((duration / step).rounded(.up))
        var ranges: [ClosedRange<Double>] = []
        var runStart: Double?
        for index in 0 ... count {
            let time = min(duration, Double(index) * step)
            let probe = min(duration, (Double(index) + 0.5) * step)
            let quiet = index < count && isQuiet(at: probe, audio: audio, motion: motion, settings: settings)
            if quiet, runStart == nil {
                runStart = time
            } else if !quiet, let start = runStart {
                ranges.append(start ... time)
                runStart = nil
            }
        }
        return ranges.filter { $0.upperBound - $0.lowerBound >= settings.minimumDuration }
    }

    public static func plan(audio: LevelSeries?, motion: LevelSeries?, duration: Double, settings: SilenceDetectionSettings) -> RetimingPlan {
        let quiet = quietRanges(audio: audio, motion: motion, duration: duration, settings: settings)
        return plan(quietRanges: quiet, duration: duration, settings: settings)
    }

    public static func plan(quietRanges: [ClosedRange<Double>], duration: Double, settings: SilenceDetectionSettings) -> RetimingPlan {
        guard duration > 0 else { return RetimingPlan(segments: []) }
        var segments: [RetimingSegment] = []
        var cursor = 0.0
        for range in quietRanges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let start = range.lowerBound <= 0.001 ? 0 : range.lowerBound + settings.padding
            let end = range.upperBound >= duration - 0.001 ? duration : range.upperBound - settings.padding
            guard end - start >= minimumChange, start >= cursor else { continue }
            segments.append(RetimingSegment(start: cursor, end: start, action: .keep))
            segments.append(RetimingSegment(start: start, end: end, action: settings.speed.action))
            cursor = end
        }
        segments.append(RetimingSegment(start: cursor, end: duration, action: .keep))
        return RetimingPlan(segments: segments)
    }

    static let minimumChange = 0.1

    private static func isQuiet(at time: Double, audio: LevelSeries?, motion: LevelSeries?, settings: SilenceDetectionSettings) -> Bool {
        let audioQuiet = audio?.value(at: time).map { $0 < settings.audioThreshold } ?? true
        let motionQuiet = motion?.value(at: time).map { $0 < settings.motionThreshold } ?? true
        return audioQuiet && motionQuiet
    }
}

public enum FrameDifference {
    public static func meanAbsoluteDifference(_ first: [UInt8], _ second: [UInt8]) -> Double {
        let count = min(first.count, second.count)
        guard count > 0 else { return first.count == second.count ? 0 : 1 }
        var total = 0
        for index in 0 ..< count {
            total += abs(Int(first[index]) - Int(second[index]))
        }
        return Double(total) / Double(count * 255)
    }

    public static func decibels(rms: Double) -> Double {
        rms > 0 ? 20 * log10(rms) : -160
    }
}

public struct AnimatedFrame: Hashable, Sendable {
    public var sourceIndex: Int
    public var delay: Double

    public init(sourceIndex: Int, delay: Double) {
        self.sourceIndex = sourceIndex
        self.delay = delay
    }
}

public enum AnimatedFrameDedupe {
    public static func merged(delays: [Double], isDuplicate: [Bool]) -> [AnimatedFrame] {
        var frames: [AnimatedFrame] = []
        for (index, delay) in delays.enumerated() {
            let duplicate = index < isDuplicate.count && isDuplicate[index]
            if duplicate, let last = frames.last {
                frames[frames.count - 1].delay = last.delay + delay
            } else {
                frames.append(AnimatedFrame(sourceIndex: index, delay: delay))
            }
        }
        return frames
    }
}
