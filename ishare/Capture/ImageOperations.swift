import CoreGraphics
import Defaults
import Foundation
import ishareCore

enum ImageOperation: String, CaseIterable, Sendable {
    case beautify
    case frame
    case trim
    case redact
    case liftSubject

    var suffix: String {
        switch self {
        case .beautify: "beautified"
        case .frame: "framed"
        case .trim: "trimmed"
        case .redact: "redacted"
        case .liftSubject: "subject"
        }
    }
}

enum ImageOperationError: LocalizedError {
    case unreadable
    case failed

    var errorDescription: String? {
        switch self {
        case .unreadable: "The image couldn’t be opened".localized()
        case .failed: "The image couldn’t be processed".localized()
        }
    }
}

@MainActor
enum ImageOperations {
    static func outputURL(for input: URL, operation: ImageOperation, in folder: URL?) -> URL {
        let directory = folder ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        return ImageCaptureFlow.availableURL(directory.appending(path: "\(base)-\(operation.suffix).png"))
    }

    static func apply(_ operation: ImageOperation, to input: URL, device: DeviceFrame = .laptop, dark: Bool = false, savingIn folder: URL? = nil) async throws -> URL {
        let output = outputURL(for: input, operation: operation, in: folder)
        if operation == .redact {
            let categories = Defaults[.redactionCategories].isEmpty ? Set(RedactionCategory.allCases) : Defaults[.redactionCategories]
            let redacted = try await Redactor.redactedCopy(of: input, categories: categories) ?? input
            guard let image = ImageEncoder.loadImage(at: redacted) else { throw ImageOperationError.unreadable }
            if redacted != input { try? FileManager.default.removeItem(at: redacted) }
            try ImageEncoder.write(image, as: .PNG, to: output)
            return output
        }
        guard let image = ImageEncoder.loadImage(at: input) else { throw ImageOperationError.unreadable }
        guard let result = try await process(image, with: operation, device: device, dark: dark) else { throw ImageOperationError.failed }
        try ImageEncoder.write(result, as: .PNG, to: output, pointScale: ImageEncoder.pointScale(of: input))
        return output
    }

    static func process(_ image: CGImage, with operation: ImageOperation, device: DeviceFrame, dark: Bool) async throws -> CGImage? {
        switch operation {
        case .beautify:
            let style = BeautifyStyle.current(scale: 2)
            return await BlockingWork.run { Beautifier.apply(to: image, style: style) }
        case .frame:
            var framed = BeautifyStyle.current(scale: 2)
            framed.frame = DeviceFrameStyle(kind: device, appearance: dark ? .dark : .light)
            let style = framed
            return await BlockingWork.run { Beautifier.apply(to: image, style: style) }
        case .trim:
            let padding = Defaults[.trimBorderPadding]
            return await BlockingWork.run { BorderTrimmer.trimmed(image, padding: padding) } ?? image
        case .liftSubject:
            return try await SubjectLifter.lift(image, croppedToSubject: true)
        case .redact:
            return nil
        }
    }
}
