import Foundation

@MainActor
enum CaptureSourceRegistry {
    static let limit = 50
    private static var sources: [(path: String, source: CaptureSource)] = []

    static func remember(_ source: CaptureSource, for url: URL) {
        guard source.appName != nil || source.windowTitle != nil else { return }
        sources.removeAll { $0.path == url.path }
        sources.append((url.path, source))
        if sources.count > limit { sources.removeFirst(sources.count - limit) }
    }

    static func source(for url: URL) -> CaptureSource? {
        sources.last { $0.path == url.path }?.source
    }
}
