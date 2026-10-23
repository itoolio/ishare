import AppKit
import BezelNotification
import CoreImage
import SwiftUI
import Vision

enum SubjectLiftError: LocalizedError, Equatable {
    case noSubject
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noSubject: "No subject was found in this image. Try a capture with a clear foreground object or person.".localized()
        case .renderFailed: "The subject couldn't be cut out of the image.".localized()
        }
    }
}

enum SubjectLifter {
    static func lift(_ image: CGImage, croppedToSubject: Bool) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try performLift(on: image, croppedToSubject: croppedToSubject)
        }.value
    }

    private static func performLift(on image: CGImage, croppedToSubject: Bool) throws -> CGImage {
        do {
            return try performLift(on: image, croppedToSubject: croppedToSubject, onCPU: false)
        } catch SubjectLiftError.noSubject {
            throw SubjectLiftError.noSubject
        } catch {
            return try performLift(on: image, croppedToSubject: croppedToSubject, onCPU: true)
        }
    }

    private static func performLift(on image: CGImage, croppedToSubject: Bool, onCPU: Bool) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        if onCPU, let cpu = try request.supportedComputeStageDevices[.main]?.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw SubjectLiftError.noSubject }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: croppedToSubject)
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let output = ImageProcessing.render(masked, colorSpace: image.colorSpace) else { throw SubjectLiftError.renderFailed }
        return output
    }
}

@MainActor
enum SubjectLiftFlow {
    static func liftAsNewCapture(from url: URL) async {
        guard let image = ImageEncoder.loadImage(at: url) else {
            BezelNotification.show(messageText: "Couldn't open the image".localized(), icon: ToastIcon)
            return
        }
        guard let lifted = await lift(image, croppedToSubject: true) else { return }
        await NewCaptureDocument.openInEditor(lifted, suffix: "subject", preservesTransparency: true)
    }

    static func lift(_ image: CGImage, croppedToSubject: Bool) async -> CGImage? {
        do {
            return try await SubjectLifter.lift(image, croppedToSubject: croppedToSubject)
        } catch {
            Log.app.error("Lifting the subject failed: \(error.localizedDescription, privacy: .public)")
            reportFailure(error)
            return nil
        }
    }

    static func reportFailure(_ error: Error) {
        let noSubject = (error as? SubjectLiftError) == .noSubject
        ToastController.showMessage(
            title: noSubject ? "No Subject Found".localized() : "Couldn’t Lift the Subject".localized(),
            message: (error as? SubjectLiftError)?.errorDescription ?? error.localizedDescription,
            symbol: noSubject ? "person.fill.questionmark" : "exclamationmark.triangle.fill",
            tint: .orange
        )
    }
}
