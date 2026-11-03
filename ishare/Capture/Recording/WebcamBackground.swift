import AppKit
@preconcurrency import AVFoundation
import CoreImage
import Defaults
import Vision

enum WebcamBackground: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case none
    case blur
    case remove

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "Keep".localized()
        case .blur: "Blur".localized()
        case .remove: "Remove".localized()
        }
    }
}

final class WebcamBackgroundProcessor: @unchecked Sendable {
    static let replacementColor = CIColor(red: 0.11, green: 0.11, blue: 0.15)

    let style: WebcamBackground
    private let request = VNGeneratePersonSegmentationRequest()
    private let context = CIContext(options: [.cacheIntermediates: false])

    init?(style: WebcamBackground) {
        guard style != .none else { return nil }
        self.style = style
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func processed(_ buffer: CVPixelBuffer) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([request])) != nil, let maskBuffer = request.results?.first?.pixelBuffer else { return nil }
        let input = CIImage(cvPixelBuffer: buffer)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: input.extent.width / mask.extent.width, y: input.extent.height / mask.extent.height))
        let background: CIImage =
            switch style {
            case .blur: input.clampedToExtent().applyingGaussianBlur(sigma: max(6, input.extent.height * 0.035)).cropped(to: input.extent)
            case .remove, .none: CIImage(color: Self.replacementColor).cropped(to: input.extent)
            }
        return input.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: scaledMask])
    }

    func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        guard let image = processed(buffer) else { return nil }
        return context.createCGImage(image, from: image.extent)
    }

    func render(_ buffer: CVPixelBuffer, into output: CVPixelBuffer) -> Bool {
        guard let image = processed(buffer) else { return false }
        context.render(image, to: output)
        return true
    }
}

final class WebcamProcessedFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let output = AVCaptureVideoDataOutput()
    private let processor: WebcamBackgroundProcessor
    private let queue = DispatchQueue(label: "dev.adrian.ishare.WebcamProcessedFeed")
    private weak var layer: CALayer?

    init(processor: WebcamBackgroundProcessor, layer: CALayer) {
        self.processor = processor
        self.layer = layer
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let buffer = sampleBuffer.imageBuffer, let image = processor.cgImage(from: buffer) else { return }
        DispatchQueue.main.async { [weak layer] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contents = image
            CATransaction.commit()
        }
    }
}
