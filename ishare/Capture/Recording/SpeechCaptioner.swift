import AVFoundation
import Foundation
import Speech

enum SpeechCaptionError: LocalizedError {
    case notAuthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Speech recognition isn't allowed"
        case .unavailable: "On-device speech recognition isn't available for your language"
        }
    }
}

enum SpeechCaptioner {
    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    static func cues(for videoURL: URL) async throws -> [CaptionCue] {
        guard isAuthorized else { throw SpeechCaptionError.notAuthorized }
        guard let audioURL = try await extractAudio(from: videoURL) else { return [] }
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let segments: [TranscriptSegment]
        if #available(macOS 26, *), SpeechTranscriber.isAvailable {
            segments = try await AnalyzerTranscription.segments(for: audioURL)
        } else {
            segments = try await RecognizerTranscription.segments(for: audioURL)
        }
        return CaptionLayout.cues(from: segments)
    }

    private static func extractAudio(from url: URL) async throws -> URL? {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty,
            let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let output = FileManager.default.temporaryDirectory.appending(path: "ishare-captions-\(UUID().uuidString).m4a")
        try await session.export(to: output, as: .m4a)
        return output
    }
}

@available(macOS 26, *)
private enum AnalyzerTranscription {
    static func segments(for audioURL: URL) async throws -> [TranscriptSegment] {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return try await RecognizerTranscription.segments(for: audioURL)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audioURL)
        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                segments.append(contentsOf: Self.segments(in: result))
            }
            return segments
        }
        do {
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        } catch {
            collector.cancel()
            throw error
        }
        return try await collector.value
    }

    private static func segments(in result: SpeechTranscriber.Result) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for run in result.text.runs {
            let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self]
            guard let range, range.start.isNumeric, range.duration.isNumeric else {
                if let last = segments.last {
                    segments[segments.count - 1].text = last.text + " " + text
                } else {
                    segments.append(TranscriptSegment(text: text, start: result.range.start.seconds, end: result.range.end.seconds))
                }
                continue
            }
            segments.append(TranscriptSegment(text: text, start: range.start.seconds, end: range.end.seconds))
        }
        return segments
    }
}

private enum RecognizerTranscription {
    static func segments(for audioURL: URL) async throws -> [TranscriptSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
            recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition
        else { throw SpeechCaptionError.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let collector = RecognitionCollector()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal {
                        collector.append(
                            result.bestTranscription.segments.map {
                                TranscriptSegment(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                            })
                        if collector.finish() { continuation.resume(returning: collector.segments) }
                    } else if let error {
                        let nsError = error as NSError
                        let isNoSpeech = nsError.domain == "kAFAssistantErrorDomain" && [203, 1110].contains(nsError.code)
                        guard collector.finish() else { return }
                        if isNoSpeech || !collector.segments.isEmpty {
                            continuation.resume(returning: collector.segments)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            collector.task?.cancel()
        }
    }
}

private final class RecognitionCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [TranscriptSegment] = []
    private var isFinished = false
    var task: SFSpeechRecognitionTask?

    var segments: [TranscriptSegment] {
        lock.withLock { collected }
    }

    func append(_ segments: [TranscriptSegment]) {
        lock.withLock { collected.append(contentsOf: segments) }
    }

    func finish() -> Bool {
        lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
    }
}
