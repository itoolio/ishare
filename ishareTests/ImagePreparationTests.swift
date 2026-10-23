import CoreGraphics
import Defaults
import Foundation
import ImageIO
import ishareCore
import Testing
import UniformTypeIdentifiers
@testable import ishare

enum SyntheticImages {
    static func image(width: Int = 320, height: Int = 200, alpha: Bool = true, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: info)!
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for row in stride(from: 0, to: height, by: 20) {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: Double(row) / Double(height), alpha: 1))
            context.fill(CGRect(x: 10, y: row + 4, width: width - 20, height: 10))
        }
        return context.makeImage()!
    }

    static func noisy(width: Int = 256, height: Int = 256) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var generator = SystemRandomNumberGenerator()
        for x in stride(from: 0, to: width, by: 4) {
            for y in stride(from: 0, to: height, by: 4) {
                let shade = Double(x + y) / Double(width + height)
                context.setFillColor(CGColor(red: shade, green: Double.random(in: 0.3 ... 0.4, using: &generator), blue: 1 - shade, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return context.makeImage()!
    }

    static func write(_ image: CGImage, type: UTType, name: String, properties: [CFString: Any] = [:]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static func unfilteredPNG(name: String = "shot.png") throws -> URL {
        try write(
            image(), type: .png, name: name,
            properties: [
                kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: PNGFilters.none, kCGImagePropertyPNGDescription: String(repeating: "ishare ", count: 400)]
            ])
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func photoWithLocation() throws -> URL {
        try write(
            image(alpha: false, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!), type: .jpeg, name: "IMG_0001.JPG",
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 48.2082, kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 16.3738, kCGImagePropertyGPSLongitudeRef: "E",
                ],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 17 Pro", kCGImagePropertyTIFFOrientation: 6],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifLensModel: "iPhone 17 Pro back camera", kCGImagePropertyExifBodySerialNumber: "F2LXK0001",
                    kCGImagePropertyExifDateTimeOriginal: "2026:01:01 12:00:00",
                ],
                kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCByline: ["Jane Doe"], kCGImagePropertyIPTCCity: "Vienna"],
            ])
    }
}

struct ImageOptimizerTests {
    let settings = ImageOptimizationSettings(enabled: true, format: .lossless, quality: 0.85)

