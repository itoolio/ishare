import AppKit
import BezelNotification
import Defaults
import ishareCore

@MainActor
enum UploadDestinationSwitcher {
    static var destinations: [UploadDestination] {
        [.builtIn(.IMGUR)] + CustomUploader.allCases.map { .custom($0.id) }
    }

    static var current: UploadDestination {
        Defaults[.uploadDestination]
    }

    static func title(for destination: UploadDestination) -> String {
        if case let .custom(id) = destination, let uploader = CustomUploader.allCases.first(where: { $0.id == id }) {
            return uploader.name
        }
        return destination == .localNetwork ? "Local Network".localized() : "Imgur"
    }

    static func identifier(for destination: UploadDestination) -> String {
        switch destination {
        case let .builtIn(type): type.rawValue.lowercased()
        case let .custom(id): id?.uuidString ?? "none"
        case .localNetwork: "localnetwork"
        }
    }

    static func symbol(for destination: UploadDestination) -> String {
        guard case let .custom(id) = destination, let uploader = CustomUploader.allCases.first(where: { $0.id == id }) else {
            return "photo"
        }
        return uploader.kind.symbolName
    }

    static func select(_ destination: UploadDestination) {
        guard destination != .localNetwork else { return }
        Defaults[.uploadDestination] = destination
        switch destination {
        case .builtIn:
            Defaults[.activeCustomUploader] = nil
            Defaults[.uploadType] = .IMGUR
        case let .custom(id):
            Defaults[.activeCustomUploader] = id
            Defaults[.uploadType] = .CUSTOM
        case .localNetwork:
            break
        }
        BezelNotification.show(messageText: String(format: "Selected %@".localized(), title(for: destination)), icon: ToastIcon)
    }

    static func next(after destination: UploadDestination, in destinations: [UploadDestination]) -> UploadDestination? {
        guard !destinations.isEmpty else { return nil }
        let current = destinations.firstIndex(of: destination) ?? -1
        return destinations[(current + 1) % destinations.count]
    }
}
