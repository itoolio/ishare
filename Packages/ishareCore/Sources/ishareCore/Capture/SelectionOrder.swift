import Foundation

public struct SelectionOrderLog: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case freezeFramesReady(at: Double)
        case selectorShown(at: Double)
    }

    public private(set) var events: [Event] = []
    public var expectsFreezeFrames: Bool

    public init(expectsFreezeFrames: Bool) {
        self.expectsFreezeFrames = expectsFreezeFrames
    }

    public mutating func record(_ event: Event) {
        events.append(event)
    }

    public var violation: String? {
        guard expectsFreezeFrames else { return nil }
        let ready = events.compactMap { if case let .freezeFramesReady(time) = $0 { time } else { nil } }.min()
        let shown = events.compactMap { if case let .selectorShown(time) = $0 { time } else { nil } }.min()
        guard let shown else { return nil }
        guard let ready else { return "the selector appeared before any freeze-frame was captured" }
        return ready <= shown ? nil : String(format: "the selector appeared %.0f ms before the freeze-frames were ready", (ready - shown) * 1000)
    }
}

public enum SelectionPrefetchPolicy {
    public static let maximumAge: Double = 0.75

    public static func isUsable(startedAt start: Double?, now: Double, maximumAge: Double = maximumAge) -> Bool {
        guard let start else { return false }
        let age = now - start
        return age >= 0 && age <= maximumAge
    }
}
