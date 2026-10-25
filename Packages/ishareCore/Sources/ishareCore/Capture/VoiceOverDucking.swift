import Foundation

public struct GainPoint: Hashable, Sendable {
    public var time: Double
    public var gain: Double

    public init(time: Double, gain: Double) {
        self.time = time
        self.gain = gain
    }
}

public struct DuckingSettings: Hashable, Sendable {
    public static let reductionRange: ClosedRange<Double> = 3 ... 40

    public var speechThreshold: Double
    public var reduction: Double
    public var attack: Double
    public var release: Double
    public var hold: Double

    public init(speechThreshold: Double = -42, reduction: Double = 12, attack: Double = 0.1, release: Double = 0.4, hold: Double = 0.3) {
        self.speechThreshold = speechThreshold
        self.reduction = reduction.clamped(to: Self.reductionRange)
        self.attack = max(0, attack)
        self.release = max(0, release)
        self.hold = max(0, hold)
    }

    public var duckedGain: Double { DuckingEnvelope.linearGain(decibels: -reduction) }
}

public enum DuckingEnvelope {
    public static func linearGain(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }

    public static func speakingRanges(levels: LevelSeries, threshold: Double, hold: Double) -> [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = []
        for (index, value) in levels.values.enumerated() where value >= threshold {
            let start = levels.start + Double(index) * levels.step
            let end = start + levels.step + hold
            if let last = ranges.last, start <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound ... max(last.upperBound, end)
            } else {
                ranges.append(start ... end)
            }
        }
        return ranges
    }

    public static func points(levels: LevelSeries, settings: DuckingSettings, duration: Double) -> [GainPoint] {
        let speaking = speakingRanges(levels: levels, threshold: settings.speechThreshold, hold: settings.hold)
        let ducked = settings.duckedGain
        var merged: [ClosedRange<Double>] = []
        for range in speaking {
            if let last = merged.last, range.lowerBound - settings.attack <= last.upperBound + settings.release {
                merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var points = [GainPoint(time: 0, gain: 1)]
        for range in merged {
            let fadeStart = max(points.last?.time ?? 0, range.lowerBound - settings.attack)
            let duckStart = max(fadeStart, range.lowerBound)
            let duckEnd = min(duration, max(duckStart, range.upperBound))
            let fadeEnd = min(duration, duckEnd + settings.release)
            points.append(GainPoint(time: fadeStart, gain: 1))
            points.append(GainPoint(time: duckStart, gain: ducked))
            points.append(GainPoint(time: duckEnd, gain: ducked))
            if fadeEnd > duckEnd { points.append(GainPoint(time: fadeEnd, gain: 1)) }
        }
        if let last = points.last, last.time < duration {
            points.append(GainPoint(time: duration, gain: last.gain))
        }
        return deduplicated(points)
    }

    public static func gain(at time: Double, points: [GainPoint]) -> Double {
        guard let first = points.first else { return 1 }
        guard time > first.time else { return points.last { $0.time <= first.time }?.gain ?? first.gain }
        for (previous, next) in zip(points, points.dropFirst()) where time <= next.time {
            let span = next.time - previous.time
            guard span > 0 else { return next.gain }
            return previous.gain + (next.gain - previous.gain) * (time - previous.time) / span
        }
        return points.last?.gain ?? 1
    }

    private static func deduplicated(_ points: [GainPoint]) -> [GainPoint] {
        var result: [GainPoint] = []
        for point in points {
            if let last = result.last, abs(last.time - point.time) < 0.000_1 {
                if last.gain != point.gain { result.append(point) }
            } else {
                result.append(point)
            }
        }
        return result
    }
}
