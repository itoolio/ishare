import Foundation

public enum EditorImageKind: String, CaseIterable, Codable, Sendable {
    case screenshot
    case photo
    case webPage

    public static func classify(fileName: String?, hasCameraMetadata: Bool) -> EditorImageKind {
        if hasCameraMetadata { return .photo }
        guard let fileName else { return .screenshot }
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        if let last = base.split(separator: "-").last, isHost(String(last)) { return .webPage }
        if ["img_", "dsc", "photo", "pxl_"].contains(where: base.hasPrefix) { return .photo }
        return .screenshot
    }

    static func isHost(_ text: String) -> Bool {
        let labels = text.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        return labels.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    }
}
