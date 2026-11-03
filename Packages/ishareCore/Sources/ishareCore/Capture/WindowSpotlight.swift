import CoreGraphics
import Foundation

public struct SpotlightStyle: Hashable, Sendable {
    public static let dimmingRange: ClosedRange<Double> = 0.3 ... 0.8

    public var dimming: Double
    public var blursBackground: Bool

    public init(dimming: Double = 0.5, blursBackground: Bool = false) {
        self.dimming = dimming.clamped(to: Self.dimmingRange)
        self.blursBackground = blursBackground
    }
}

public struct SpotlightSample: Hashable, Sendable {
    public var time: Double
    public var windowID: UInt32?
    public var frame: CGRect?

    public init(time: Double, windowID: UInt32?, frame: CGRect?) {
        self.time = time
        self.windowID = windowID
        self.frame = frame
    }
}

public struct SpotlightFrame: Hashable, Sendable {
    public var rect: CGRect
    public var strength: Double

    public init(rect: CGRect, strength: Double) {
        self.rect = rect
        self.strength = strength
    }

    static let none = SpotlightFrame(rect: .zero, strength: 0)

    func interpolated(to other: SpotlightFrame, fraction: Double) -> SpotlightFrame {
        let t = fraction.clamped(to: 0 ... 1)
        return SpotlightFrame(
            rect: CGRect(
                x: rect.minX + (other.rect.minX - rect.minX) * t,
                y: rect.minY + (other.rect.minY - rect.minY) * t,
                width: rect.width + (other.rect.width - rect.width) * t,
                height: rect.height + (other.rect.height - rect.height) * t
            ),
            strength: strength + (other.strength - strength) * t
        )
    }
}

public struct SpotlightTimeline: Hashable, Sendable {
    public static let focusTransition: Double = 0.35
    public static let followDuration: Double = 0.1
    static let visibleStrength: Double = 0.001

    struct Move: Hashable, Sendable {
        var start: Double
        var duration: Double
        var from: SpotlightFrame
        var to: SpotlightFrame
        var eased: Bool

        func frame(at time: Double) -> SpotlightFrame {
            guard duration > 0 else { return to }
            let progress = ((time - start) / duration).clamped(to: 0 ... 1)
            return from.interpolated(to: to, fraction: eased ? Self.smoothstep(progress) : progress)
        }

        static func smoothstep(_ value: Double) -> Double {
            value * value * (3 - 2 * value)
        }
    }

    private(set) var moves: [Move] = []

    public init(samples: [SpotlightSample], focusTransition: Double = Self.focusTransition, followDuration: Double = Self.followDuration) {
        var lastWindowID: UInt32?
        var lastFrame: CGRect?
        for sample in samples.sorted(by: { $0.time < $1.time }) {
            guard let previous = moves.last else {
                let initial = sample.frame.map { SpotlightFrame(rect: $0, strength: 1) } ?? .none
                moves.append(Move(start: sample.time, duration: 0, from: initial, to: initial, eased: false))
                lastWindowID = sample.windowID
                lastFrame = sample.frame
                continue
            }
            guard sample.frame != lastFrame || sample.windowID != lastWindowID else { continue }
            let current = previous.frame(at: sample.time)
            moves.append(Self.move(from: current, to: sample, sameWindow: sample.windowID == lastWindowID, focusTransition: focusTransition, followDuration: followDuration))
            lastWindowID = sample.windowID
            lastFrame = sample.frame
        }
    }

    private static func move(from current: SpotlightFrame, to sample: SpotlightSample, sameWindow: Bool, focusTransition: Double, followDuration: Double) -> Move {
        guard let frame = sample.frame else {
            return Move(start: sample.time, duration: focusTransition, from: current, to: SpotlightFrame(rect: current.rect, strength: 0), eased: true)
        }
        let target = SpotlightFrame(rect: frame, strength: 1)
        if current.strength < visibleStrength {
            return Move(start: sample.time, duration: focusTransition, from: SpotlightFrame(rect: frame, strength: 0), to: target, eased: true)
        }
        if sameWindow {
            return Move(start: sample.time, duration: followDuration, from: current, to: target, eased: false)
        }
        return Move(start: sample.time, duration: focusTransition, from: current, to: target, eased: true)
    }

    public var isEmpty: Bool {
        !moves.contains { $0.from.strength >= Self.visibleStrength || $0.to.strength >= Self.visibleStrength }
    }

    public var changeCount: Int {
        max(0, moves.count - 1)
    }

    public func frame(at time: Double) -> SpotlightFrame? {
        guard let first = moves.first else { return nil }
        let frame = time < first.start ? first.from : moves[lastMoveIndex(atOrBefore: time)].frame(at: time)
        return frame.strength >= Self.visibleStrength && frame.rect.width > 0 && frame.rect.height > 0 ? frame : nil
    }

    private func lastMoveIndex(atOrBefore time: Double) -> Int {
        var low = 0
        var high = moves.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if moves[middle].start <= time { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

public enum SpotlightGeometry {
    public static func videoRect(windowFrame: CGRect, sourceRect: CGRect, videoSize: CGSize) -> CGRect? {
        guard sourceRect.width > 0, sourceRect.height > 0, videoSize.width > 0, videoSize.height > 0 else { return nil }
        let visible = windowFrame.intersection(sourceRect)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return nil }
        let scale = min(videoSize.width / sourceRect.width, videoSize.height / sourceRect.height)
        let contentOrigin = CGPoint(x: (videoSize.width - sourceRect.width * scale) / 2, y: (videoSize.height - sourceRect.height * scale) / 2)
        return CGRect(
            x: contentOrigin.x + (visible.minX - sourceRect.minX) * scale,
            y: contentOrigin.y + (visible.minY - sourceRect.minY) * scale,
            width: visible.width * scale,
            height: visible.height * scale
        )
    }

    public static func flipped(_ rect: CGRect, videoHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: videoHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

public enum FocusedWindowPicker {
    public static let minimumSide: CGFloat = 40

    public static func focusedWindow(in windows: [WindowDescriptor], frontmostPID: Int32?) -> WindowDescriptor? {
        guard let frontmostPID else { return nil }
        return windows.first { window in
            window.ownerPID == frontmostPID && window.layer == 0 && window.isOnScreen && window.frame.width >= minimumSide && window.frame.height >= minimumSide
        }
    }
}
