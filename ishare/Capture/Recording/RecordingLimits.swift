import BezelNotification
import Defaults
import Foundation
import ishareCore

extension RecordingLimits {
    static var current: RecordingLimits {
        make(maxMinutes: RecordingDefaults[.recordingMaxMinutes], maxMegabytes: RecordingDefaults[.recordingMaxMegabytes], lowDiskMegabytes: Defaults[.recordingLowDiskWarningMB])
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
    var recordedTime: (() -> Double)?
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
        let elapsed = recordedTime?() ?? now.timeIntervalSince(startDate)
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
