import Foundation
import Testing
@testable import ishare

@Suite(.serialized)
struct NetworkSuite {}

@MainActor
final class UploadEnvironmentSpy: UploadEnvironment {
    var history: [HistoryItem] = []
    var notifications: [String] = []
    var enqueued: [(URL, UploadDestination)] = []
    var delivered: [URL] = []
    var linkChoice: LinkChoiceResolution = .use(.none)
    let showsProgress = false

    func recordHistory(_ item: HistoryItem) {
        history.append(item)
    }

    func notify(_ message: String) {
        notifications.append(message)
    }

    func enqueue(_ fileURL: URL, target: UploadTarget, localPath _: String?, error _: any Error) throws {
        enqueued.append((fileURL, target.destination))
    }

    func deliver(_ url: URL) {
        delivered.append(url)
    }

    func resolveLinkChoice(for _: UploadTarget) async -> LinkChoiceResolution {
        linkChoice
    }
}

@MainActor
struct FailingQueueUploadEnvironment: UploadEnvironment {
    struct QueueUnavailable: Error {}

    let wrapped: UploadEnvironmentSpy
    var showsProgress: Bool { wrapped.showsProgress }

    func recordHistory(_ item: HistoryItem) {
        wrapped.recordHistory(item)
    }

    func notify(_ message: String) {
        wrapped.notify(message)
    }

    func enqueue(_: URL, target _: UploadTarget, localPath _: String?, error _: any Error) throws {
        throw QueueUnavailable()
    }

    func deliver(_ url: URL) {
        wrapped.deliver(url)
    }

    func resolveLinkChoice(for target: UploadTarget) async -> LinkChoiceResolution {
        await wrapped.resolveLinkChoice(for: target)
    }
}

enum TestUploaders {
    static func http(name: String, host: String, responseURL: String = "{{url}}") -> CustomUploader {
        CustomUploader(
            name: name, requestURL: "https://\(host)/upload", headers: nil, formData: nil, fileFormName: "file",
            responseURL: responseURL
        )
    }

    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])
}

@MainActor
enum TestSecrets {
    private static let fallback = InMemorySecretBackend()

    static var backend: InMemorySecretBackend {
        install()
        return S3SecretStore.backend as? InMemorySecretBackend ?? fallback
    }

    static func install() {
        if !(S3SecretStore.backend is InMemorySecretBackend) {
            S3SecretStore.backend = fallback
        }
    }
}
