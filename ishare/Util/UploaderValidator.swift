import Foundation
import ishareCore

extension UploaderIssue {
    @MainActor var localizedMessage: String {
        argument.map { String(format: messageKey.localized(), $0.localized()) } ?? messageKey.localized()
    }
}
