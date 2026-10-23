import AppKit
import Defaults
import Foundation

@MainActor
enum RecordingFlow {
    static func recordingURL() -> URL {
        let suffix = NSWorkspace.shared.frontmostApplication?.localizedName ?? "screen"
        let ext = Defaults[.recordMP4] ? "mp4" : "mov"
        let fileName = CaptureFileName.make(prefix: Defaults[.recordingFileName], suffix: suffix, ext: ext)
        return SaveLocation.fileURL(for: .recordings, fileName: fileName)
    }
}
