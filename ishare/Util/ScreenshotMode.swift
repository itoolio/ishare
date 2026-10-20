import Foundation

@MainActor
enum ScreenshotMode {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-ishareScreenshotMode")
    }

    static func prepareIfNeeded() {}
}
