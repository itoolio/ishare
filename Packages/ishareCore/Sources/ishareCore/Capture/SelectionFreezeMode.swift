import Foundation

public enum SelectionFreezeMode: String, Codable, Sendable, CaseIterable {
    case frozen
    case live

    public init(prefersFrozen: Bool) {
        self = prefersFrozen ? .frozen : .live
    }

    public var toggled: SelectionFreezeMode {
        self == .frozen ? .live : .frozen
    }

    public var loadsBackdrops: Bool {
        self == .frozen
    }
}

public enum SelectionImageSource: Equatable, Sendable {
    case backdrop
    case liveCapture(settle: Duration)
    case afterCountdown
}

public enum SelectionMagnifierSource: Equatable, Sendable {
    case backdrop
    case pending
    case liveSample
    case position
    case hidden
}

public enum SelectionFreezePolicy {
    public static let liveSettleDelay: Duration = .milliseconds(80)

    public static func imageSource(mode: SelectionFreezeMode, hasBackdrop: Bool, delay: Int) -> SelectionImageSource {
        if delay > 0 { return .afterCountdown }
        switch mode {
        case .frozen: return hasBackdrop ? .backdrop : .liveCapture(settle: .zero)
        case .live: return .liveCapture(settle: liveSettleDelay)
        }
    }

    public static func magnifierSource(
        enabled: Bool, mode: SelectionFreezeMode, hasBackdrop: Bool, awaitingBackdrop: Bool, liveSamplingAvailable: Bool
    ) -> SelectionMagnifierSource {
        guard enabled else { return .hidden }
        switch mode {
        case .frozen:
            if hasBackdrop { return .backdrop }
            return awaitingBackdrop ? .pending : .position
        case .live:
            return liveSamplingAvailable ? .liveSample : .position
        }
    }
}

public struct SamplingThrottle: Hashable, Sendable {
    public let minimumInterval: TimeInterval
    public let slowLatency: TimeInterval
    public let slowSampleLimit: Int
    public private(set) var isInFlight = false
    public private(set) var isDisabled = false
    private var lastStart: TimeInterval?
    private var consecutiveSlowSamples = 0
    private var consecutiveFailures = 0

    public init(minimumInterval: TimeInterval = 1.0 / 15, slowLatency: TimeInterval = 0.25, slowSampleLimit: Int = 3) {
        self.minimumInterval = minimumInterval
        self.slowLatency = slowLatency
        self.slowSampleLimit = max(1, slowSampleLimit)
    }

    public func delayBeforeNextRequest(at now: TimeInterval) -> TimeInterval? {
        guard !isDisabled, !isInFlight else { return nil }
        guard let lastStart else { return 0 }
        return max(0, minimumInterval - (now - lastStart))
    }

    public mutating func begin(at now: TimeInterval) {
        isInFlight = true
        lastStart = now
    }

    public mutating func finish(at now: TimeInterval) {
        isInFlight = false
        consecutiveFailures = 0
        let latency = now - (lastStart ?? now)
        if latency > slowLatency {
            consecutiveSlowSamples += 1
            if consecutiveSlowSamples >= slowSampleLimit {
                isDisabled = true
            }
        } else {
            consecutiveSlowSamples = 0
        }
    }

    public mutating func fail() {
        isInFlight = false
        consecutiveFailures += 1
        if consecutiveFailures >= slowSampleLimit {
            isDisabled = true
        }
    }
}
