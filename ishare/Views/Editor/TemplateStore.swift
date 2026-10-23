import AppKit
import Combine
import Foundation

@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore(directory: defaultDirectory)
    static let previewSize = CGSize(width: 72, height: 44)

    static var defaultDirectory: URL {
        if RuntimeEnvironment.isRunningTests {
            return FileManager.default.temporaryDirectory.appending(path: "ishare-tests/Templates", directoryHint: .isDirectory)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "ishare/Templates", directoryHint: .isDirectory)
    }

    @Published private(set) var templates: [AnnotationTemplate] = []
    let directory: URL
    private var previews: [UUID: NSImage] = [:]

    init(directory: URL) {
        self.directory = directory
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        templates = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                do {
                    return try AnnotationTemplate.decode(Data(contentsOf: url))
                } catch {
                    Log.app.error("Reading template \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            .sorted { $0.createdAt < $1.createdAt }
        previews.removeAll()
    }

    func defaultName() -> String {
        let base = "Template".localized()
        let existing = Set(templates.map(\.name))
        return (1...).lazy.map { "\(base) \($0)" }.first { !existing.contains($0) } ?? base
    }

    @discardableResult
    func save(name: String, annotations: [Annotation], frame: CGRect) throws -> AnnotationTemplate {
        let template = AnnotationTemplate(name: resolvedName(name), annotations: annotations, frame: frame)
        try write(template)
        templates.append(template)
        return template
    }

    func rename(_ id: UUID, to name: String) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        var template = templates[index]
        template.name = resolvedName(name)
        try write(template)
        templates[index] = template
    }

    func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        templates.removeAll { $0.id == id }
        previews[id] = nil
    }

    func preview(for template: AnnotationTemplate) -> NSImage {
        if let cached = previews[template.id] { return cached }
        let image = TemplatePreview.image(for: template, fitting: Self.previewSize)
        previews[template.id] = image
        return image
    }

    func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func resolvedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName() : trimmed
    }

    private func write(_ template: AnnotationTemplate) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try template.encoded().write(to: fileURL(for: template.id), options: .atomic)
    }
}

enum TemplatePreview {
    static func size(for template: AnnotationTemplate, fitting bounds: CGSize) -> CGSize {
        let ratio = template.aspectRatio
        let width = min(bounds.width, bounds.height * ratio)
        return CGSize(width: max(1, width.rounded()), height: max(1, (width / max(0.01, ratio)).rounded()))
    }

    static func cgImage(for template: AnnotationTemplate, size: CGSize, pixelScale: CGFloat = 2) -> CGImage? {
        let width = Int((size.width * pixelScale).rounded())
        let height = Int((size.height * pixelScale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 0.55, alpha: 1))
        context.fill(canvas)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let annotations = template.annotations(fittedTo: canvas)
        AnnotationRenderer.draw(annotations.filter { !$0.isEffect }, in: context, source: nil, canvasSize: canvas.size)
        for effect in annotations.filter(\.isEffect) {
            context.setFillColor(CGColor(gray: 0.8, alpha: 0.6))
            context.fill(effect.bounds)
        }
        return context.makeImage()
    }

    static func image(for template: AnnotationTemplate, fitting bounds: CGSize) -> NSImage {
        let size = size(for: template, fitting: bounds)
        guard let cgImage = cgImage(for: template, size: size) else { return NSImage(size: size) }
        return NSImage(cgImage: cgImage, size: size)
    }
}
