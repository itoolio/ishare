import Foundation

public enum MicrophoneSelection: Hashable, Sendable {
    case systemDefault
    case configured(String)
    case missing(String)

    public static func resolve(configuredID: String?, connectedIDs: [String]) -> MicrophoneSelection {
        guard let configuredID, !configuredID.isEmpty else { return .systemDefault }
        return connectedIDs.contains(configuredID) ? .configured(configuredID) : .missing(configuredID)
    }

    public var deviceID: String? {
        guard case let .configured(id) = self else { return nil }
        return id
    }

    public var fellBackToDefault: Bool {
        guard case .missing = self else { return false }
        return true
    }
}
