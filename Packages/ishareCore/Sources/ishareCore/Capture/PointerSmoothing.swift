import CoreGraphics
import Foundation

public enum PointerSmoother {
    public static let defaultTimeConstant: Double = 0.08

    public static func smooth(_ samples: [PointerSample], timeConstant: Double = defaultTimeConstant) -> [PointerSample] {
        guard let first = samples.first, timeConstant > 0 else { return samples }
        var current = first.point
        var previousTime = first.time
        return samples.map { sample in
            let elapsed = max(0, sample.time - previousTime)
            let alpha = 1 - exp(-elapsed / timeConstant)
            current = current.interpolated(to: sample.point, fraction: alpha)
            previousTime = sample.time
            return PointerSample(time: sample.time, point: current)
        }
    }

    static func resample(_ samples: [PointerSample], interval: Double) -> [PointerSample] {
        guard let first = samples.first, let last = samples.last, interval > 0, last.time > first.time else { return samples }
        let count = Int(((last.time - first.time) / interval).rounded(.down))
        return (0 ... count).compactMap { index in
            let time = first.time + Double(index) * interval
            return PointerTrack.interpolatedPoint(in: samples, at: time, maximumGap: .infinity).map { PointerSample(time: time, point: $0) }
        }
    }
}

public enum PointerIdleDetector {
    static let movementThreshold: CGFloat = 1

    public static func hiddenIntervals(samples: [PointerSample], clicks: [Double], idleDelay: Double, duration: Double) -> [ClosedRange<Double>] {
        guard idleDelay > 0, let first = samples.first else { return [] }
        var activity: [Double] = [first.time]
        var anchor = first.point
        for sample in samples.dropFirst() where sample.point.distance(to: anchor) > movementThreshold {
            activity.append(sample.time)
            anchor = sample.point
        }
        let times = (activity + clicks).sorted()
        var intervals: [ClosedRange<Double>] = []
        for (index, time) in times.enumerated() {
            let hideStart = time + idleDelay
            let nextActivity = index + 1 < times.count ? times[index + 1] : duration
            if nextActivity > hideStart {
                intervals.append(hideStart ... nextActivity)
            }
        }
        return intervals
    }
}

public struct PointerTrack: Hashable, Sendable {
    static let maximumSampleGap: Double = 0.25
    public static let fadeDuration: Double = 0.25

    public var samples: [PointerSample]
    public var hiddenIntervals: [ClosedRange<Double>] = []
    public var scale: Double = 1

    public func position(at time: Double) -> CGPoint? {
        Self.interpolatedPoint(in: samples, at: time, maximumGap: Self.maximumSampleGap)
    }

    public func opacity(at time: Double) -> Double {
        guard let interval = hiddenIntervals.first(where: { $0.contains(time) }) else { return 1 }
        guard time < interval.upperBound else { return 1 }
        return 1 - min(1, (time - interval.lowerBound) / Self.fadeDuration)
    }

    static func interpolatedPoint(in samples: [PointerSample], at time: Double, maximumGap: Double) -> CGPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time { return first.time - time <= maximumGap / 2 ? first.point : nil }
        if time >= last.time { return time - last.time <= maximumGap / 2 ? last.point : nil }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if samples[middle].time <= time { low = middle } else { high = middle }
        }
        let previous = samples[low]
        let next = samples[high]
        guard next.time - previous.time <= maximumGap else { return nil }
        let fraction = (time - previous.time) / max(0.0001, next.time - previous.time)
        return previous.point.interpolated(to: next.point, fraction: fraction)
    }

    static func nearestPoint(in samples: [PointerSample], at time: Double) -> CGPoint? {
        samples.min { abs($0.time - time) < abs($1.time - time) }?.point
    }

    public init(samples: [PointerSample], hiddenIntervals: [ClosedRange<Double>] = [], scale: Double = 1) {
        self.samples = samples
        self.hiddenIntervals = hiddenIntervals
        self.scale = scale
    }
}
