import Foundation

enum RecordingStatusText {
    static func clock(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }

    static func remaining(_ seconds: Double) -> String {
        "−" + clock(seconds.rounded(.up))
    }

    static func toolTip(isRecording: Bool, isPaused: Bool, remaining seconds: Double?) -> String? {
        guard isRecording else { return nil }
        let state = isPaused ? "Recording paused".localized() : "Recording".localized()
        guard let seconds else { return state }
        return String(format: "%@ · %@ left".localized(), state, clock(seconds.rounded(.up)))
    }
}
