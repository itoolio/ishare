import CoreGraphics
import Foundation

public enum WebPageWidth: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case desktop
    case tablet
    case mobile

    public var id: Self { self }

    public var points: CGFloat {
        switch self {
        case .desktop: 1440
        case .tablet: 834
        case .mobile: 390
        }
    }
}

public enum WebPageCapturePlan {
    public static let maximumHeight: CGFloat = 30000
    public static let chunkHeight: CGFloat = 4000

    public static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host(), host.contains(".") || host == "localhost"
        else { return nil }
        return url
    }

    public static func cappedHeight(_ height: CGFloat) -> CGFloat {
        min(max(1, height.rounded(.up)), maximumHeight)
    }

    public static func chunks(height: CGFloat, chunkHeight: CGFloat = chunkHeight) -> [CGRect] {
        let total = cappedHeight(height)
        var rects: [CGRect] = []
        var origin: CGFloat = 0
        while origin < total {
            let height = min(chunkHeight, total - origin)
            rects.append(CGRect(x: 0, y: origin, width: 0, height: height))
            origin += height
        }
        return rects
    }

    public static func scrollStops(height: CGFloat, viewport: CGFloat) -> [CGFloat] {
        guard viewport > 0 else { return [0] }
        let total = cappedHeight(height)
        return Array(stride(from: 0, to: total, by: viewport)) + [0]
    }
}
