import Combine
import Defaults
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

final class AudioLevelsProvider: ObservableObject {
    @Published var audioLevels = AudioLevels.zero
}

enum RecordingTarget {
    case picker
    case region(NSScreen, CGRect)
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var startDate = Date()
}

struct RecordingHUD: View {
    @ObservedObject var model: RecordingHUDModel
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
            TimelineView(.periodic(from: model.startDate, by: 1)) { context in
                Text(Duration.seconds(context.date.timeIntervalSince(model.startDate)).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            Button(action: onStop) {
                Label("Stop".localized(), systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .adaptiveGlassButtonStyle(prominent: true)
            .tint(.red)
            .accessibilityIdentifier("recording.stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlassCapsule()
    }
}

@MainActor
final class ScreenRecorder: ObservableObject {
    @Published var isRunning = false
    @Published var startDate: Date?
    @Published private(set) var audioLevelsProvider = AudioLevelsProvider()

    private var audioMeterCancellable: AnyCancellable?
    private let captureEngine = CaptureEngine()
    private var overlayWindows: [NSWindow] = []

    var canRecord: Bool {
        get async {
            guard ScreenshotEngine.ensurePermission() else { return false }
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                NSLog("Screen recording permissions denied: %@", error.localizedDescription)
                return false
            }
        }
    }

    func start(_ fileURL: URL, target: RecordingTarget = .picker) async {
        guard !isRunning else { return }
        switch target {
        case .picker:
            startWithPicker(fileURL)
        case let .region(screen, rect):
            await startRegion(fileURL, screen: screen, rect: rect)
        }
    }

    private func startWithPicker(_ fileURL: URL) {
        isRunning = true
        let pickerManager = ContentSharingPickerManager.shared
        Task {
            await pickerManager.setContentSelectedCallback { [weak self] filter, _ in
                Task { @MainActor [weak self] in
                    await self?.startCapture(with: filter, fileURL: fileURL)
                }
            }
            await pickerManager.setContentSelectionCancelledCallback { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isRunning = false
                    self?.startDate = nil
                }
            }
            await pickerManager.setContentSelectionFailedCallback { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isRunning = false
                    self?.startDate = nil
                }
            }
            let stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
            pickerManager.setupPicker(stream: stream)
            pickerManager.showPicker()
        }
    }

    private func startRegion(_ fileURL: URL, screen: NSScreen, rect: CGRect) async {
        do {
            let content = try await ScreenshotEngine.shareableContent()
            guard let display = ScreenshotEngine.display(for: screen, in: content) else { throw CaptureError.displayNotFound }
            let filter = SCContentFilter(display: display, excludingApplications: ScreenshotEngine.excludedApplications(in: content), exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = makeConfiguration(pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale))
            configuration.sourceRect = rect
            showRegionOverlay(screen: screen, rect: rect)
            isRunning = true
            await run(configuration: configuration, filter: filter, fileURL: fileURL)
        } catch {
            NSLog("Region recording failed: %@", error.localizedDescription)
            removeOverlay()
            isRunning = false
        }
    }

    private func makeConfiguration(pixelSize: CGSize) -> SCStreamConfiguration {
        let configuration = Defaults[.useHDR] ? SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay) : SCStreamConfiguration()
        let output = Defaults[.recordingResolution].outputSize(for: pixelSize)
        configuration.width = Int(output.width)
        configuration.height = Int(output.height)
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = Defaults[.recordingFrameRate].minimumFrameInterval
        configuration.queueDepth = 6
        return configuration
    }

    private func showRegionOverlay(screen: NSScreen, rect: CGRect) {
        let global = CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let border = RegionOverlay.borderWindow(around: global, dashed: false)
        let model = RecordingHUDModel()
        let hud = RegionOverlay.hudWindow(RecordingHUD(model: model) {
            CaptureSession.stopRecording()
        }, near: global, on: screen)
        border.orderFrontRegardless()
        hud.orderFrontRegardless()
        overlayWindows = [border, hud]
    }

    private func removeOverlay() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    func stop() async -> Result<URL, any Error> {
        removeOverlay()
        let result = await captureEngine.stopCapture()
        stopAudioMetering()
        isRunning = false
        startDate = nil
        return result
    }

    private func startAudioMetering() {
        audioMeterCancellable = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            audioLevelsProvider.audioLevels = captureEngine.audioLevels
        }
    }

    private func stopAudioMetering() {
        audioMeterCancellable?.cancel()
        audioLevelsProvider.audioLevels = AudioLevels.zero
    }

    private func startCapture(with filter: SCContentFilter, fileURL: URL) async {
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = makeConfiguration(pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale))
        isRunning = true
        await run(configuration: configuration, filter: filter, fileURL: fileURL)
    }

    private func run(configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL) async {
        startDate = Date()
        startAudioMetering()
        do {
            for try await _ in captureEngine.startCapture(configuration: configuration, filter: filter, fileURL: fileURL) {}
        } catch {
            NSLog("Capture stream ended: %@", error.localizedDescription)
        }
    }
}
