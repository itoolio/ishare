import AppKit
import Defaults

@MainActor
enum RecordingCountdown {
    static let chimeName = "Tink"
    static let chimeDuration: Duration = .milliseconds(350)

    static func run(seconds: Int = Defaults[.recordingCountdownSeconds]) async -> Bool {
        guard seconds > 0, !ScreenshotMode.isActive else { return true }
        guard await CaptureCountdown.run(seconds: seconds) else {
            Log.capture.info("Recording cancelled during the countdown")
            return false
        }
        if Defaults[.recordingCountdownChime], let chime = NSSound(named: NSSound.Name(chimeName)) {
            chime.play()
            try? await Task.sleep(for: chimeDuration)
        }
        return true
    }
}
