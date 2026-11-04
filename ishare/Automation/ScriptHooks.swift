import Defaults
import Foundation
import ishareCore

enum ScriptHooks {
    static let timeout: Duration = .seconds(60)

    static var isAvailable: Bool {
        #if GITHUB_RELEASE
            true
        #else
            false
        #endif
    }

    static func runs(for event: ScriptHookEvent) -> Bool {
        guard isAvailable, let path = Defaults[.scriptHookPath], !path.isEmpty else { return false }
        switch event {
        case .capture, .recording: return Defaults[.scriptHookAfterCapture]
        case .upload: return Defaults[.scriptHookAfterUpload]
        }
    }

    static func runIfEnabled(_ event: ScriptHookEvent, file: URL, link: URL? = nil) {
        guard runs(for: event), let script = Defaults[.scriptHookPath] else { return }
        Task.detached(priority: .utility) {
            _ = await run(script: script, event: event, file: file.path, link: link?.absoluteString)
        }
    }

    @discardableResult
    static func run(script: String, event: ScriptHookEvent, file: String, link: String?) async -> Int32? {
        let isExecutable = FileManager.default.isExecutableFile(atPath: script)
        let invocation = ScriptHookInvocation.make(script: script, event: event, file: file, link: link, isExecutable: isExecutable)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            if process.isRunning {
                Log.app.error("The script hook took longer than a minute and was stopped")
                process.terminate()
            }
        }
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Log.app.error("The script hook couldn't start: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
        watchdog.cancel()
        guard let status else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        Log.app.info("Script hook for \(event.rawValue, privacy: .public) exited with \(status): \(text, privacy: .public)")
        return status
    }
}
