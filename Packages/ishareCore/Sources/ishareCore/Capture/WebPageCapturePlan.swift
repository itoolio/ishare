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

public enum WebPageFormat: String, CaseIterable, Codable, Hashable, Sendable {
    case image
    case pdf
}

public struct WebPageCaptureRequest: Equatable, Hashable, Sendable {
    public var address: String
    public var width: CGFloat
    public var format: WebPageFormat
    public var dismissesCookieBanners: Bool

    public init(address: String, width: CGFloat = WebPageWidth.desktop.points, format: WebPageFormat = .image, dismissesCookieBanners: Bool = true) {
        self.address = address
        self.width = width
        self.format = format
        self.dismissesCookieBanners = dismissesCookieBanners
    }
}

public enum WebPageCapturePlan {
    public static let widthRange: ClosedRange<CGFloat> = 320...3840

    public static func width(from parameter: String?) -> CGFloat? {
        guard let parameter = parameter?.trimmingCharacters(in: .whitespaces).lowercased(), !parameter.isEmpty else { return WebPageWidth.desktop.points }
        if let preset = WebPageWidth(rawValue: parameter) { return preset.points }
        guard let value = Double(parameter.replacingOccurrences(of: "px", with: "").replacingOccurrences(of: "pt", with: "")), value.isFinite else { return nil }
        return min(max(CGFloat(value).rounded(), widthRange.lowerBound), widthRange.upperBound)
    }

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
