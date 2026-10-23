import BezelNotification
import Defaults
import Foundation

struct RecordingLimits: Equatable, Sendable {
    static let megabyte: Int64 = 1024 * 1024
    static let criticalDiskBytes: Int64 = 512 * megabyte

    var maxDuration: Double?
    var maxBytes: Int64?
    var lowDiskBytes: Int64
    var criticalDiskBytes: Int64

    init(maxDuration: Double? = nil, maxBytes: Int64? = nil, lowDiskBytes: Int64 = 2048 * megabyte, criticalDiskBytes: Int64 = criticalDiskBytes) {
        self.maxDuration = maxDuration.flatMap { $0 > 0 ? $0 : nil }
        self.maxBytes = maxBytes.flatMap { $0 > 0 ? $0 : nil }
        self.lowDiskBytes = max(0, lowDiskBytes)
        self.criticalDiskBytes = min(max(0, criticalDiskBytes), max(0, lowDiskBytes))
    }

    static func make(maxMinutes: Int, maxMegabytes: Int, lowDiskMegabytes: Int) -> RecordingLimits {
        RecordingLimits(
            maxDuration: maxMinutes > 0 ? Double(maxMinutes) * 60 : nil,
            maxBytes: maxMegabytes > 0 ? Int64(maxMegabytes) * megabyte : nil,
            lowDiskBytes: Int64(max(0, lowDiskMegabytes)) * megabyte
        )
    }

    static var current: RecordingLimits {
        make(maxMinutes: Defaults[.recordingMaxMinutes], maxMegabytes: Defaults[.recordingMaxMegabytes], lowDiskMegabytes: Defaults[.recordingLowDiskWarningMB])
    }

    var hasRecordingLimit: Bool {
        maxDuration != nil || maxBytes != nil
    }
}

enum RecordingStopReason: Equatable, Sendable {
    case duration
    case size
    case diskSpace

    var message: String {
        switch self {
        case .duration: "Recording stopped: time limit reached"
        case .size: "Recording stopped: size limit reached"
        case .diskSpace: "Recording stopped: the disk is almost full"
        }
    }
}

enum RecordingLimitDecision: Equatable, Sendable {
    case keepRecording
    case warnLowDisk
    case stop(RecordingStopReason)
}

enum RecordingLimitPolicy {
    static let minimumEstimateSeconds: Double = 3
    static let warningRearmFactor: Double = 1.1

    static func decision(elapsed: Double, bytesWritten: Int64, freeBytes: Int64?, limits: RecordingLimits, hasWarned: Bool) -> RecordingLimitDecision {
        if let freeBytes, freeBytes <= limits.criticalDiskBytes { return .stop(.diskSpace) }
        if let maxDuration = limits.maxDuration, elapsed >= maxDuration { return .stop(.duration) }
        if let maxBytes = limits.maxBytes, bytesWritten >= maxBytes { return .stop(.size) }
        if let freeBytes, freeBytes < limits.lowDiskBytes, !hasWarned { return .warnLowDisk }
        return .keepRecording
    }

    static func rearmsWarning(freeBytes: Int64?, limits: RecordingLimits) -> Bool {
        guard let freeBytes else { return false }
        return Double(freeBytes) >= Double(limits.lowDiskBytes) * warningRearmFactor
    }

    static func remainingTime(elapsed: Double, bytesWritten: Int64, limits: RecordingLimits) -> Double? {
        let byDuration = limits.maxDuration.map { max(0, $0 - elapsed) }
        let bySize = limits.maxBytes.flatMap { maxBytes -> Double? in
            guard elapsed >= minimumEstimateSeconds, bytesWritten > 0 else { return nil }
            let rate = Double(bytesWritten) / elapsed
            return max(0, Double(maxBytes - bytesWritten) / rate)
        }
        return [byDuration, bySize].compactMap(\.self).min()
    }
}

enum DiskSpace {
    static func availableBytes(near url: URL) -> Int64? {
        let candidates = [url, url.deletingLastPathComponent()]
        for candidate in candidates {
            if let values = try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
        }
        return nil
    }
}

@MainActor
final class RecordingLimitMonitor {
    private static let tickInterval: Double = 1
    private static let diskCheckInterval: Double = 5

    private var timer: Timer?
    private var startDate = Date()
    private var limits = RecordingLimits()
    private var fileURL: URL?
    private var hasWarned = false
    private var freeBytes: Int64?
    private var lastDiskCheck: Date = .distantPast
    private var didStop = false

    var bytesWritten: () -> Int64 = { 0 }
    var onRemainingTime: (Double?) -> Void = { _ in }
    var onStop: (RecordingStopReason) -> Void = { _ in }

    func start(fileURL: URL, startDate: Date, limits: RecordingLimits = .current) {
        stop()
        self.fileURL = fileURL
        self.startDate = startDate
        self.limits = limits
        hasWarned = false
        didStop = false
        freeBytes = nil
        lastDiskCheck = .distantPast
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fileURL = nil
    }

    private func tick() {
        guard !didStop, let fileURL else { return }
        let now = Date()
        if now.timeIntervalSince(lastDiskCheck) >= Self.diskCheckInterval {
            freeBytes = DiskSpace.availableBytes(near: fileURL)
            lastDiskCheck = now
            if hasWarned, RecordingLimitPolicy.rearmsWarning(freeBytes: freeBytes, limits: limits) {
                hasWarned = false
            }
        }
        let elapsed = now.timeIntervalSince(startDate)
        let bytes = bytesWritten()
        if limits.hasRecordingLimit {
            onRemainingTime(RecordingLimitPolicy.remainingTime(elapsed: elapsed, bytesWritten: bytes, limits: limits))
        }
        switch RecordingLimitPolicy.decision(elapsed: elapsed, bytesWritten: bytes, freeBytes: freeBytes, limits: limits, hasWarned: hasWarned) {
        case .keepRecording:
            break
        case .warnLowDisk:
            hasWarned = true
            let free = ByteCountFormatter.string(fromByteCount: freeBytes ?? 0, countStyle: .file)
            Log.capture.info("Free disk space is low while recording: \(free, privacy: .public)")
            BezelNotification.show(messageText: String(format: "Low disk space: %@ left".localized(), free), icon: ToastIcon)
        case let .stop(reason):
            didStop = true
            Log.capture.info("Stopping the recording automatically: \(reason.message, privacy: .public)")
            stop()
            onStop(reason)
        }
    }
}
