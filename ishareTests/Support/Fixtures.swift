import Foundation

private final class FixturesBundleToken {}

enum Fixtures {
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let bundledRoot = Bundle(for: FixturesBundleToken.self).resourceURL?.appending(path: "Fixtures", directoryHint: .isDirectory)

    static let repositoryRoot: URL = {
        if isSandboxed, let bundledRoot, FileManager.default.fileExists(atPath: bundledRoot.path) {
            return bundledRoot
        }
        return sourceRoot
    }()

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appending(path: relativePath)
    }

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }

    static func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url
    }
}
