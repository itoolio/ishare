import CoreGraphics
import Defaults
import Foundation
import ishareCore

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

    init(
        recordsPointer: Bool = true, smoothing: Bool = false, scale: Double = 1, ripples: Bool = false, rippleColor: CaptureColor = .defaultRipple, hidesWhenIdle: Bool = false,
        idleDelay: Double = 3
    ) {
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

extension PointerTrack {
    static func make(samples: [PointerSample], clicks: [Double], settings: PointerEffectSettings, duration: Double) -> PointerTrack {
        let sorted = samples.sorted { $0.time < $1.time }
        let positions = settings.smoothing ? PointerSmoother.smooth(sorted) : sorted
        let hidden = settings.hidesWhenIdle ? PointerIdleDetector.hiddenIntervals(samples: sorted, clicks: clicks, idleDelay: settings.idleDelay, duration: duration) : []
        return PointerTrack(samples: positions, hiddenIntervals: hidden, scale: settings.scale)
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
        let track =
            settings.rendersPointer && !activity.pointer.isEmpty
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
