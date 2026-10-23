import AppKit
import ObjectiveC
import SwiftUI
@testable import ishare

@MainActor
enum SnapshotRenderer {
    static let scale: CGFloat = 2

    static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, settle: TimeInterval = 0.2) -> CGImage? {
        let content = ZStack {
            Color(nsColor: .windowBackgroundColor)
            view
        }
        .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        hosting.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        return rep.cgImage
    }

    static func crop(_ image: CGImage, toPoints rect: CGRect) -> CGImage? {
        image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
    }
}

struct PixelBuffer: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    func differentPixels(from other: PixelBuffer, channelTolerance: Int) -> Int? {
        guard width == other.width, height == other.height else { return nil }
        var count = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0 ..< 4 where abs(Int(bytes[pixel + channel]) - Int(other.bytes[pixel + channel])) > channelTolerance {
                count += 1
                break
            }
        }
        return count
    }

    func variance(in rect: CGRect) -> Double {
        let minX = max(0, Int(rect.minX)), maxX = min(width, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(height, Int(rect.maxY))
        var values: [Double] = []
        for y in minY ..< maxY {
            for x in stride(from: minX, to: maxX, by: 2) {
                let index = (y * width + x) * 4
                values.append(Double(bytes[index]) * 0.299 + Double(bytes[index + 1]) * 0.587 + Double(bytes[index + 2]) * 0.114)
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
}

final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var language: Bundle?

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if Thread.isMainThread, let language = Self.language {
            return language.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
enum LanguageOverride {
    private static var installed = false

    static func bundle(for language: String) -> Bundle? {
        if language == "en" {
            return Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main.path(forResource: "Base", ofType: "lproj").flatMap(Bundle.init(path:))
        }
        return Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    static func with<T>(_ language: String, _ body: () throws -> T) rethrows -> T {
        if !installed {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
            installed = true
        }
        LanguageOverrideBundle.language = bundle(for: language)
        defer { LanguageOverrideBundle.language = nil }
        return try body()
    }
}

enum SnapshotStore {
    static let tolerance = 24
    static let maximumDifferentFraction = 0.005

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["ISHARE_RECORD_SNAPSHOTS"] == "1"
    }

    static var osFolder: String {
        "macOS\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
    }

    static var directory: URL {
        Fixtures.url("ishareTests/Snapshots").appending(path: osFolder, directoryHint: .isDirectory)
    }

    static var isAvailable: Bool {
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return false }
        return isRecording || FileManager.default.fileExists(atPath: directory.path)
    }

    static var failureDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "ishare-snapshot-failures", directoryHint: .isDirectory)
    }

    enum Outcome: Equatable {
        case matched
        case recorded
        case missingReference(String)
        case sizeChanged(String)
        case different(Int, String)
    }

    static func verify(_ image: CGImage, named name: String) throws -> Outcome {
        let reference = directory.appending(path: "\(name).png")
        if isRecording {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ImageEncoder.write(image, as: .PNG, to: reference)
            return .recorded
        }
        let actualPath = try writeFailure(image, named: name)
        guard let source = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let expected = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return .missingReference(actualPath) }
        guard let actualPixels = PixelBuffer(image), let expectedPixels = PixelBuffer(expected),
              let different = actualPixels.differentPixels(from: expectedPixels, channelTolerance: tolerance)
        else { return .sizeChanged(actualPath) }
        if Double(different) <= Double(actualPixels.width * actualPixels.height) * maximumDifferentFraction {
            try? FileManager.default.removeItem(atPath: actualPath)
            return .matched
        }
        return .different(different, actualPath)
    }

    private static func writeFailure(_ image: CGImage, named name: String) throws -> String {
        try FileManager.default.createDirectory(at: failureDirectory, withIntermediateDirectories: true)
        let url = failureDirectory.appending(path: "\(name).png")
        try ImageEncoder.write(image, as: .PNG, to: url)
        return url.path
    }
}
