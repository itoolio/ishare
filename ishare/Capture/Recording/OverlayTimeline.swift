import CoreGraphics
import CoreMedia
import Foundation

enum RecordingClock {
    static var now: Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}

enum OverlayCoordinateMapper {
    static func contentFrame(sourceSize: CGSize, videoSize: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, videoSize.width > 0, videoSize.height > 0 else { return .zero }
        let scale = min(videoSize.width / sourceSize.width, videoSize.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: (videoSize.width - size.width) / 2, y: (videoSize.height - size.height) / 2, width: size.width, height: size.height)
    }

    static func videoPoint(_ point: CGPoint, sourceRect: CGRect, videoSize: CGSize) -> CGPoint? {
        guard sourceRect.contains(point) else { return nil }
        let content = contentFrame(sourceSize: sourceRect.size, videoSize: videoSize)
        guard content.width > 0 else { return nil }
        let scale = content.width / sourceRect.width
        return CGPoint(x: content.minX + (point.x - sourceRect.minX) * scale, y: content.minY + (point.y - sourceRect.minY) * scale)
    }

    static func cgGlobalPoint(fromCocoa point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func pixelsPerPoint(sourceSize: CGSize, videoSize: CGSize) -> CGFloat {
        let content = contentFrame(sourceSize: sourceSize, videoSize: videoSize)
        guard sourceSize.width > 0, content.width > 0 else { return 1 }
        return content.width / sourceSize.width
    }

    static func flipped(_ point: CGPoint, videoHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: videoHeight - point.y)
    }
}

struct OverlayClick: Hashable, Sendable {
    var time: Double
    var point: CGPoint
}

struct OverlayKeystrokeSpan: Hashable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

struct OverlayWebcamClip: Hashable, Sendable {
    var url: URL
    var offset: Double
}

struct OverlayEventLog: Sendable {
    struct Click: Hashable, Sendable {
        var time: Double
        var point: CGPoint
        var sourceRect: CGRect
    }

    struct Key: Equatable, Sendable {
        var time: Double
        var keystroke: Keystroke
    }

    private(set) var clicks: [Click] = []
    private(set) var keys: [Key] = []

    var isEmpty: Bool { clicks.isEmpty && keys.isEmpty }

    mutating func recordClick(at point: CGPoint, sourceRect: CGRect, time: Double) {
        clicks.append(Click(time: time, point: point, sourceRect: sourceRect))
    }

    mutating func recordKey(_ keystroke: Keystroke, time: Double) {
        keys.append(Key(time: time, keystroke: keystroke))
    }

    func timeline(recordingStart: Double, videoSize: CGSize, webcam: OverlayWebcamClip? = nil, duration: Double = .infinity) -> OverlayTimeline {
        let mappedClicks = clicks.compactMap { click -> OverlayClick? in
            let time = click.time - recordingStart
            guard time >= 0, time <= duration,
                  let point = OverlayCoordinateMapper.videoPoint(click.point, sourceRect: click.sourceRect, videoSize: videoSize)
            else { return nil }
            return OverlayClick(time: time, point: point)
        }
        let spans = OverlayTimeline.keystrokeSpans(for: keys.map { ($0.time - recordingStart, $0.keystroke) }, duration: duration)
        return OverlayTimeline(clicks: mappedClicks, keystrokes: spans, webcam: webcam)
    }
}

struct OverlayTimeline: Hashable, Sendable {
    static let rippleLifetime: Double = 0.7
    static let rippleAnimation: Double = 0.6
    static let keystrokeLifetime: Double = 1.6

    var clicks: [OverlayClick] = []
    var keystrokes: [OverlayKeystrokeSpan] = []
    var webcam: OverlayWebcamClip?
    var effects = RecordingEffectsPlan()

    var isEmpty: Bool { clicks.isEmpty && keystrokes.isEmpty && webcam == nil && effects.isEmpty }

    func ripples(at time: Double) -> [(point: CGPoint, progress: Double)] {
        clicks
            .filter { time >= $0.time && time < $0.time + Self.rippleLifetime }
            .map { ($0.point, min(1, (time - $0.time) / Self.rippleAnimation)) }
    }

    func keystroke(at time: Double) -> String? {
        keystrokes.last { time >= $0.start && time < $0.end }?.text
    }

    static func keystrokeSpans(for keys: [(time: Double, keystroke: Keystroke)], duration: Double = .infinity) -> [OverlayKeystrokeSpan] {
        var ticker = KeystrokeTicker()
        var spans: [OverlayKeystrokeSpan] = []
        for key in keys.sorted(by: { $0.time < $1.time }) where key.time >= 0 && key.time <= duration {
            ticker.register(key.keystroke, at: Date(timeIntervalSinceReferenceDate: key.time))
            if let last = spans.last, last.end > key.time {
                spans[spans.count - 1].end = key.time
            }
            spans.append(OverlayKeystrokeSpan(start: key.time, end: min(duration, key.time + keystrokeLifetime), text: ticker.text))
        }
        return spans.filter { $0.end > $0.start }
    }
}

struct OverlayCompositionLayout: Hashable, Sendable {
    var videoSize: CGSize
    var pixelsPerPoint: CGFloat
    var webcamFrame: CGRect?

    static func make(videoSize: CGSize, sourceSize: CGSize, webcamDiameter: CGFloat?, corner: WebcamCorner) -> OverlayCompositionLayout {
        let scale = OverlayCoordinateMapper.pixelsPerPoint(sourceSize: sourceSize, videoSize: videoSize)
        let webcamFrame = webcamDiameter.map { diameter -> CGRect in
            let area = CGRect(x: 0, y: 0, width: videoSize.width / scale, height: videoSize.height / scale)
            let frame = WebcamBubbleLayout.frame(diameter: diameter, corner: corner, in: area)
            return CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
        }
        return OverlayCompositionLayout(videoSize: videoSize, pixelsPerPoint: scale, webcamFrame: webcamFrame)
    }

    func keystrokeCenter() -> CGPoint {
        let heightInPoints = videoSize.height / pixelsPerPoint
        let fromBottom = heightInPoints - max(40, heightInPoints - 64)
        return CGPoint(x: videoSize.width / 2, y: fromBottom * pixelsPerPoint)
    }
}
