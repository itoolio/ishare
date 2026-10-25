import AppKit
import AVFoundation
import BezelNotification
import Defaults
import ishareCore
import SwiftUI

struct RecordingSidecar: Sendable {
    static let empty = RecordingSidecar()

    var markers: [RecordingMarker] = []
    var overlay: OverlayCapture?
    var effects: RecordingEffectsCapture?
    var recordingStart: Double?
    var appAudio: AppAudioClip?
    var pauses = RecordingPauseTimeline()
}

@MainActor
final class ProcessingHUDModel: ObservableObject {
    @Published var title: String
    @Published var progress: Double?

    init(title: String) {
        self.title = title
    }
}

struct ProcessingHUD: View {
    @ObservedObject var model: ProcessingHUDModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(model.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            ProgressView(value: model.progress ?? 0)
                .frame(width: 180)
                .opacity(model.progress == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .adaptiveGlassCapsule()
        .accessibilityIdentifier("recording.processing")
    }
}

@MainActor
enum ProcessingHUDPresenter {
    static func run<Value>(_ title: String, _ work: (@escaping @Sendable (Double) -> Void) async throws -> Value) async rethrows -> Value {
        let model = ProcessingHUDModel(title: title)
        let panel = makePanel(model: model)
        panel?.orderFrontRegardless()
        defer { panel?.orderOut(nil) }
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in model.progress = value }
        }
        return try await work(report)
    }

    private static func makePanel(model: ProcessingHUDModel) -> NSPanel? {
        guard let screen = NSScreen.main else { return nil }
        let anchor = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80, width: 0, height: 0)
        return RegionOverlay.hudWindow(ProcessingHUD(model: model), near: anchor, on: screen)
    }
}

@MainActor
enum RecordingPostProcessor {
    private static let chapterExtensions: Set<String> = ["mp4", "mov", "m4v"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func mergeAppAudio(_ url: URL, sidecar: RecordingSidecar) async {
        guard let clip = sidecar.appAudio else { return }
        defer { try? FileManager.default.removeItem(at: clip.url) }
        guard let start = sidecar.recordingStart, videoExtensions.contains(url.pathExtension.lowercased()) else { return }
        do {
            try await AppAudioMuxer.merge(clip, into: url, recordingStart: start, pauses: sidecar.pauses)
        } catch {
            Log.capture.error("Adding the selected apps' audio failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    static func compositeOverlays(_ url: URL, sidecar: RecordingSidecar) async -> CameraPath? {
        let capture = sidecar.overlay
        let effects = sidecar.effects
        defer {
            if let webcam = capture?.webcam { try? FileManager.default.removeItem(at: webcam.url) }
        }
        guard capture != nil || effects != nil, let start = sidecar.recordingStart, videoExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let hevc = Defaults[.useHEVC]
        let defersZoom = Defaults[.trimBeforeSaving]
        let pauses = sidecar.pauses
        do {
            return try await ProcessingHUDPresenter.run("Processing…".localized()) { progress in
                try await OverlayCompositor.composite(
                    url, capture: capture, effects: effects, recordingStart: start, pauses: pauses, hevc: hevc, defersZoom: defersZoom, progress: progress)
            }
        } catch {
            Log.capture.error("Compositing overlays failed, keeping the original: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func finalize(_ url: URL, markers: [RecordingMarker]) async {
        await applyCaptions(to: url)
        await applyChapters(markers, to: url)
    }

    static func applyCaptions(to url: URL) async {
        guard Defaults[.generateCaptions] else { return }
        let ext = url.pathExtension.lowercased()
        guard videoExtensions.contains(ext) || ext == "m4a" else { return }
        guard SpeechCaptioner.isAuthorized else {
            Log.capture.info("Captions skipped because speech recognition isn't allowed")
            return
        }
        let output = Defaults[.captionOutput]
        let burns = output == .burnIn && videoExtensions.contains(ext)
        let hevc = Defaults[.useHEVC]
        do {
            try await ProcessingHUDPresenter.run("Generating captions…".localized()) { progress in
                let cues = try await SpeechCaptioner.cues(for: url)
                guard !cues.isEmpty else { return }
                if burns {
                    try await CaptionBurner.burn(cues, into: url, hevc: hevc, progress: progress)
                } else {
                    _ = try SRTFormatter.write(cues, nextTo: url)
                }
            }
        } catch {
            Log.capture.error("Generating captions failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Captions failed".localized(), icon: ToastIcon)
        }
    }

    static func applyChapters(_ markers: [RecordingMarker], to url: URL) async {
        guard !markers.isEmpty, chapterExtensions.contains(url.pathExtension.lowercased()) else { return }
        do {
            try await RecordingChapters.write(markers, into: url)
        } catch {
            Log.capture.error("Writing chapters failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
