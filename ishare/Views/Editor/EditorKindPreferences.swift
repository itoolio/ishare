import Defaults
import Foundation
import ImageIO
import ishareCore

struct EditorKindPreference: Codable, Hashable, Defaults.Serializable {
    var tool: String?
    var color: RGBAColor?
    var zoom: Double?
}

@MainActor
enum EditorKindPreferences {
    static func kind(of fileURL: URL?) -> EditorImageKind {
        EditorImageKind.classify(fileName: fileURL?.lastPathComponent, hasCameraMetadata: fileURL.map(hasCameraMetadata) ?? false)
    }

    static func hasCameraMetadata(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return tiff?[kCGImagePropertyTIFFMake] != nil || (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifFNumber] != nil
    }

    static func preference(for kind: EditorImageKind) -> EditorKindPreference? {
        Defaults[.editorKindPreferences][kind.rawValue]
    }

    static func update(_ kind: EditorImageKind, _ change: (inout EditorKindPreference) -> Void) {
        var all = Defaults[.editorKindPreferences]
        var preference = all[kind.rawValue] ?? EditorKindPreference()
        change(&preference)
        all[kind.rawValue] = preference
        Defaults[.editorKindPreferences] = all
    }
}
