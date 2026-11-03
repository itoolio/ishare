import CoreGraphics
import Foundation

public struct ExportPreset: Codable, Hashable, Identifiable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        case png
        case jpg
        case webp
    }

    public enum Destination: String, Codable, CaseIterable, Sendable {
        case clipboard
        case file
    }

    public var id: UUID
    public var name: String
    public var format: Format
    public var maxDimension: Int?
    public var downscalesRetina: Bool
    public var quality: Double
    public var destination: Destination

    public init(
        id: UUID = UUID(), name: String, format: Format, maxDimension: Int? = nil, downscalesRetina: Bool = false, quality: Double = 0.85,
        destination: Destination = .clipboard
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.maxDimension = maxDimension
        self.downscalesRetina = downscalesRetina
        self.quality = quality
        self.destination = destination
    }

    public static let builtIn: [ExportPreset] = [
        ExportPreset(id: UUID(uuidString: "5A1A0000-0000-0000-0000-000000000001")!, name: "Slack", format: .png, maxDimension: 2400),
        ExportPreset(id: UUID(uuidString: "5A1A0000-0000-0000-0000-000000000002")!, name: "Docs", format: .png, downscalesRetina: true),
        ExportPreset(id: UUID(uuidString: "5A1A0000-0000-0000-0000-000000000003")!, name: "Retina PNG", format: .png, destination: .file),
        ExportPreset(
            id: UUID(uuidString: "5A1A0000-0000-0000-0000-000000000004")!, name: "Small JPEG", format: .jpg, maxDimension: 1280, downscalesRetina: true,
            quality: 0.7, destination: .file),
    ]

    public func outputSize(for size: CGSize, pointScale: CGFloat) -> CGSize {
        var scale: CGFloat = 1
        if downscalesRetina, pointScale > 1 {
            scale = 1 / pointScale
        }
        var output = CGSize(width: size.width * scale, height: size.height * scale)
        if let maxDimension, max(output.width, output.height) > CGFloat(maxDimension) {
            let fit = CGFloat(maxDimension) / max(output.width, output.height)
            output = CGSize(width: output.width * fit, height: output.height * fit)
        }
        return CGSize(width: max(1, output.width.rounded()), height: max(1, output.height.rounded()))
    }
}
