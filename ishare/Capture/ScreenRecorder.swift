import Combine
import Defaults
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

final class AudioLevelsProvider: ObservableObject {
    @Published var audioLevels = RecordingAudioLevels.zero
}

enum RecordingTarget {
    case picker
    case region(NSScreen, CGRect)
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var startDate = Date()
    @Published var showsSystemAudio = Defaults[.recordAudio]
    @Published var showsMicrophone = Defaults[.recordMic]
    @Published var markerCount = 0
}

struct RecordingHUD: View {
    @ObservedObject var model: RecordingHUDModel
    @ObservedObject var levels: AudioLevelsProvider
    var onMarker: () -> Void
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
            if model.showsSystemAudio || model.showsMicrophone {
                VStack(alignment: .leading, spacing: 3) {
                    if model.showsSystemAudio {
                        LabeledAudioMeter(systemImage: "speaker.wave.2.fill", levels: levels.audioLevels.system)
                            .help("System audio".localized())
                    }
                    if model.showsMicrophone {
                        LabeledAudioMeter(systemImage: "mic.fill", levels: levels.audioLevels.microphone)
                            .help("Microphone".localized())
                    }
                }
            }
            Button(action: onMarker) {
                Label(model.markerCount > 0 ? "\(model.markerCount)" : "Marker".localized(), systemImage: "bookmark.fill")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .help("Add a marker at the current time".localized())
            .accessibilityLabel(Text("Add Marker".localized()))
            .accessibilityIdentifier("recording.marker")
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
    private let inputOverlay = InputOverlayController()
    private let webcamBubble = WebcamBubbleController()
    private let overlayRecorder = OverlayEventRecorder()
    private var hudModel = RecordingHUDModel()
    private var markerLog = RecordingMarkerLog()
    private var sidecar = RecordingSidecar.empty

    private var captureOverlayWindowIDs: Set<CGWindowID> {
        Set(inputOverlay.windowIDs + [webcamBubble.windowID].compactMap(\.self))
    }

    private var showsNativeClicks: Bool {
        Defaults[.recordClicks] && !inputOverlay.drawsClicks && !overlayRecorder.capturesClicks
    }

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
        hudModel = RecordingHUDModel()
        markerLog = RecordingMarkerLog()
        sidecar = .empty
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
            let area = RecordingArea.region(rect, on: screen)
            await showCaptureOverlays(areas: [area], bubbleArea: area.rect)
            let content = try await ScreenshotEngine.shareableContent()
            guard let display = ScreenshotEngine.display(for: screen, in: content) else { throw CaptureError.displayNotFound }
            let overlayIDs = captureOverlayWindowIDs
            let overlayWindows = content.windows.filter { overlayIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingApplications: ScreenshotEngine.excludedApplications(in: content), exceptingWindows: overlayWindows)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = makeConfiguration(pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale))
            configuration.sourceRect = rect
            showRegionOverlay(screen: screen, rect: rect)
            isRunning = true
            await run(configuration: configuration, filter: filter, fileURL: fileURL)
        } catch {
            NSLog("Region recording failed: %@", error.localizedDescription)
            removeOverlay()
            hideCaptureOverlays()
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
        let global = RecordingArea.region(rect, on: screen).rect
        let border = RegionOverlay.borderWindow(around: global, dashed: false)
        let hud = makeHUDWindow(near: global, on: screen)
        border.orderFrontRegardless()
        hud.orderFrontRegardless()
        overlayWindows = [border, hud]
    }

    private func showPickerHUD() {
        guard let screen = NSScreen.main else { return }
        let anchor = CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 80, width: 0, height: 0)
        let hud = makeHUDWindow(near: anchor, on: screen)
        hud.orderFrontRegardless()
        overlayWindows = [hud]
    }

    private func makeHUDWindow(near rect: CGRect, on screen: NSScreen) -> NSPanel {
        RegionOverlay.hudWindow(RecordingHUD(model: hudModel, levels: audioLevelsProvider, onMarker: { [weak self] in
            self?.addMarker()
        }, onStop: {
            CaptureSession.stopRecording()
        }), near: rect, on: screen)
    }

    private func showCaptureOverlays(areas: [RecordingArea], bubbleArea: CGRect?) async {
        inputOverlay.start(
            areas: areas,
            showsClicks: Defaults[.recordClicks],
            showsKeystrokes: Defaults[.showKeystrokes],
            shortcutsOnly: Defaults[.keystrokesShortcutsOnly]
        )
        if Defaults[.showWebcam], let bubbleArea {
            await webcamBubble.show(in: bubbleArea)
        }
    }

    private func hideCaptureOverlays() {
        inputOverlay.stop()
        webcamBubble.hide()
    }

    private func recordedScreen(for filter: SCContentFilter) -> NSScreen? {
        if #available(macOS 15.2, *), let display = filter.includedDisplays.first {
            return NSScreen.screens.first { $0.displayID == display.displayID }
        }
        return NSScreen.screens.first { $0.frame.size == filter.contentRect.size } ?? NSScreen.main
    }

    private func removeOverlay() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    func addMarker() {
        guard isRunning, let startDate else { return }
        let start = captureEngine.startClock.time
        let time = start.map { RecordingClock.now - $0 } ?? Date().timeIntervalSince(startDate)
        let marker = markerLog.add(at: time)
        hudModel.markerCount = markerLog.times.count
        Log.capture.info("Added \(marker.title, privacy: .public) at \(marker.time)s")
    }

    func takeSidecar() -> RecordingSidecar {
        defer { sidecar = .empty }
        return sidecar
    }

    func stop() async -> Result<URL, any Error> {
        removeOverlay()
        let result = await captureEngine.stopCapture()
        hideCaptureOverlays()
        let overlay = await overlayRecorder.stop()
        sidecar = RecordingSidecar(markers: markerLog.markers, overlay: overlay, recordingStart: captureEngine.startClock.time)
        markerLog = RecordingMarkerLog()
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
        audioLevelsProvider.audioLevels = .zero
    }

    private func startCapture(with filter: SCContentFilter, fileURL: URL) async {
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = makeConfiguration(pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale))
        guard startDate == nil else {
            configuration.capturesAudio = Defaults[.recordAudio]
            configuration.captureMicrophone = Defaults[.recordMic]
            configuration.microphoneCaptureDeviceID = Defaults[.recordMic] ? CaptureDevices.connectedMicrophoneID(Defaults[.microphoneDeviceID]) : nil
            configuration.showsCursor = Defaults[.recordPointer]
            configuration.showMouseClicks = showsNativeClicks
            if overlayRecorder.isActive {
                overlayRecorder.update(source: OverlaySource.make(for: filter))
            }
            await captureEngine.update(configuration: configuration, filter: filter)
            return
        }
        isRunning = true
        if filter.style == .display, let screen = recordedScreen(for: filter) {
            await showCaptureOverlays(areas: [.fullScreen(screen)], bubbleArea: screen.visibleFrame)
        } else {
            await overlayRecorder.start(
                source: OverlaySource.make(for: filter),
                showsClicks: Defaults[.recordClicks],
                showsKeystrokes: Defaults[.showKeystrokes],
                shortcutsOnly: Defaults[.keystrokesShortcutsOnly],
                recordsWebcam: Defaults[.showWebcam]
            )
            showPickerHUD()
        }
        await run(configuration: configuration, filter: filter, fileURL: fileURL)
    }

    private func run(configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL) async {
        startDate = Date()
        startAudioMetering()
        do {
            for try await _ in captureEngine.startCapture(configuration: configuration, filter: filter, fileURL: fileURL, showsNativeClicks: showsNativeClicks) {}
        } catch {
            NSLog("Capture stream ended: %@", error.localizedDescription)
        }
    }
}
