import Defaults
import Foundation

enum MenuBarIcon: Codable, CaseIterable, Identifiable, Defaults.Serializable {
    case DEFAULT
    case APPICON
    case SYSTEM
    var id: Self { self }
}
