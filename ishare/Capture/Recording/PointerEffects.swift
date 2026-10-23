import CoreGraphics
import Defaults
import Foundation

struct PointerEffectSettings: Hashable, Sendable {
    static let scaleRange: ClosedRange<Double> = 1 ... 3
    static let idleRange: ClosedRange<Double> = 1 ... 30

    var recordsPointer: Bool
    var smoothing: Bool
    var scale: Double
    var ripples: Bool
    var rippleColor: CaptureColor
    var hidesWhenIdle: Bool
    var idleDelay: Double

    init(recordsPointer: Bool = true, smoothing: Bool = false, scale: Double = 1, ripples: Bool = false, rippleColor: CaptureColor = .defaultRipple, hidesWhenIdle: Bool = false, idleDelay: Double = 3) {
        self.recordsPointer = recordsPointer
        self.smoothing = smoothing
        self.scale = scale.clamped(to: Self.scaleRange)
        self.ripples = ripples
        self.rippleColor = rippleColor
        self.hidesWhenIdle = hidesWhenIdle
        self.idleDelay = idleDelay.clamped(to: Self.idleRange)
    }

    var rendersPointer: Bool {
        recordsPointer && (smoothing || scale > 1.001 || hidesWhenIdle)
    }

    var isActive: Bool {
        rendersPointer || ripples
    }

    static var current: PointerEffectSettings {
        PointerEffectSettings(
            recordsPointer: Defaults[.recordPointer],
            smoothing: Defaults[.pointerSmoothing],
            scale: Defaults[.pointerScale],
            ripples: Defaults[.clickRipples],
            rippleColor: CaptureColor(hex: Defaults[.clickRippleColor]) ?? .defaultRipple,
            hidesWhenIdle: Defaults[.hidesIdlePointer],
            idleDelay: Defaults[.pointerIdleSeconds]
        )
    }
}

extension CaptureColor {
    static let defaultRipple = CaptureColor(red: 1, green: 0.8, blue: 0)
}

enum PointerSmoother {
    static let defaultTimeConstant: Double = 0.08

