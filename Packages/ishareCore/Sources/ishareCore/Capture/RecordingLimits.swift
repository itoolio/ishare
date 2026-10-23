import Foundation

public struct RecordingLimits: Equatable, Sendable {
    public static let megabyte: Int64 = 1024 * 1024
    public static let criticalDiskBytes: Int64 = 512 * megabyte

    var maxDuration: Double?
    var maxBytes: Int64?
    var lowDiskBytes: Int64
    var criticalDiskBytes: Int64

    public init(maxDuration: Double? = nil, maxBytes: Int64? = nil, lowDiskBytes: Int64 = 2048 * megabyte, criticalDiskBytes: Int64 = criticalDiskBytes) {
        self.maxDuration = maxDuration.flatMap { $0 > 0 ? $0 : nil }
        self.maxBytes = maxBytes.flatMap { $0 > 0 ? $0 : nil }
        self.lowDiskBytes = max(0, lowDiskBytes)
        self.criticalDiskBytes = min(max(0, criticalDiskBytes), max(0, lowDiskBytes))
    }

    public static func make(maxMinutes: Int, maxMegabytes: Int, lowDiskMegabytes: Int) -> RecordingLimits {
        RecordingLimits(
            maxDuration: maxMinutes > 0 ? Double(maxMinutes) * 60 : nil,
            maxBytes: maxMegabytes > 0 ? Int64(maxMegabytes) * megabyte : nil,
            lowDiskBytes: Int64(max(0, lowDiskMegabytes)) * megabyte
        )
    }

    public var hasRecordingLimit: Bool {
        maxDuration != nil || maxBytes != nil
    }
}

public enum RecordingStopReason: Equatable, Sendable {
    case duration
    case size
    case diskSpace

    public var message: String {
        switch self {
        case .duration: "Recording stopped: time limit reached"
        case .size: "Recording stopped: size limit reached"
        case .diskSpace: "Recording stopped: the disk is almost full"
        }
    }
}

public enum RecordingLimitDecision: Equatable, Sendable {
    case keepRecording
    case warnLowDisk
    case stop(RecordingStopReason)
}

public enum RecordingLimitPolicy {
    static let minimumEstimateSeconds: Double = 3
    static let warningRearmFactor: Double = 1.1

    public static func decision(elapsed: Double, bytesWritten: Int64, freeBytes: Int64?, limits: RecordingLimits, hasWarned: Bool) -> RecordingLimitDecision {
        if let freeBytes, freeBytes <= limits.criticalDiskBytes { return .stop(.diskSpace) }
        if let maxDuration = limits.maxDuration, elapsed >= maxDuration { return .stop(.duration) }
        if let maxBytes = limits.maxBytes, bytesWritten >= maxBytes { return .stop(.size) }
        if let freeBytes, freeBytes < limits.lowDiskBytes, !hasWarned { return .warnLowDisk }
        return .keepRecording
    }

    public static func rearmsWarning(freeBytes: Int64?, limits: RecordingLimits) -> Bool {
        guard let freeBytes else { return false }
        return Double(freeBytes) >= Double(limits.lowDiskBytes) * warningRearmFactor
    }

    public static func remainingTime(elapsed: Double, bytesWritten: Int64, limits: RecordingLimits) -> Double? {
        let byDuration = limits.maxDuration.map { max(0, $0 - elapsed) }
        let bySize = limits.maxBytes.flatMap { maxBytes -> Double? in
            guard elapsed >= minimumEstimateSeconds, bytesWritten > 0 else { return nil }
            let rate = Double(bytesWritten) / elapsed
            return max(0, Double(maxBytes - bytesWritten) / rate)
        }
        return [byDuration, bySize].compactMap(\.self).min()
    }
}

public enum DiskSpace {
    public static func availableBytes(near url: URL) -> Int64? {
        let candidates = [url, url.deletingLastPathComponent()]
        for candidate in candidates {
            if let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
                let capacity = values.volumeAvailableCapacityForImportantUsage
            {
                return capacity
            }
        }
        return nil
    }
}
