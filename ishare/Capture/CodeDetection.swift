import AppKit
import BezelNotification
import Defaults
import Foundation
import Vision

enum CodeDetection {
    static func payloads(in image: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let observations = (request.results ?? []).sorted { first, second in
                if abs(first.boundingBox.midY - second.boundingBox.midY) > 0.01 {
                    return first.boundingBox.midY > second.boundingBox.midY
                }
                return first.boundingBox.minX < second.boundingBox.minX
            }
            return uniquePayloads(observations.compactMap(\.payloadStringValue))
        }.value
    }

    static func uniquePayloads(_ payloads: [String]) -> [String] {
        var seen = Set<String>()
        return
            payloads
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func preferredPayload(_ payloads: [String]) -> String? {
        payloads.first(where: isWebLink) ?? payloads.first
    }

    static func isWebLink(_ payload: String) -> Bool {
        guard let url = URL(string: payload), let scheme = url.scheme?.lowercased(), url.host() != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    @MainActor @discardableResult
    static func copyPayloadIfEnabled(fromImageAt fileURL: URL) async -> Bool {
        guard Defaults[.copyLinksFromCodes], let image = ImageEncoder.loadImage(at: fileURL) else { return false }
        guard let payloads = try? await payloads(in: image), let payload = preferredPayload(payloads) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        let message = isWebLink(payload) ? "Copied link from code".localized() : "Copied code contents".localized()
        BezelNotification.show(messageText: message, icon: ToastIcon)
        return true
    }
}
