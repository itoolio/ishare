import AppKit
@preconcurrency import AVFoundation
import Defaults
import ishareCore
@preconcurrency import Speech
import SwiftUI

@MainActor
final class LiveCaptionModel: ObservableObject {
    @Published var lines: [String] = []
}

final class LiveCaptionRecognizer: @unchecked Sendable {
    static let restartInterval: TimeInterval = 50

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt = Date()
    private let lock = NSLock()
    var onText: (@Sendable (String) -> Void)?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    var isAvailable: Bool {
        recognizer?.isAvailable == true
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        beginTask()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock {
            request?.endAudio()
            task?.cancel()
            request = nil
            task = nil
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        let needsRestart = lock.withLock { () -> Bool in
            request?.append(buffer)
            return Date().timeIntervalSince(startedAt) > Self.restartInterval
        }
        if needsRestart {
            beginTask()
        }
    }

    private func beginTask() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        lock.withLock {
            self.request?.endAudio()
            self.task?.finish()
            self.request = request
            startedAt = Date()
            task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let text = result?.bestTranscription.formattedString, !text.isEmpty else { return }
                self?.onText?(text)
            }
        }
    }
}

@MainActor
final class LiveCaptionController {
    static let hideDelay: Duration = .seconds(3)

    private var overlays: [(window: NSPanel, model: LiveCaptionModel)] = []
    private var recognizer: LiveCaptionRecognizer?
    private var hideTask: Task<Void, Never>?

    var windowIDs: [CGWindowID] {
        overlays.map { CGWindowID($0.window.windowNumber) }
    }

    static var isRequested: Bool {
        RecordingDefaults[.liveCaptions]
    }

    func start(areas: [RecordingArea]) async {
        stop()
        guard Self.isRequested, !areas.isEmpty else { return }
        guard await SpeechCaptioner.requestAuthorization(), await CaptureDevices.requestAccess(for: .audio) else {
            Log.capture.info("Live captions are off because speech recognition or the microphone isn't allowed")
            return
        }
        let recognizer = LiveCaptionRecognizer()
        guard recognizer.isAvailable else {
            Log.capture.info("Live captions are off because speech recognition isn't available")
            return
        }
        overlays = areas.map(makeOverlay)
        overlays.forEach { $0.window.orderFrontRegardless() }
        recognizer.onText = { [weak self] text in
            Task { @MainActor in self?.show(text) }
        }
        do {
            try recognizer.start()
            self.recognizer = recognizer
        } catch {
            Log.capture.error("Live captions couldn't start: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        recognizer?.stop()
        recognizer = nil
        hideTask?.cancel()
        hideTask = nil
        overlays.forEach { $0.window.orderOut(nil) }
        overlays.removeAll()
    }

    private func show(_ transcript: String) {
        let lines = LiveCaptionText.lines(of: transcript)
        overlays.forEach { $0.model.lines = lines }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self?.overlays.forEach { $0.model.lines = [] }
            }
        }
    }

    private func makeOverlay(for area: RecordingArea) -> (window: NSPanel, model: LiveCaptionModel) {
        let model = LiveCaptionModel()
        let height: CGFloat = 120
        let frame = CGRect(x: area.rect.minX, y: area.rect.minY + 24, width: area.rect.width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .recordingOverlay
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LiveCaptionView(model: model))
        panel.setFrame(frame, display: false)
        return (panel, model)
    }
}

struct LiveCaptionView: View {
    @ObservedObject var model: LiveCaptionModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if !model.lines.isEmpty {
                Text(model.lines.joined(separator: "\n"))
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
