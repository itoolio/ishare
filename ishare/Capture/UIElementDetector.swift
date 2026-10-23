import CoreGraphics
import Foundation
import Vision

enum UIElementDetector {
    static let textPadding: CGFloat = 3
    static let duplicateTolerance: CGFloat = 3

    static func detect(in image: CGImage) async -> [CGRect] {
        let result = try? await Task.detached(priority: .utility) {
            try performDetection(on: image)
        }.value
        return result ?? []
    }

    static func pixelRect(fromNormalized box: CGRect, imageSize: CGSize) -> CGRect {
        let minX = (box.minX * imageSize.width).rounded()
        let maxX = (box.maxX * imageSize.width).rounded()
        let minY = ((1 - box.maxY) * imageSize.height).rounded()
        let maxY = ((1 - box.minY) * imageSize.height).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func deduplicated(_ rects: [CGRect], tolerance: CGFloat) -> [CGRect] {
        var unique: [CGRect] = []
        for rect in rects where rect.width >= 2 && rect.height >= 2 {
            let duplicate = unique.contains { existing in
                abs(existing.minX - rect.minX) <= tolerance && abs(existing.maxX - rect.maxX) <= tolerance
                    && abs(existing.minY - rect.minY) <= tolerance && abs(existing.maxY - rect.maxY) <= tolerance
            }
            if !duplicate {
                unique.append(rect)
            }
        }
        return unique
    }

    private static func performDetection(on image: CGImage) throws -> [CGRect] {
        do {
            return try performDetection(on: image, onCPU: false)
        } catch {
            return try performDetection(on: image, onCPU: true)
        }
    }

    private static func performDetection(on image: CGImage, onCPU: Bool) throws -> [CGRect] {
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 0
        rectangles.minimumAspectRatio = 0.02
        rectangles.maximumAspectRatio = 1
        rectangles.minimumSize = 0.02
        rectangles.quadratureTolerance = 10
        rectangles.minimumConfidence = 0.4
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        if onCPU {
            for request in [rectangles, text] as [VNRequest] {
                if let cpu = try request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
                    request.setComputeDevice(cpu, for: .main)
                }
            }
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([rectangles, text])
        let size = CGSize(width: image.width, height: image.height)
        let boxes = (rectangles.results ?? []).map { pixelRect(fromNormalized: $0.boundingBox, imageSize: size) }
        let lines = (text.results ?? []).map {
            pixelRect(fromNormalized: $0.boundingBox, imageSize: size).insetBy(dx: -textPadding, dy: -textPadding)
        }
        return deduplicated(boxes + lines, tolerance: duplicateTolerance)
    }
}
