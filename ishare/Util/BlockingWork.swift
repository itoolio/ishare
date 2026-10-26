import Foundation

enum BlockingWork {
    private static let queue = DispatchQueue(label: "dev.adrian.ishare.blocking-work", qos: .userInitiated, attributes: .concurrent)

    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    static func runThrowing<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
