import Defaults
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageOptimizationFormat: String, Codable, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case lossless
    case avif
    case webp

    var id: Self { self }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "lossless", "png", "original": self = .lossless
        case "avif": self = .avif
        case "webp": self = .webp
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid image format: \(rawValue)")
        }
    }

    var titleKey: String {
        switch self {
        case .lossless: "Keep the format (lossless PNG recompression)"
        case .avif: "Convert to AVIF"
        case .webp: "Convert to WebP"
        }
    }
}

struct ImageOptimizationOverride: Codable, Hashable, Sendable {
    var enabled: Bool?
    var format: ImageOptimizationFormat?

    init(enabled: Bool? = nil, format: ImageOptimizationFormat? = nil) {
        self.enabled = enabled
        self.format = format
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        enabled = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "enabled"))
        format = try container.decodeDynamicIfPresent(ImageOptimizationFormat.self, forKey: .key(named: "format"))
    }

    var isEmpty: Bool { enabled == nil && format == nil }
}

struct ImageOptimizationSettings: Equatable, Sendable {
    var enabled: Bool
    var format: ImageOptimizationFormat
    var quality: Double

    static func resolved(global: ImageOptimizationSettings, override: ImageOptimizationOverride?) -> ImageOptimizationSettings {
        var settings = global
        if let enabled = override?.enabled {
            settings.enabled = enabled
        }
        if let format = override?.format {
            settings.format = format
        }
        return settings
    }
}

struct ImageOptimizationResult: Equatable, Sendable {
    let url: URL
    let originalBytes: Int
    let optimizedBytes: Int

    var savedBytes: Int { max(0, originalBytes - optimizedBytes) }

    var savedFraction: Double {
        originalBytes > 0 ? Double(savedBytes) / Double(originalBytes) : 0
    }
}

enum ImageEncoders {
    static let png = UTType.png.identifier
    static let avif = "public.avif"
    static let heic = UTType.heic.identifier
    static let webp = "org.webmproject.webp"

    static var destinationTypes: Set<String> {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }

    static func canEncode(_ type: String) -> Bool {
        destinationTypes.contains(type)
    }

    static func conversionTarget(for format: ImageOptimizationFormat, available: Set<String> = destinationTypes) -> (type: String, fileExtension: String)? {
        switch format {
        case .lossless:
            nil
        case .avif:
            available.contains(avif) ? (avif, "avif") : available.contains(heic) ? (heic, "heic") : nil
        case .webp:
            available.contains(webp) ? (webp, "webp") : nil
        }
    }
}

enum PNGFilters {
    static let none = 0x08
    static let sub = 0x10
    static let up = 0x20
    static let average = 0x40
    static let paeth = 0x80
    static let all = none | sub | up | average | paeth
}

enum ImageOptimizer {
    static let convertibleExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif"]

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func optimize(_ fileURL: URL, settings: ImageOptimizationSettings, in directory: URL) -> ImageOptimizationResult? {
        guard settings.enabled else { return nil }
        let ext = fileURL.pathExtension.lowercased()
        guard convertibleExtensions.contains(ext),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetCount(source) == 1
        else { return nil }
        let original = fileSize(fileURL)
        var candidates: [URL] = []
        if let target = ImageEncoders.conversionTarget(for: settings.format),
           let converted = convert(source, to: target, quality: settings.quality, name: fileURL.deletingPathExtension().lastPathComponent, in: directory)
        {
            candidates.append(converted)
        }
        if ext == "png", let recompressed = recompressPNG(source, name: fileURL.lastPathComponent, in: directory) {
            candidates.append(recompressed)
        }
        let best = candidates.min { fileSize($0) < fileSize($1) }
        for candidate in candidates where candidate != best {
            try? FileManager.default.removeItem(at: candidate)
        }
        guard let best, fileSize(best) > 0, fileSize(best) < original else {
            best.map { try? FileManager.default.removeItem(at: $0) }
            return nil
        }
        return ImageOptimizationResult(url: best, originalBytes: original, optimizedBytes: fileSize(best))
    }

    static func preservedProperties(of source: CGImageSource) -> [CFString: Any] {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var preserved: [CFString: Any] = [:]
        if let orientation = properties[kCGImagePropertyOrientation] {
            preserved[kCGImagePropertyOrientation] = orientation
        }
        return preserved
    }

    static func recompressPNG(_ source: CGImageSource, name: String, in directory: URL) -> URL? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = directory.appending(path: name, directoryHint: .notDirectory)
        let flattened = isOpaque(image) ? removingAlpha(image) ?? image : image
        var properties = preservedProperties(of: source)
        properties[kCGImagePropertyPNGDictionary] = [
            kCGImagePropertyPNGCompressionFilter: PNGFilters.all,
            kCGImagePropertyPNGInterlaceType: 0,
        ]
        return write(flattened, type: ImageEncoders.png, to: output, properties: properties) ? output : nil
    }

    static func convert(_ source: CGImageSource, to target: (type: String, fileExtension: String), quality: Double, name: String, in directory: URL) -> URL? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = directory.appending(path: "\(name).\(target.fileExtension)", directoryHint: .notDirectory)
        var properties = preservedProperties(of: source)
        properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, quality))
        return write(image, type: target.type, to: output, properties: properties) ? output : nil
    }

    static func write(_ image: CGImage, type: String, to url: URL, properties: [CFString: Any]) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            break
        }
        let width = image.width
        let height = image.height
        guard width * height <= 40_000_000, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 }
    }

    static func removingAlpha(_ image: CGImage) -> CGImage? {
        guard let space = image.colorSpace, space.model == .rgb || space.model == .monochrome else { return nil }
        let bitsPerComponent = image.bitsPerComponent == 16 ? 16 : 8
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | (bitsPerComponent == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        guard space.model == .rgb, let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0, space: space,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

enum ByteSavings {
    static func description(saved: Int, original: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        let percent = original > 0 ? Int((Double(saved) / Double(original) * 100).rounded()) : 0
        return String(format: "Saved %@ (%d%%)".localized(), formatter.string(fromByteCount: Int64(saved)), percent)
    }
}
