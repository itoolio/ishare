import BezelNotification
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import MetalFX
import ishareCore

enum UpscaleMethod: Sendable {
    case automatic
    case metalFX
    case lanczos
}

enum ImageUpscaler {
    static let sharpness: Float = 0.45

    static func upscale(_ image: CGImage, by factor: UpscaleFactor, method: UpscaleMethod = .automatic) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        guard UpscaleGeometry.canUpscale(size, by: factor) else { return nil }
        switch method {
        case .lanczos:
            return lanczos(image, factor: factor)
        case .metalFX:
            return metalFX(image, factor: factor)
        case .automatic:
            return metalFX(image, factor: factor) ?? lanczos(image, factor: factor)
        }
    }

    static func lanczos(_ image: CGImage, factor: UpscaleFactor) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = UpscaleGeometry.outputSize(for: CGSize(width: image.width, height: image.height), factor: factor)
        let scale = CIFilter.lanczosScaleTransform()
        scale.inputImage = input.clampedToExtent()
        scale.scale = Float(factor.scale)
        scale.aspectRatio = 1
        guard let scaled = scale.outputImage else { return nil }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = scaled
        sharpen.sharpness = sharpness
        sharpen.radius = Float(factor.scale) * 0.75
        let extent = CGRect(origin: .zero, size: output)
        let sharpened = (sharpen.outputImage ?? scaled).cropped(to: extent)
        return ImageProcessing.render(sharpened, extent: extent, colorSpace: image.colorSpace)
    }

    static var supportsMetalFX: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    static func metalFX(_ image: CGImage, factor: UpscaleFactor) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice(), MTLFXSpatialScalerDescriptor.supportsDevice(device),
            let queue = device.makeCommandQueue(), var pixels = PixelBuffer(image: image), pixels.isOpaque
        else { return nil }
        for _ in 0 ..< factor.passes {
            guard let doubled = doubleWithMetalFX(pixels, device: device, queue: queue) else { return nil }
            pixels = doubled
        }
        return pixels.makeImage()
    }

    private static func doubleWithMetalFX(_ pixels: PixelBuffer, device: MTLDevice, queue: MTLCommandQueue) -> PixelBuffer? {
        let outputWidth = pixels.width * 2
        let outputHeight = pixels.height * 2
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = pixels.width
        descriptor.inputHeight = pixels.height
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorTextureFormat = .rgba8Unorm
        descriptor.outputTextureFormat = .rgba8Unorm
        descriptor.colorProcessingMode = .perceptual
        guard let scaler = descriptor.makeSpatialScaler(device: device) else { return nil }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: pixels.width, height: pixels.height, mipmapped: false)
        inputDescriptor.usage = scaler.colorTextureUsage
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outputWidth, height: outputHeight, mipmapped: false)
        outputDescriptor.usage = scaler.outputTextureUsage
        outputDescriptor.storageMode = .private
        let readbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outputWidth, height: outputHeight, mipmapped: false)
        readbackDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor), let output = device.makeTexture(descriptor: outputDescriptor),
            let readback = device.makeTexture(descriptor: readbackDescriptor), let commandBuffer = queue.makeCommandBuffer()
        else { return nil }
        pixels.bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            input.replace(region: MTLRegionMake2D(0, 0, pixels.width, pixels.height), mipmapLevel: 0, withBytes: base, bytesPerRow: pixels.bytesPerRow)
        }
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.inputContentWidth = pixels.width
        scaler.inputContentHeight = pixels.height
        scaler.encode(commandBuffer: commandBuffer)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: output, to: readback)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        var result = PixelBuffer(width: outputWidth, height: outputHeight)
        let rowBytes = result.bytesPerRow
        result.bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            readback.getBytes(base, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0)
        }
        return result
    }

    struct PixelBuffer {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        var bytesPerRow: Int { width * 4 }

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
        }

        init?(image: CGImage) {
            self.init(width: image.width, height: image.height)
            let rowBytes = bytesPerRow
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.setBlendMode(.copy)
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { return nil }
        }

        var isOpaque: Bool {
            stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }
        }

        func makeImage() -> CGImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
        }
    }
}

extension EditorDocument {
    func canUpscale(by factor: UpscaleFactor) -> Bool {
        UpscaleGeometry.canUpscale(imageSize, by: factor)
    }

    @discardableResult
    func upscale(by factor: UpscaleFactor, method: UpscaleMethod = .automatic) async -> Bool {
        commitPendingEdits()
        guard !isProcessing, canUpscale(by: factor) else { return false }
        let image = base
        let upscaled = await withProcessing {
            await Task.detached(priority: .userInitiated) { ImageUpscaler.upscale(image, by: factor, method: method) }.value
        }
        guard let upscaled, image === base else { return false }
        let target = CGRect(x: 0, y: 0, width: upscaled.width, height: upscaled.height)
        let mapping = TemplateMapping(source: imageBounds, target: target)
        replaceBase(with: upscaled) { annotation in
            annotation.mapped(with: mapping)
        } crop: { rect in
            mapping.rect(rect).integral
        }
        return true
    }
}

@MainActor
enum UpscaleFlow {
    static func upscaleAsNewCapture(from url: URL, by factor: UpscaleFactor) async {
        guard let image = ImageEncoder.loadImage(at: url) else {
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
            return
        }
        guard UpscaleGeometry.canUpscale(CGSize(width: image.width, height: image.height), by: factor) else {
            BezelNotification.show(messageText: "The image is too large to upscale".localized(), icon: ToastIcon)
            return
        }
        guard let upscaled = await Task.detached(priority: .userInitiated, operation: { ImageUpscaler.upscale(image, by: factor) }).value else {
            BezelNotification.show(messageText: "Couldn't upscale the image".localized(), icon: ToastIcon)
            return
        }
        await NewCaptureDocument.openInEditor(upscaled, suffix: "upscaled", preservesTransparency: true)
    }

    static func title(for factor: UpscaleFactor, size: CGSize) -> String {
        let output = UpscaleGeometry.outputSize(for: size, factor: factor)
        return "\(factor.rawValue)× — \(Int(output.width)) × \(Int(output.height))"
    }
}

extension HistoryActions {
    static func upscale(_ item: HistoryItem, by factor: UpscaleFactor) {
        guard let file = item.existingLocalFileURL else { return }
        MenuController.shared.perform {
            await UpscaleFlow.upscaleAsNewCapture(from: file, by: factor)
        }
    }
}