    static func smooth(_ samples: [PointerSample], timeConstant: Double = defaultTimeConstant) -> [PointerSample] {
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

enum PointerIdleDetector {
    static let movementThreshold: CGFloat = 1

    static func hiddenIntervals(samples: [PointerSample], clicks: [Double], idleDelay: Double, duration: Double) -> [ClosedRange<Double>] {
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

struct PointerTrack: Hashable, Sendable {
    static let maximumSampleGap: Double = 0.25
    static let fadeDuration: Double = 0.25

    var samples: [PointerSample]
    var hiddenIntervals: [ClosedRange<Double>] = []
    var scale: Double = 1

    static func make(samples: [PointerSample], clicks: [Double], settings: PointerEffectSettings, duration: Double) -> PointerTrack {
        let sorted = samples.sorted { $0.time < $1.time }
        let positions = settings.smoothing ? PointerSmoother.smooth(sorted) : sorted
        let hidden = settings.hidesWhenIdle ? PointerIdleDetector.hiddenIntervals(samples: sorted, clicks: clicks, idleDelay: settings.idleDelay, duration: duration) : []
        return PointerTrack(samples: positions, hiddenIntervals: hidden, scale: settings.scale)
    }

    func position(at time: Double) -> CGPoint? {
        Self.interpolatedPoint(in: samples, at: time, maximumGap: Self.maximumSampleGap)
    }

    func opacity(at time: Double) -> Double {
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
}

struct ClickRippleFrame: Equatable, Sendable {
    var diameterScale: Double
    var alpha: Double
}

enum ClickRippleAnimation {
    static let lifetime: Double = 0.6
    static let baseDiameter: CGFloat = 46
    static let lineWidth: CGFloat = 3

    static func frame(elapsed: Double) -> ClickRippleFrame? {
        guard elapsed >= 0, elapsed < lifetime else { return nil }
        let progress = elapsed / lifetime
        let eased = 1 - pow(1 - progress, 3)
        return ClickRippleFrame(diameterScale: 0.35 + 1.15 * eased, alpha: 1 - eased)
    }

    static func active(_ clicks: [OverlayClick], at time: Double) -> [(point: CGPoint, frame: ClickRippleFrame)] {
        clicks.compactMap { click in
            frame(elapsed: time - click.time).map { (click.point, $0) }
        }
    }
}

struct PointerActivity: Hashable, Sendable {
    var pointer: [PointerSample] = []
    var clicks: [PointerSample] = []
    var keyTimes: [Double] = []

    var isEmpty: Bool { pointer.isEmpty && clicks.isEmpty && keyTimes.isEmpty }

    var activityEvents: [ActivityEvent] {
        ActivityEvent.collect(clicks: clicks, keyTimes: keyTimes, pointer: pointer)
    }
}

struct PointerActivityLog: Sendable {
    struct Entry: Hashable, Sendable {
        var time: Double
        var point: CGPoint
        var sourceRect: CGRect
    }

    private(set) var samples: [Entry] = []
    private(set) var clicks: [Entry] = []
    private(set) var keyTimes: [Double] = []

    var isEmpty: Bool { samples.isEmpty && clicks.isEmpty && keyTimes.isEmpty }

    mutating func recordSample(at point: CGPoint, sourceRect: CGRect, time: Double) {
        samples.append(Entry(time: time, point: point, sourceRect: sourceRect))
    }

    mutating func recordClick(at point: CGPoint, sourceRect: CGRect, time: Double) {
        clicks.append(Entry(time: time, point: point, sourceRect: sourceRect))
    }

    mutating func recordKey(time: Double) {
        keyTimes.append(time)
    }

    func activity(recordingStart: Double, videoSize: CGSize, duration: Double = .infinity) -> PointerActivity {
        PointerActivity(
            pointer: Self.mapped(samples, recordingStart: recordingStart, videoSize: videoSize, duration: duration),
            clicks: Self.mapped(clicks, recordingStart: recordingStart, videoSize: videoSize, duration: duration),
            keyTimes: keyTimes.map { $0 - recordingStart }.filter { $0 >= 0 && $0 <= duration }
        )
    }

    private static func mapped(_ entries: [Entry], recordingStart: Double, videoSize: CGSize, duration: Double) -> [PointerSample] {
        entries.compactMap { entry in
            let time = entry.time - recordingStart
            guard time >= 0, time <= duration,
                  let point = OverlayCoordinateMapper.videoPoint(entry.point, sourceRect: entry.sourceRect, videoSize: videoSize)
            else { return nil }
            return PointerSample(time: time, point: point)
        }
        .sorted { $0.time < $1.time }
    }
}

struct RecordingEffectsCapture: Sendable {
    var log: PointerActivityLog
    var contentSize: CGSize
    var pointer: PointerEffectSettings
    var autoZoom: AutoZoomSettings?
}

struct RecordingEffectsPlan: Hashable, Sendable {
    var pointer: PointerTrack?
    var ripples: [OverlayClick] = []
    var rippleColor: CaptureColor = .defaultRipple
    var camera: CameraPath?

    var isEmpty: Bool {
        pointer == nil && ripples.isEmpty && (camera?.isEmpty ?? true)
    }

    static func make(activity: PointerActivity, pointer settings: PointerEffectSettings, autoZoom: AutoZoomSettings?, videoSize: CGSize, duration: Double) -> RecordingEffectsPlan {
        let clickTimes = activity.clicks.map(\.time)
        let track = settings.rendersPointer && !activity.pointer.isEmpty
            ? PointerTrack.make(samples: activity.pointer, clicks: clickTimes, settings: settings, duration: duration)
            : nil
        let ripples = settings.ripples ? activity.clicks.map { OverlayClick(time: $0.time, point: $0.point) } : []
        let camera = autoZoom.map {
            CameraPlanner.plan(activity: activity.activityEvents, pointer: activity.pointer, duration: duration, frameSize: videoSize, settings: $0)
        }
        return RecordingEffectsPlan(pointer: track, ripples: ripples, rippleColor: settings.rippleColor, camera: camera?.isEmpty == false ? camera : nil)
    }

    func withoutCamera() -> RecordingEffectsPlan {
        var plan = self
        plan.camera = nil
        return plan
    }
}
