import Foundation
import ishareCore

extension RemotePathError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            "The remote path template produced an empty path".localized()
        case let .invalidPublicURL(value):
            String(format: "The public URL template produced an invalid URL: %@".localized(), value)
        }
    }
}
