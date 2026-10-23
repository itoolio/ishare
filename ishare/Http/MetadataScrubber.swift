import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MetadataScrubber {
    static let scrubbableExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "avif", "webp"]

    static var sensitiveDictionaries: [CFString] {
        [
        kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyMakerAppleDictionary,
        kCGImagePropertyMakerCanonDictionary, kCGImagePropertyMakerNikonDictionary, kCGImagePropertyExifAuxDictionary,
        ]
    }

    static var identifyingTIFFKeys: [CFString] {
        [
        kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFSoftware,
        kCGImagePropertyTIFFHostComputer, kCGImagePropertyTIFFCopyright,
        ]
    }

    static var identifyingExifKeys: [CFString] {
        [
        kCGImagePropertyExifMakerNote, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifCameraOwnerName,
        kCGImagePropertyExifLensMake, kCGImagePropertyExifLensModel, kCGImagePropertyExifLensSerialNumber,
        kCGImagePropertyExifUserComment, kCGImagePropertyExifImageUniqueID, kCGImagePropertyExifDateTimeOriginal,
        ]
    }

    static func containsSensitiveMetadata(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        if sensitiveDictionaries.contains(where: { properties[$0] != nil }) { return true }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if identifyingTIFFKeys.contains(where: { tiff[$0] != nil }) { return true }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if identifyingExifKeys.contains(where: { exif[$0] != nil }) { return true }
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else { return false }
        return tags.contains { tag in
            let namespace = CGImageMetadataTagCopyNamespace(tag) as String? ?? ""
            return namespace != (kCGImageMetadataNamespaceTIFF as String) && namespace != (kCGImageMetadataNamespaceExif as String)
        }
    }

    static func orientation(of source: CGImageSource) -> Int? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue
    }

    static func scrubbed(_ fileURL: URL, in directory: URL) -> URL? {
        let ext = fileURL.pathExtension.lowercased()
        guard scrubbableExtensions.contains(ext), containsSensitiveMetadata(fileURL),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { return nil }
        let output = directory.appending(path: UploadFileName.lowercasingExtension(of: fileURL), directoryHint: .notDirectory)
        if copyWithoutMetadata(source, type: type, to: output), !containsSensitiveMetadata(output) {
            return output
        }
        try? FileManager.default.removeItem(at: output)
        return reencodeWithoutMetadata(source, type: type, to: output) ? output : nil
    }

    static func minimalMetadata(orientation: Int?) -> CGMutableImageMetadata {
        let metadata = CGImageMetadataCreateMutable()
        if let orientation, orientation != 1 {
            CGImageMetadataSetValueMatchingImageProperty(
                metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, NSNumber(value: orientation)
            )
        }
        return metadata
    }

    static func copyWithoutMetadata(_ source: CGImageSource, type: CFString, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
        var options: [CFString: Any] = [
            kCGImageDestinationMetadata: minimalMetadata(orientation: orientation(of: source)),
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        if let orientation = orientation(of: source) {
            options[kCGImageDestinationOrientation] = orientation
        }
        var error: Unmanaged<CFError>?
        let copied = CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error)
        error?.release()
        return copied
    }

    static func reencodeWithoutMetadata(_ source: CGImageSource, type: CFString, to url: URL) -> Bool {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)
        else { return false }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
        if let orientation = orientation(of: source) {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
