import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoderError: Error {
    case destinationUnavailable
    case finalizeFailed
}

enum ImageEncoder {
    static let lossyQuality = 0.9

    static func contentType(for fileType: FileType) -> UTType {
        switch fileType {
        case .PNG: .png
        case .JPG: .jpeg
        case .PDF: .pdf
        case .TIFF: .tiff
        case .HEIC: .heic
        }
    }

    static func data(for image: CGImage, as fileType: FileType) throws -> Data {
        let output = NSMutableData()
        if fileType == .PDF {
            try writePDF(image, consumer: CGDataConsumer(data: output as CFMutableData))
            return output as Data
        }
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, contentType(for: fileType).identifier as CFString, 1, nil) else {
            throw ImageEncoderError.destinationUnavailable
        }
        CGImageDestinationAddImage(destination, prepared(image, for: fileType), properties(for: fileType) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageEncoderError.finalizeFailed }
        return output as Data
    }

    static func write(_ image: CGImage, as fileType: FileType, to url: URL) throws {
        try data(for: image, as: fileType).write(to: url, options: .atomic)
    }

    static func properties(for fileType: FileType) -> [CFString: Any] {
        switch fileType {
        case .JPG, .HEIC:
            [kCGImageDestinationLossyCompressionQuality: lossyQuality]
        default:
            [:]
        }
    }

    static func prepared(_ image: CGImage, for fileType: FileType) -> CGImage {
        guard fileType == .JPG, image.alphaInfo != .none, image.alphaInfo != .noneSkipFirst, image.alphaInfo != .noneSkipLast else {
            return image
        }
        let width = image.width
        let height = image.height
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return image }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func writePDF(_ image: CGImage, consumer: CGDataConsumer?) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer, let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ImageEncoderError.destinationUnavailable
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
    }

    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
