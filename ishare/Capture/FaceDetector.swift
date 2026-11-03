import CoreGraphics
import Vision

enum FaceDetector {
    static func faces(in image: CGImage) async throws -> [CGRect] {
        try await BlockingWork.runThrowing {
            do {
                return try detect(in: image, onCPU: false)
            } catch {
                return try detect(in: image, onCPU: true)
            }
        }
    }

    private static func detect(in image: CGImage, onCPU: Bool) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        if onCPU, let cpu = try request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }
}
