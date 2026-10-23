import Foundation

public enum ImageOptimizationFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case lossless
    case avif
    case webp

    public var id: Self { self }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "lossless", "png", "original": self = .lossless
        case "avif": self = .avif
        case "webp": self = .webp
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid image format: \(rawValue)")
        }
    }

    public var titleKey: String {
        switch self {
        case .lossless: "Keep the format (lossless PNG recompression)"
        case .avif: "Convert to AVIF"
        case .webp: "Convert to WebP"
        }
    }
}

public struct ImageOptimizationOverride: Codable, Hashable, Sendable {
    public var enabled: Bool?
    public var format: ImageOptimizationFormat?

    public init(enabled: Bool? = nil, format: ImageOptimizationFormat? = nil) {
        self.enabled = enabled
        self.format = format
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        enabled = try container.decodeDynamicIfPresent(Bool.self, forKey: .key(named: "enabled"))
        format = try container.decodeDynamicIfPresent(ImageOptimizationFormat.self, forKey: .key(named: "format"))
    }

    public var isEmpty: Bool { enabled == nil && format == nil }
}

public struct ImageOptimizationSettings: Equatable, Sendable {
    public var enabled: Bool
    public var format: ImageOptimizationFormat
    public var quality: Double

    public static func resolved(global: ImageOptimizationSettings, override: ImageOptimizationOverride?) -> ImageOptimizationSettings {
        var settings = global
        if let enabled = override?.enabled {
            settings.enabled = enabled
        }
        if let format = override?.format {
            settings.format = format
        }
        return settings
    }

    public init(enabled: Bool, format: ImageOptimizationFormat, quality: Double) {
        self.enabled = enabled
        self.format = format
        self.quality = quality
    }
}
