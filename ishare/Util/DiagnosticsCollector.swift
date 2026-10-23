import Foundation
import MetricKit

final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = DiagnosticsCollector()

    private let store: DiagnosticsStore

    init(store: DiagnosticsStore = .shared) {
        self.store = store
    }

    func start() {
        MXMetricManager.shared.add(self)
        let past = MXMetricManager.shared.pastDiagnosticPayloads
        if !past.isEmpty {
            Task.detached(priority: .utility) { self.record(past) }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        record(payloads)
    }

    private func record(_ payloads: [MXDiagnosticPayload]) {
        var saved = false
        for payload in payloads {
            for (kind, diagnostic) in Self.diagnostics(in: payload) {
                let metadata = diagnostic.metaData
                let result = try? store.save(
                    kind: kind, date: payload.timeStampEnd, summary: Self.summary(of: diagnostic),
                    appVersion: metadata.applicationBuildVersion, osVersion: metadata.osVersion,
                    diagnostic: diagnostic.jsonRepresentation()
                )
                saved = saved || result != nil
            }
        }
        if saved {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DiagnosticsStore.changedNotification, object: nil)
            }
        }
    }

    static func diagnostics(in payload: MXDiagnosticPayload) -> [(DiagnosticKind, MXDiagnostic)] {
        var result: [(DiagnosticKind, MXDiagnostic)] = []
        result += (payload.crashDiagnostics ?? []).map { (.crash, $0) }
        result += (payload.hangDiagnostics ?? []).map { (.hang, $0) }
        result += (payload.cpuExceptionDiagnostics ?? []).map { (.cpuException, $0) }
        result += (payload.diskWriteExceptionDiagnostics ?? []).map { (.diskWriteException, $0) }
        return result
    }

    static func summary(of diagnostic: MXDiagnostic) -> String {
        switch diagnostic {
        case let crash as MXCrashDiagnostic:
            return [
                crash.exceptionType.map { "exception type \($0)" },
                crash.exceptionCode.map { "code \($0)" },
                crash.signal.map { "signal \($0)" },
                crash.terminationReason,
            ].compactMap { $0 }.joined(separator: ", ")
        case let hang as MXHangDiagnostic:
            return "hung for \(hang.hangDuration.converted(to: .seconds).formatted())"
        case let cpu as MXCPUExceptionDiagnostic:
            return "\(cpu.totalCPUTime.converted(to: .seconds).formatted()) of CPU time"
        case let disk as MXDiskWriteExceptionDiagnostic:
            return "\(disk.totalWritesCaused.converted(to: .megabytes).formatted()) written"
        default:
            return ""
        }
    }
}
