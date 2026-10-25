import AppKit
import AVFoundation
import CoreVideo

enum ClipEncoderError: Error {
    case cannotStart(String)
    case noPixelBuffer
    case appendFailed(String)
    case finishFailed(String)
}

@MainActor
final class ClipEncoder {
    let size: CGSize
    let framesPerSecond: Int32
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var frameIndex: Int64 = 0

    init(url: URL, size: CGSize, framesPerSecond: Int32, bitRate: Int = 1_800_000) throws {
        self.size = size
        self.framesPerSecond = framesPerSecond
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: Int(framesPerSecond) * 2,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw ClipEncoderError.cannotStart(writer.error?.localizedDescription ?? "unknown") }
        writer.startSession(atSourceTime: .zero)
    }

    var frameCount: Int64 { frameIndex }

    func append(_ image: CGImage) throws {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let pool = adaptor.pixelBufferPool else { throw ClipEncoderError.noPixelBuffer }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw ClipEncoderError.noPixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { throw ClipEncoderError.noPixelBuffer }
        context.interpolationQuality = .high
        context.draw(image, in: Self.aspectFill(CGSize(width: image.width, height: image.height), in: size))
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: framesPerSecond)) else {
            throw ClipEncoderError.appendFailed(writer.error?.localizedDescription ?? "unknown")
        }
        frameIndex += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ClipEncoderError.finishFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)") }
    }

    nonisolated static func aspectFill(_ source: CGSize, in target: CGSize) -> CGRect {
        let scale = max(target.width / max(1, source.width), target.height / max(1, source.height))
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height)
    }

    nonisolated static func jpeg(_ image: CGImage, size: CGSize, quality: Double = 0.8) -> Data? {
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: aspectFill(CGSize(width: image.width, height: image.height), in: size))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
