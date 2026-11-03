import AppIntents
import CoreGraphics
import Defaults
import Foundation
import ishareCore
import UniformTypeIdentifiers

enum ImageIntentIO {
    static func load(_ file: IntentFile) throws -> (CGImage, URL) {
        let staged = try IntentFileStaging.stage(file)
        guard let image = ImageEncoder.loadImage(at: staged) else { throw IntentError.unreadableFile }
        return (image, staged)
    }

    static func output(_ image: CGImage, named name: String) throws -> IntentFile {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ishare-intent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name).png")
        try ImageEncoder.write(image, as: .PNG, to: url)
        return IntentFile(fileURL: url, filename: url.lastPathComponent, type: .png)
    }

    static func baseName(of file: IntentFile) -> String {
        let name = URL(fileURLWithPath: file.filename).deletingPathExtension().lastPathComponent
        return name.isEmpty ? "ishare" : name
    }
}

enum DeviceFrameChoice: String, AppEnum {
    case laptop
    case display
    case phone
    case browser

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Device" }
    static var caseDisplayRepresentations: [DeviceFrameChoice: DisplayRepresentation] {
        [.laptop: "Laptop", .display: "Desktop Display", .phone: "Phone", .browser: "Browser Window"]
    }

    var frame: DeviceFrame {
        switch self {
        case .laptop: .laptop
        case .display: .display
        case .phone: .phone
        case .browser: .browser
        }
    }
}

enum CombineLayoutChoice: String, AppEnum {
    case horizontal
    case vertical
    case grid

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Layout" }
    static var caseDisplayRepresentations: [CombineLayoutChoice: DisplayRepresentation] {
        [.horizontal: "Side by Side", .vertical: "Stacked", .grid: "Grid"]
    }

    var layout: CombineLayout {
        switch self {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .grid: .grid
        }
    }
}

struct BeautifyImageIntent: AppIntent {
    static var title: LocalizedStringResource { "Beautify Image with ishare" }
    static var description: IntentDescription { IntentDescription("Adds the background, padding, corners, shadow and frame from ishare's beautify settings.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let style = BeautifyStyle.current(scale: 2)
        guard let result = await BlockingWork.run({ Beautifier.apply(to: image, style: style) }) else { throw IntentError.unreadableFile }
        return .result(value: try ImageIntentIO.output(result, named: ImageIntentIO.baseName(of: file) + "-beautified"))
    }
}

struct FrameImageInDeviceIntent: AppIntent {
    static var title: LocalizedStringResource { "Frame Image in Device with ishare" }
    static var description: IntentDescription { IntentDescription("Places the image in a laptop, display, phone or browser frame.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @Parameter(title: "Device", default: .laptop)
    var device: DeviceFrameChoice

    @Parameter(title: "Dark", default: false)
    var dark: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        var framed = BeautifyStyle.current(scale: 2)
        framed.frame = DeviceFrameStyle(kind: device.frame, appearance: dark ? .dark : .light)
        let style = framed
        guard let result = await BlockingWork.run({ Beautifier.apply(to: image, style: style) }) else { throw IntentError.unreadableFile }
        return .result(value: try ImageIntentIO.output(result, named: ImageIntentIO.baseName(of: file) + "-framed"))
    }
}

struct CombineImagesIntent: AppIntent {
    static var title: LocalizedStringResource { "Combine Images with ishare" }
    static var description: IntentDescription { IntentDescription("Combines images side by side, stacked or in a grid with ishare's combine settings.") }

    @Parameter(title: "Images", supportedContentTypes: [.image])
    var files: [IntentFile]

    @Parameter(title: "Layout", default: .horizontal)
    var layout: CombineLayoutChoice

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let loaded = try files.map(ImageIntentIO.load)
        defer {
            for item in loaded { try? FileManager.default.removeItem(at: item.1.deletingLastPathComponent()) }
        }
        guard loaded.count >= 2 else { throw IntentError.unreadableFile }
        var settings = CombineSettings.load()
        settings.layout = layout.layout
        if layout == .grid, settings.columns == 0 {
            settings.columns = AppWindowsPlan.contactSheetColumns(for: loaded.count)
        }
        let style = settings.style(imageCount: loaded.count)
        let images = loaded.map { $0.0 }
        guard let result = await BlockingWork.run({ ImageCombiner.combine(images, style: style) }) else { throw IntentError.unreadableFile }
        return .result(value: try ImageIntentIO.output(result, named: "ishare-combined"))
    }
}

struct UpscaleImageIntent: AppIntent {
    static var title: LocalizedStringResource { "Upscale Image with ishare" }
    static var description: IntentDescription { IntentDescription("Upscales an image two or four times.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @Parameter(title: "Four Times", default: false)
    var fourTimes: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let factor: UpscaleFactor = fourTimes ? .quadruple : .double
        guard let result = await BlockingWork.run({ ImageUpscaler.upscale(image, by: factor) }) else { throw IntentError.unreadableFile }
        return .result(value: try ImageIntentIO.output(result, named: ImageIntentIO.baseName(of: file) + "-upscaled"))
    }
}

struct LiftSubjectIntent: AppIntent {
    static var title: LocalizedStringResource { "Lift Subject with ishare" }
    static var description: IntentDescription { IntentDescription("Removes the background around the main subject and returns a transparent PNG.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let result = try await SubjectLifter.lift(image, croppedToSubject: true)
        return .result(value: try ImageIntentIO.output(result, named: ImageIntentIO.baseName(of: file) + "-subject"))
    }
}

struct TrimBordersIntent: AppIntent {
    static var title: LocalizedStringResource { "Trim Image Borders with ishare" }
    static var description: IntentDescription { IntentDescription("Removes uniform borders and whitespace around an image.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (image, staged) = try ImageIntentIO.load(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let padding = Defaults[.trimBorderPadding]
        let result = await BlockingWork.run({ BorderTrimmer.trimmed(image, padding: padding) }) ?? image
        return .result(value: try ImageIntentIO.output(result, named: ImageIntentIO.baseName(of: file) + "-trimmed"))
    }
}

struct RedactSensitiveTextIntent: AppIntent {
    static var title: LocalizedStringResource { "Redact Sensitive Text with ishare" }
    static var description: IntentDescription { IntentDescription("Pixelates email addresses, keys and other sensitive text found in an image.") }

    @Parameter(title: "Image", supportedContentTypes: [.image])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let staged = try IntentFileStaging.stage(file)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        let categories = Defaults[.redactionCategories].isEmpty ? Set(RedactionCategory.allCases) : Defaults[.redactionCategories]
        let output = try await Redactor.redactedCopy(of: staged, categories: categories) ?? staged
        guard let image = ImageEncoder.loadImage(at: output) else { throw IntentError.unreadableFile }
        if output != staged { try? FileManager.default.removeItem(at: output) }
        return .result(value: try ImageIntentIO.output(image, named: ImageIntentIO.baseName(of: file) + "-redacted"))
    }
}
