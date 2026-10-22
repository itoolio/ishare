import Foundation
import Testing
@testable import ishare

@Suite(.serialized)
struct NetworkSuite {}

@MainActor
final class UploadEnvironmentSpy {
    var history: [HistoryItem] = []
    var notifications: [String] = []
    var enqueued: [(URL, UploadDestination)] = []
    var delivered: [URL] = []

    var environment: UploadEnvironment {
        UploadEnvironment(
            recordHistory: { [unowned self] in history.append($0) },
            notify: { [unowned self] in notifications.append($0) },
            enqueue: { [unowned self] url, target, _, _ in enqueued.append((url, target.destination)) },
            deliver: { [unowned self] in delivered.append($0) },
            showsProgress: false
        )
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
    static let backend = InMemorySecretBackend()

    static func install() {
        if !(S3SecretStore.backend is InMemorySecretBackend) {
            S3SecretStore.backend = backend
        }
    }
}
