import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

enum ImageProcessing {
    nonisolated(unsafe) static let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])

    static func ciRect(fromTopLeft rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func render(_ image: CIImage, extent: CGRect? = nil, colorSpace: CGColorSpace? = nil) -> CGImage? {
        context.createCGImage(image, from: extent ?? image.extent, format: .RGBA8, colorSpace: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    }

    static func pixelate(_ image: CGImage, region: CGRect, blockSize: CGFloat? = nil) -> CGImage {
        let input = CIImage(cgImage: image)
        let rect = ciRect(fromTopLeft: region, imageHeight: CGFloat(image.height)).intersection(input.extent)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return image }
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(blockSize ?? max(8, min(rect.width, rect.height) / 14))
        filter.center = CGPoint(x: rect.minX, y: rect.minY)
        guard let output = filter.outputImage?.cropped(to: rect) else { return image }
        return render(output.composited(over: input), extent: input.extent, colorSpace: image.colorSpace) ?? image
    }

    static func blur(_ image: CGImage, region: CGRect, radius: CGFloat? = nil) -> CGImage {
        let input = CIImage(cgImage: image)
        let rect = ciRect(fromTopLeft: region, imageHeight: CGFloat(image.height)).intersection(input.extent)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return image }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.cropped(to: rect).clampedToExtent()
        filter.radius = Float(radius ?? max(10, min(rect.width, rect.height) / 8))
        guard let output = filter.outputImage?.cropped(to: rect) else { return image }
        return render(output.composited(over: input), extent: input.extent, colorSpace: image.colorSpace) ?? image
    }

    static func borderColor(of image: CGImage, around region: CGRect) -> CIColor {
        let input = CIImage(cgImage: image)
        let rect = ciRect(fromTopLeft: region, imageHeight: CGFloat(image.height))
        let ring = rect.insetBy(dx: -3, dy: -3).intersection(input.extent)
        guard !ring.isNull else { return CIColor(red: 1, green: 1, blue: 1) }
        let strips = [
            CGRect(x: ring.minX, y: ring.minY, width: ring.width, height: 3),
            CGRect(x: ring.minX, y: ring.maxY - 3, width: ring.width, height: 3),
            CGRect(x: ring.minX, y: ring.minY, width: 3, height: ring.height),
            CGRect(x: ring.maxX - 3, y: ring.minY, width: 3, height: ring.height),
        ]
        var totals = [Double](repeating: 0, count: 4)
        for strip in strips {
            let filter = CIFilter.areaAverage()
            filter.inputImage = input
            filter.extent = strip
            guard let output = filter.outputImage else { continue }
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            for index in 0 ..< 4 {
                totals[index] += Double(pixel[index]) / 255
            }
        }
        return CIColor(red: totals[0] / 4, green: totals[1] / 4, blue: totals[2] / 4, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? CIColor(red: 1, green: 1, blue: 1)
    }

    static func erase(_ image: CGImage, region: CGRect) -> CGImage {
        let input = CIImage(cgImage: image)
        let rect = ciRect(fromTopLeft: region, imageHeight: CGFloat(image.height)).intersection(input.extent)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return image }
        let fill = CIImage(color: borderColor(of: image, around: region)).cropped(to: rect)
        return render(fill.composited(over: input), extent: input.extent, colorSpace: image.colorSpace) ?? image
    }

    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.oriented(clockwise ? .right : .left)
        return render(output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY)), colorSpace: image.colorSpace) ?? image
    }

    static func flipped(_ image: CGImage, horizontally: Bool) -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input.oriented(horizontally ? .upMirrored : .downMirrored)
        return render(output.transformed(by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY)), colorSpace: image.colorSpace) ?? image
    }

    static func resized(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxPixelSize else { return image }
        let scale = maxPixelSize / longest
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        guard let output = filter.outputImage else { return image }
        return render(output, colorSpace: image.colorSpace) ?? image
    }

    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return image }
        return image.cropping(to: clamped) ?? image
    }

    static func thumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }

    static func icon(_ image: NSImage?, height: CGFloat) -> NSImage {
        guard let image, image.size.height > 0 else { return NSImage(size: CGSize(width: height, height: height)) }
        let ratio = image.size.width / image.size.height
        let size = CGSize(width: height * ratio, height: height)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    static func averageLuminance(of image: CGImage) -> Double {
        let filter = CIFilter.areaAverage()
        let input = CIImage(cgImage: image)
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }
}
