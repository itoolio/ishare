import Foundation

@MainActor
protocol Uploader: Sendable {
    func upload(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> UploadOutcome
    func delete(_ item: HistoryItem) async throws
}
