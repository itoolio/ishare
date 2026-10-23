import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

enum OnDeviceModelError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Intelligence is not available on this Mac".localized()
    }
}

enum OnDeviceModel {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return SystemLanguageModel.default.availability == .available
            }
        #endif
        return false
    }

    static func respond(to prompt: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), isAvailable {
                let session = LanguageModelSession(instructions: instructions)
                return try await session.respond(to: prompt).content
            }
        #endif
        throw OnDeviceModelError.unavailable
    }

    static func stream(_ prompt: String, instructions: String, onPartial: @escaping @MainActor (String) -> Void) async throws {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), isAvailable {
                let session = LanguageModelSession(instructions: instructions)
                for try await snapshot in session.streamResponse(to: prompt) {
                    let partial = snapshot.content
                    await onPartial(partial)
                }
                return
            }
        #endif
        throw OnDeviceModelError.unavailable
    }
}
