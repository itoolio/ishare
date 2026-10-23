import AppKit
import BezelNotification
import Foundation

enum TextCapturePreview {
    static let maximumLength = 40

    static func summary(of text: String, limit: Int = maximumLength) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

@MainActor
enum TextCaptureFlow {
    enum Outcome: Equatable {
        case recognized(String)
        case noText
        case failed
        case cancelled
    }

    static func capture() async -> Outcome {
        guard let image = await ImageCaptureFlow.captureForRecognition() else { return .cancelled }
        do {
            let text = try await TextRecognition.recognize(in: image).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .noText : .recognized(text)
        } catch {
            Log.capture.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    @discardableResult
    static func captureAndCopy() async -> Outcome {
        let outcome = await capture()
        switch outcome {
        case let .recognized(text):
            copy(text)
            SoundPlayer.play(.capture)
            BezelNotification.show(messageText: String(format: "Copied “%@”".localized(), TextCapturePreview.summary(of: text)), icon: ToastIcon)
        case .noText:
            BezelNotification.show(messageText: "No text found".localized(), icon: ToastIcon)
        case .failed:
            BezelNotification.show(messageText: "Text recognition failed".localized(), icon: ToastIcon)
        case .cancelled:
            break
        }
        return outcome
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
