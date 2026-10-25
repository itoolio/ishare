import Defaults
import Foundation
import ishareCore

@MainActor
enum LinkRewriting {
    static func rewrite(_ outcome: UploadOutcome, for target: UploadTarget) -> UploadOutcome {
        guard case let .custom(uploader) = target, outcome.isShareable, !outcome.url.isFileURL else { return outcome }
        rememberLastLink(outcome.url, for: uploader.id)
        return rewrite(outcome, with: uploader.linkRewrite)
    }

    nonisolated static func rewrite(_ outcome: UploadOutcome, with rule: LinkRewrite?) -> UploadOutcome {
        guard let rule, !rule.isEmpty, let url = rule.apply(to: outcome.url) else { return outcome }
        var rewritten = outcome
        rewritten.url = url
        rewritten.deletionURL = rule.applyToDeletionURL(outcome.deletionURL)
        return rewritten
    }

    static func rememberLastLink(_ url: URL, for id: UUID) {
        Defaults[.lastUploadLinks][id.uuidString] = url.absoluteString
    }

    static func lastLink(for id: UUID) -> URL? {
        Defaults[.lastUploadLinks][id.uuidString].flatMap(URL.init(string:))
    }

    static func forget(_ id: UUID) {
        Defaults[.lastUploadLinks][id.uuidString] = nil
    }
}
