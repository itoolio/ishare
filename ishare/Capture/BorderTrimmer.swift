import AppKit
import BezelNotification
import Defaults
import ishareCore

enum BorderTrimmer {
    static func contentRect(of image: CGImage, padding: Int) -> CGRect? {
        guard let buffer = ImageUpscaler.PixelBuffer(image: image) else { return nil }
        return BorderTrim.contentRect(in: RGBAPixels(width: buffer.width, height: buffer.height, bytes: buffer.bytes), padding: padding)
    }

    static func trimmed(_ image: CGImage, padding: Int) -> CGImage? {
        guard let rect = contentRect(of: image, padding: padding) else { return nil }
        return image.cropping(to: rect)
    }

    static func trimIfEnabled(_ image: CGImage) -> CGImage {
        guard Defaults[.trimUniformBorders] else { return image }
        return trimmed(image, padding: Defaults[.trimBorderPadding]) ?? image
    }

    @MainActor static func trimAsNewCapture(from url: URL) async {
        guard let image = ImageEncoder.loadImage(at: url) else {
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
            return
        }
        let padding = Defaults[.trimBorderPadding]
        guard let result = await BlockingWork.run({ trimmed(image, padding: padding) }) else {
            BezelNotification.show(messageText: "No uniform borders found".localized(), icon: ToastIcon)
            return
        }
        await NewCaptureDocument.openInEditor(result, suffix: "trimmed", preservesTransparency: true)
    }
}
