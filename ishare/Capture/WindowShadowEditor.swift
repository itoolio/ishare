import CoreGraphics
import ishareCore

enum WindowShadowEditor {
    static func apply(_ style: WindowShadowStyle, to image: CGImage, scale: CGFloat = 2) -> CGImage? {
        guard let buffer = ImageUpscaler.PixelBuffer(image: image) else { return nil }
        let pixels = RGBAPixels(width: buffer.width, height: buffer.height, bytes: buffer.bytes)
        guard let opaque = WindowShadow.opaqueBounds(in: pixels), let window = image.cropping(to: opaque) else { return nil }
        guard style != .none else { return window }
        let padding = style.padding * scale
        let width = window.width + Int(padding * 2)
        let height = window.height + Int(padding * 2)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setShadow(
            offset: CGSize(width: 0, height: -style.offset * scale), blur: style.blur * scale, color: CGColor(gray: 0, alpha: style.opacity))
        context.draw(window, in: CGRect(x: padding, y: padding, width: CGFloat(window.width), height: CGFloat(window.height)))
        return context.makeImage()
    }
}
