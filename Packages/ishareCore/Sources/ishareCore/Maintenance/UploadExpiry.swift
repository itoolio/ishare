import Foundation

public struct MaintenanceClock: Sendable {
    public var now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    public static let system = MaintenanceClock { Date() }

    public static func fixed(_ date: Date) -> MaintenanceClock {
        MaintenanceClock { date }
    }
}

public enum AutoDeletePreset: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case custom = -1

    public var id: Self { self }

    public init(days: Int?) {
        guard let days, days > 0 else {
            self = .off
            return
        }
        self = AutoDeletePreset(rawValue: days) ?? .custom
    }

    public var days: Int? {
        rawValue > 0 ? rawValue : nil
    }

    public var titleKey: String {
        switch self {
        case .off: "Off"
        case .oneDay: "After 1 day"
        case .sevenDays: "After 7 days"
        case .thirtyDays: "After 30 days"
        case .ninetyDays: "After 90 days"
        case .custom: "Custom"
        }
    }
}

public struct UploadExpiryState: Equatable, Sendable {
    public var expiresAt: Date?
    public var keepForever: Bool
    public var expiredAt: Date?
    public var attempts: Int
    public var nextAttemptAt: Date?
    public var lastError: String?

    public init(
        expiresAt: Date?, keepForever: Bool = false, expiredAt: Date? = nil, attempts: Int = 0, nextAttemptAt: Date? = nil, lastError: String? = nil
    ) {
        self.expiresAt = expiresAt
        self.keepForever = keepForever
        self.expiredAt = expiredAt
        self.attempts = attempts
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
    }
}

public enum UploadExpiryDecision: Equatable, Sendable {
    case none
    case keptForever
    case alreadyExpired
    case gaveUp
    case scheduled(Date)
    case retrying(Date)
    case due
}

public struct UploadExpirySummary: Equatable, Sendable {
    public var deleted: Int
    public var failed: Int
    public var errors: [String]

    public init(deleted: Int = 0, failed: Int = 0, errors: [String] = []) {
        self.deleted = deleted
        self.failed = failed
        self.errors = errors
    }

    public var isEmpty: Bool { deleted == 0 && failed == 0 }
}

public enum UploadExpiry {
    public static let maximumDays = 3650
    public static let maximumAttempts = 10
    public static let firstRetryDelay: TimeInterval = 15 * 60
    public static let maximumRetryDelay: TimeInterval = 86400
    public static let runInterval: TimeInterval = 86400

    public static func isValid(days: Int) -> Bool {
        (1 ... maximumDays).contains(days)
    }

    public static func expiryDate(uploadedAt: Date, days: Int?) -> Date? {
        guard let days, isValid(days: days) else { return nil }
        return uploadedAt.addingTimeInterval(TimeInterval(days) * 86400)
    }

    public static func retryDelay(afterAttempts attempts: Int) -> TimeInterval {
        min(firstRetryDelay * pow(2, Double(max(attempts - 1, 0))), maximumRetryDelay)
    }

    public static func decision(for state: UploadExpiryState, now: Date) -> UploadExpiryDecision {
        guard let expiresAt = state.expiresAt else { return .none }
        if state.keepForever { return .keptForever }
        if state.expiredAt != nil { return .alreadyExpired }
        if state.attempts >= maximumAttempts { return .gaveUp }
        if expiresAt > now { return .scheduled(expiresAt) }
        if let next = state.nextAttemptAt, next > now { return .retrying(next) }
        return .due
    }

    public static func isDue(_ state: UploadExpiryState, now: Date) -> Bool {
        decision(for: state, now: now) == .due
    }

    public static func dueIndices(_ states: [UploadExpiryState], now: Date) -> [Int] {
        states.indices.filter { isDue(states[$0], now: now) }
    }

    public static func failed(_ state: UploadExpiryState, error: String, now: Date) -> UploadExpiryState {
        var updated = state
        updated.attempts += 1
        updated.lastError = error
        updated.nextAttemptAt = now.addingTimeInterval(retryDelay(afterAttempts: updated.attempts))
        return updated
    }

    public static func expired(_ state: UploadExpiryState, now: Date) -> UploadExpiryState {
        var updated = state
        updated.expiredAt = now
        updated.nextAttemptAt = nil
        updated.lastError = nil
        return updated
    }

    public static func nextWakeUp(_ states: [UploadExpiryState], now: Date) -> Date? {
        states.compactMap { state -> Date? in
            switch decision(for: state, now: now) {
            case let .scheduled(date), let .retrying(date): date
            case .due: now
            default: nil
            }
        }.min()
    }
}

public enum MaintenanceSchedule {
    public static func isDue(lastRun: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval || lastRun > now
    }
}
