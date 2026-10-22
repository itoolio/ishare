import AppKit
import Defaults

enum ForceUploadModifier: String, CaseIterable, Identifiable, Defaults.Serializable {
    case shift = "⇧"
    case control = "⌃"
    case option = "⌥"
    case command = "⌘"

    var id: Self { self }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .control: .control
        case .option: .option
        case .command: .command
        }
    }
}
