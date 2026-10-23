import Defaults
import Foundation
import ishareCore

enum LinkPasswordStore {
    static let service = "dev.adrian.ishare.link-password"
    private static let backendSlot = SecretBackendSlot(
        RuntimeEnvironment.isRunningTests
            ? InMemorySecretBackend()
            : KeychainSecretBackend(service: service, label: "ishare default link password")
    )

    static var backend: any SecretBackend {
        get { backendSlot.current }
        set { backendSlot.current = newValue }
    }

    static func password(for id: UUID) -> String? {
        backend.read(account: id.uuidString)
    }

    static func setPassword(_ password: String?, for id: UUID) {
        guard let password, !password.isEmpty else {
            backend.delete(account: id.uuidString)
            return
        }
        do {
            try backend.write(password, account: id.uuidString)
        } catch {
            Log.upload.error("Storing the default link password failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
enum LinkOptionsResolver {
    static func preferences(for id: UUID) -> LinkOptionPreferences {
        Defaults[.linkOptionPreferences][id.uuidString] ?? .standard
    }

    static func setPreferences(_ preferences: LinkOptionPreferences?, for id: UUID) {
        Defaults[.linkOptionPreferences][id.uuidString] = preferences == .standard ? nil : preferences
    }

    static func storedChoice(for uploader: CustomUploader) -> LinkChoice {
        guard let spec = uploader.linkOptions, !spec.isEmpty else { return .none }
        return preferences(for: uploader.id).choice(password: LinkPasswordStore.password(for: uploader.id), spec: spec)
    }

    static func resolve(for target: UploadTarget, prompt: (CustomUploader, LinkChoice) async -> LinkChoice? = LinkOptionsPrompt.ask) async -> LinkChoiceResolution {
        guard case let .custom(uploader) = target, let spec = uploader.linkOptions, !spec.isEmpty else { return .use(.none) }
        let stored = storedChoice(for: uploader)
        guard preferences(for: uploader.id).asksEveryTime else { return .use(stored) }
        guard let chosen = await prompt(uploader, stored) else { return .cancel }
        return .use(chosen)
    }

    static func forget(_ id: UUID) {
        setPreferences(nil, for: id)
        LinkPasswordStore.setPassword(nil, for: id)
    }
}

extension LinkOptionPreferences: @retroactive Defaults.Serializable {}
