import AppKit
import Defaults

enum SoundChoice: Hashable, Codable, Sendable, Defaults.Serializable {
    case none
    case beep
    case system(String)

    var title: String {
        switch self {
        case .none: "None".localized()
        case .beep: "System Beep".localized()
        case let .system(name): name
        }
    }
}

enum SoundEvent: CaseIterable, Sendable {
    case capture
    case uploadComplete

    var key: Defaults.Key<SoundChoice> {
        switch self {
        case .capture: .captureSound
        case .uploadComplete: .uploadCompleteSound
        }
    }
}

@MainActor
enum SoundPlayer {
    nonisolated static let systemSoundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    nonisolated static let soundExtensions: Set<String> = ["aiff", "aif", "caf", "wav", "mp3", "m4a"]

    private static var current: NSSound?

    static func play(_ event: SoundEvent) {
        play(Defaults[event.key])
    }

    static func play(_ choice: SoundChoice) {
        switch choice {
        case .none:
            return
        case .beep:
            NSSound.beep()
        case let .system(name):
            guard let sound = sound(named: name) else {
                NSSound.beep()
                return
            }
            current?.stop()
            current = sound
            sound.play()
        }
    }

    private static func sound(named name: String) -> NSSound? {
        if let sound = NSSound(named: NSSound.Name(name)) {
            return sound
        }
        let match = (try? FileManager.default.contentsOfDirectory(at: systemSoundsDirectory, includingPropertiesForKeys: nil))?
            .first { $0.deletingPathExtension().lastPathComponent == name }
        return match.flatMap { NSSound(contentsOf: $0, byReference: true) }
    }

    nonisolated static func soundNames(in directory: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let names =
            files
            .filter { soundExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static var choices: [SoundChoice] {
        [.none, .beep] + soundNames(in: systemSoundsDirectory).map(SoundChoice.system)
    }
}
