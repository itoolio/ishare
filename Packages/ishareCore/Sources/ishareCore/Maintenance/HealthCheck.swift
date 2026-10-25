import Foundation

public enum HealthCheckFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case daily
    case weekly

    public var id: Self { self }

    public var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .daily: 86400
        case .weekly: 7 * 86400
        }
    }

    public var titleKey: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

public struct HealthCheckConditions: Equatable, Sendable {
    public var batteryLevel: Int?
    public var isOnBattery: Bool
    public var isConstrained: Bool
    public var isExpensive: Bool

    public init(batteryLevel: Int? = nil, isOnBattery: Bool = false, isConstrained: Bool = false, isExpensive: Bool = false) {
        self.batteryLevel = batteryLevel
        self.isOnBattery = isOnBattery
        self.isConstrained = isConstrained
        self.isExpensive = isExpensive
    }

    public static let ideal = HealthCheckConditions()
}

public enum HealthCheckSkipReason: String, Equatable, Sendable {
    case lowBattery
    case constrainedNetwork
    case expensiveNetwork
    case notDue
    case disabled
    case noUploader
    case unsupportedUploader
}

public enum HealthCheckPlanner {
    public static let minimumBatteryLevel = 20

    public static func blockingCondition(_ conditions: HealthCheckConditions) -> HealthCheckSkipReason? {
        if conditions.isOnBattery, let level = conditions.batteryLevel, level < minimumBatteryLevel {
            return .lowBattery
        }
        if conditions.isConstrained {
            return .constrainedNetwork
        }
        if conditions.isExpensive {
            return .expensiveNetwork
        }
        return nil
    }

    public static func isDue(frequency: HealthCheckFrequency, lastCheck: Date?, now: Date) -> Bool {
        guard let interval = frequency.interval else { return false }
        return MaintenanceSchedule.isDue(lastRun: lastCheck, interval: interval, now: now)
    }

    public static func skipReason(
        frequency: HealthCheckFrequency, lastCheck: Date?, conditions: HealthCheckConditions, now: Date, forced: Bool = false
    ) -> HealthCheckSkipReason? {
        if !forced {
            guard frequency != .off else { return .disabled }
            guard isDue(frequency: frequency, lastCheck: lastCheck, now: now) else { return .notDue }
        }
        return blockingCondition(conditions)
    }

    public static func nextCheck(frequency: HealthCheckFrequency, lastCheck: Date?, now: Date) -> Date? {
        guard let interval = frequency.interval else { return nil }
        guard let lastCheck else { return now }
        return max(lastCheck.addingTimeInterval(interval), now)
    }
}

public struct HealthCheckRecord: Codable, Equatable, Sendable {
    public var date: Date
    public var succeeded: Bool
    public var message: String?
    public var uploaderName: String?
    public var method: HealthCheckMethod?

    public init(date: Date, succeeded: Bool, message: String? = nil, uploaderName: String? = nil, method: HealthCheckMethod? = nil) {
        self.date = date
        self.succeeded = succeeded
        self.message = message
        self.uploaderName = uploaderName
        self.method = method
    }
}

public enum HealthCheckMethod: String, Codable, Equatable, Sendable {
    case upload
    case uploadAndDelete
    case probe
}

public enum HealthCheckProbe {
    public static let fileName = "ishare-health-check.png"

    public static let tinyPNG = Data(
        [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82,
        ])
}
