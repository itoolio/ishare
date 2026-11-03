import CoreGraphics
import Foundation
import libwebp

enum WebPEncoder {
    enum EncodingError: Error {
        case encodingFailed
    }

    struct Frame {
        var image: CGImage
        var duration: Double
    }

    static func encode(_ image: CGImage, quality: Double? = nil) throws -> Data {
        let buffer = try rgbaBuffer(of: image)
        var output: UnsafeMutablePointer<UInt8>?
        let size = buffer.bytes.withUnsafeBufferPointer { pointer -> Int in
            guard let base = pointer.baseAddress else { return 0 }
            if let quality {
                return WebPEncodeRGBA(base, Int32(buffer.width), Int32(buffer.height), Int32(buffer.bytesPerRow), Float(quality * 100), &output)
            }
            return WebPEncodeLosslessRGBA(base, Int32(buffer.width), Int32(buffer.height), Int32(buffer.bytesPerRow), &output)
        }
        guard size > 0, let output else { throw EncodingError.encodingFailed }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }

    static func encodeAnimation(_ frames: [Frame], quality: Double = 0.8, loopCount: Int = 0) throws -> Data {
        guard let first = frames.first else { throw EncodingError.encodingFailed }
        var options = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInitInternal(&options, WEBP_MUX_ABI_VERSION) != 0 else { throw EncodingError.encodingFailed }
        options.anim_params.loop_count = Int32(loopCount)
        guard let encoder = WebPAnimEncoderNewInternal(Int32(first.image.width), Int32(first.image.height), &options, WEBP_MUX_ABI_VERSION) else {
            throw EncodingError.encodingFailed
        }
        defer { WebPAnimEncoderDelete(encoder) }
        var config = WebPConfig()
        guard WebPConfigInitInternal(&config, WEBP_PRESET_DEFAULT, Float(quality * 100), WEBP_ENCODER_ABI_VERSION) != 0 else { throw EncodingError.encodingFailed }
        var timestamp: Int32 = 0
        for frame in frames {
            var picture = WebPPicture()
            guard WebPPictureInitInternal(&picture, WEBP_ENCODER_ABI_VERSION) != 0 else { throw EncodingError.encodingFailed }
            defer { WebPPictureFree(&picture) }
            let buffer = try rgbaBuffer(of: frame.image, width: first.image.width, height: first.image.height)
            picture.use_argb = 1
            picture.width = Int32(buffer.width)
            picture.height = Int32(buffer.height)
            let imported = buffer.bytes.withUnsafeBufferPointer { pointer in
                pointer.baseAddress.map { WebPPictureImportRGBA(&picture, $0, Int32(buffer.bytesPerRow)) } ?? 0
            }
            guard imported != 0, WebPAnimEncoderAdd(encoder, &picture, timestamp, &config) != 0 else { throw EncodingError.encodingFailed }
            timestamp += Int32(max(10, (frame.duration * 1000).rounded()))
        }
        guard WebPAnimEncoderAdd(encoder, nil, timestamp, nil) != 0 else { throw EncodingError.encodingFailed }
        var data = WebPData()
        guard WebPAnimEncoderAssemble(encoder, &data) != 0, let bytes = data.bytes else { throw EncodingError.encodingFailed }
        defer { WebPFree(UnsafeMutableRawPointer(mutating: bytes)) }
        return Data(bytes: bytes, count: data.size)
    }

    private struct RGBABuffer {
        var width: Int
        var height: Int
        var bytes: [UInt8]
        var bytesPerRow: Int { width * 4 }
    }

    private static func rgbaBuffer(of image: CGImage, width: Int? = nil, height: Int? = nil) throws -> RGBABuffer {
        let width = width ?? image.width
        let height = height ?? image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard
                let context = CGContext(
                    data: pointer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw EncodingError.encodingFailed }
        unpremultiply(&bytes)
        return RGBABuffer(width: width, height: height, bytes: bytes)
    }

    private static func unpremultiply(_ bytes: inout [UInt8]) {
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                bytes[index + channel] = UInt8(min(255, Int(bytes[index + channel]) * 255 / alpha))
            }
        }
    }
}