    func workingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func recompressesPNGsLosslesslyAndDropsAncillaryChunks() throws {
        let source = try SyntheticImages.unfilteredPNG()
        let result = try #require(ImageOptimizer.optimize(source, settings: settings, in: workingDirectory()))
        #expect(result.optimizedBytes < result.originalBytes)
        #expect(result.url.pathExtension == "png")
        #expect(result.savedFraction > 0)
        let png = SyntheticImages.properties(result.url)[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        #expect(png?[kCGImagePropertyPNGDescription] == nil)
        let original = try #require(CGImageSourceCreateWithURL(source as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let optimized = try #require(CGImageSourceCreateWithURL(result.url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(pixels(of: original) == pixels(of: optimized))
    }

    @Test func skipsFilesWhenTheResultIsNotSmaller() throws {
        let tiny = try SyntheticImages.write(SyntheticImages.image(width: 1, height: 1), type: .png, name: "dot.png")
        let directory = try workingDirectory()
        let first = ImageOptimizer.optimize(tiny, settings: settings, in: directory)
        if let first {
            #expect(ImageOptimizer.optimize(first.url, settings: settings, in: try workingDirectory()) == nil)
        }
        #expect(ImageOptimizer.optimize(tiny, settings: ImageOptimizationSettings(enabled: false, format: .lossless, quality: 1), in: directory) == nil)
        let gif = try SyntheticImages.write(SyntheticImages.image(), type: .gif, name: "a.gif")
        #expect(ImageOptimizer.optimize(gif, settings: settings, in: directory) == nil)
    }

    @Test func convertsToAVIFOrFallsBackToHEIC() throws {
        let source = try SyntheticImages.write(SyntheticImages.noisy(), type: .png, name: "photo.png")
        let avif = ImageOptimizationSettings(enabled: true, format: .avif, quality: 0.7)
        let result = try #require(ImageOptimizer.optimize(source, settings: avif, in: workingDirectory()))
        #expect(["avif", "heic"].contains(result.url.pathExtension))
        #expect(result.url.pathExtension == (ImageEncoders.canEncode(ImageEncoders.avif) ? "avif" : "heic"))
        #expect(result.optimizedBytes < result.originalBytes)
    }

    @Test func picksConversionTargetsFromTheAvailableEncoders() {
        #expect(ImageEncoders.conversionTarget(for: .avif, available: ["public.avif", "public.heic"])?.fileExtension == "avif")
        #expect(ImageEncoders.conversionTarget(for: .avif, available: ["public.heic"])?.fileExtension == "heic")
        #expect(ImageEncoders.conversionTarget(for: .avif, available: []) == nil)
        #expect(ImageEncoders.conversionTarget(for: .webp, available: ["public.heic"]) == nil)
        #expect(ImageEncoders.conversionTarget(for: .webp, available: ["org.webmproject.webp"])?.fileExtension == "webp")
        #expect(ImageEncoders.conversionTarget(for: .lossless) == nil)
    }

    @Test func appliesPerUploaderOverrides() throws {
        let global = ImageOptimizationSettings(enabled: true, format: .avif, quality: 0.8)
        #expect(ImageOptimizationSettings.resolved(global: global, override: nil) == global)
        let keepFormat = ImageOptimizationSettings.resolved(global: global, override: ImageOptimizationOverride(format: .lossless))
        #expect(keepFormat.format == .lossless)
        #expect(keepFormat.enabled)
        #expect(!ImageOptimizationSettings.resolved(global: global, override: ImageOptimizationOverride(enabled: false)).enabled)
        #expect(
            try CustomUploader.fromJSON(Data(#"{"name": "x", "requestURL": "https://x", "responseURL": "{{url}}", "imageOptimization": {"format": "png"}}"#.utf8))
                .imageOptimization?.format == .lossless)
    }

    @Test func describesTheSavings() {
        #expect(ByteSavings.description(saved: 51200, original: 204_800).contains("25%"))
        let item = HistoryItem(fileUrl: "https://x/a.png", originalSize: 2000, uploadedSize: 1500)
        #expect(item.savingsDescription?.contains("25%") == true)
        #expect(HistoryItem(fileUrl: "https://x/a.png").savingsDescription == nil)
    }

    func pixels(of image: CGImage) -> [UInt8] {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
}

struct MetadataScrubberTests {
    @Test func removesLocationCameraAndCreatorDetailsButKeepsOrientationAndColorProfile() throws {
        let photo = try SyntheticImages.photoWithLocation()
        let before = SyntheticImages.properties(photo)
        #expect(before[kCGImagePropertyGPSDictionary] != nil)
        #expect(MetadataScrubber.containsSensitiveMetadata(photo))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clean = try #require(MetadataScrubber.scrubbed(photo, in: directory))
        let after = SyntheticImages.properties(clean)
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        #expect(after[kCGImagePropertyIPTCDictionary] == nil)
        let tiff = after[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        let exif = after[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifLensModel] == nil)
        #expect(exif[kCGImagePropertyExifBodySerialNumber] == nil)
        #expect((after[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 6)
        #expect(after[kCGImagePropertyProfileName] as? String == before[kCGImagePropertyProfileName] as? String)
        #expect((after[kCGImagePropertyProfileName] as? String)?.contains("P3") == true)
        #expect(!MetadataScrubber.containsSensitiveMetadata(clean))
        #expect(clean.lastPathComponent == "IMG_0001.jpg")
    }

    @Test func leavesCleanImagesAlone() throws {
        let png = try SyntheticImages.write(SyntheticImages.image(), type: .png, name: "clean.png")
        #expect(!MetadataScrubber.containsSensitiveMetadata(png))
        #expect(MetadataScrubber.scrubbed(png, in: FileManager.default.temporaryDirectory) == nil)
    }

    @Test func stripsImportedPhotosByDefaultAndEverythingWhenAsked() {
        #expect(UploadPreparationPolicy.stripsMetadata(origin: .imported, always: false, imported: true))
        #expect(!UploadPreparationPolicy.stripsMetadata(origin: .capture, always: false, imported: true))
        #expect(UploadPreparationPolicy.stripsMetadata(origin: .capture, always: true, imported: false))
        #expect(!UploadPreparationPolicy.stripsMetadata(origin: .imported, always: false, imported: false))
    }

    @Test func preparesAnImportedPhotoBeforeUpload() async throws {
        let photo = try SyntheticImages.photoWithLocation()
        let policy = UploadPreparationPolicy(stripsMetadata: true, optimization: ImageOptimizationSettings(enabled: false, format: .lossless, quality: 1))
        let prepared = await UploadPreparation.prepare(photo, policy: policy)
        defer { prepared.discard() }
        #expect(prepared.fileURL != photo)
        #expect(prepared.strippedMetadata)
        #expect(SyntheticImages.properties(prepared.fileURL)[kCGImagePropertyGPSDictionary] == nil)
        #expect(SyntheticImages.properties(photo)[kCGImagePropertyGPSDictionary] != nil)
        let untouched = await UploadPreparation.prepare(photo, policy: UploadPreparationPolicy(stripsMetadata: false, optimization: policy.optimization))
        #expect(untouched.fileURL == photo)
    }

    @Test func readsTheOriginFromTheTaskLocal() async {
        #expect(UploadOrigin.current == .capture)
        let inside = await UploadOrigin.$current.withValue(.imported) { () async in UploadOrigin.current }
        #expect(inside == .imported)
    }
}

extension NetworkSuite {
    @MainActor
    @Suite
    struct OptimizedUploadTests {
        @Test func uploadsTheOptimizedFileAndRecordsTheSavings() async throws {
            UploadService.session = StubURLProtocol.makeSession()
            StubURLProtocol.reset { _ in StubResponse(body: Data(#"{"url": "https://cdn.example.com/a.png"}"#.utf8)) }
            let spy = UploadEnvironmentSpy()
            UploadCoordinator.environment = spy
            let previous = Defaults[.optimizeImagesBeforeUpload]
            Defaults[.optimizeImagesBeforeUpload] = true
            defer {
                Defaults[.optimizeImagesBeforeUpload] = previous
                UploadCoordinator.environment = LiveUploadEnvironment()
            }
            var uploader = TestUploaders.http(name: "opt", host: "opt.example.com")
            uploader.imageOptimization = ImageOptimizationOverride(format: .lossless)
            let source = try SyntheticImages.unfilteredPNG()
            let originalSize = ImageOptimizer.fileSize(source)
            let results = await UploadCoordinator.upload(fileURL: source, to: [.custom(uploader)], localFileURL: source)
            let outcome = try #require(try results.first?.get())
            #expect(outcome.savedBytes ?? 0 > 0)
            let item = try #require(spy.history.first)
            #expect(item.originalSize == originalSize)
            #expect((item.uploadedSize ?? .max) < originalSize)
            #expect(item.localPath == source.path)
            #expect(item.savingsDescription != nil)
            let uploaded = try #require(StubURLProtocol.lastRequest)
            #expect(uploaded.body.count < originalSize + 1024)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }
}
