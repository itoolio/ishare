import Foundation

public enum UploadFileName {
    public static func lowercasingExtension(of url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return url.lastPathComponent }
        return url.deletingPathExtension().lastPathComponent + "." + ext.lowercased()
    }
}
