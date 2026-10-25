import BezelNotification
import Combine
import Defaults
import Foundation
import ishareCore
import SwiftUI
@preconcurrency import ScreenCaptureKit

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
    @Published var showsSystemAudio = RecordingAudioSource.current != .none
    @Published var showsMicrophone = RecordingDefaults[.recordMic]
    @Published var markerCount = 0
    @Published var showsNotes = RecordingNotesController.shared.isVisible
    @Published var remainingTime: Double?
    @Published var canDraw = false
    @Published var isDrawing = false
    @Published var pauses = RecordingPauseTimeline()
    var clockStart = RecordingClock.now

    var isPaused: Bool { pauses.isPaused }

    func recordedTime() -> Double {
        pauses.recordedDuration(from: clockStart, to: RecordingClock.now)
    }
}

struct RecordingHUD: View {
    @ObservedObject var model: RecordingHUDModel
    @ObservedObject var levels: AudioLevelsProvider
    var onMarker: () -> Void
    var onNotes: () -> Void = {}
    var onDraw: () -> Void = {}
    var onPause: () -> Void = {}
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if model.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(Text("Paused".localized()))
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
            }
            TimelineView(.periodic(from: model.startDate, by: 1)) { _ in
                Text(Duration.seconds(model.recordedTime()).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(model.isPaused ? .secondary : .primary)
            }
            .accessibilityIdentifier("recording.elapsed")
            if let remaining = model.remainingTime {
                Text("−" + Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(remaining < 30 ? .red : .secondary)
                    .help("Time left before the recording stops automatically".localized())
                    .accessibilityIdentifier("recording.remaining")
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
            Button(action: onNotes) {
                Image(systemName: model.showsNotes ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .help("Show or hide your notes. Only you can see them.".localized())
            .accessibilityLabel(Text("Notes".localized()))
            .accessibilityIdentifier("recording.notes")
            if model.canDraw {
                Button(action: onDraw) {
                    Image(systemName: model.isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .adaptiveGlassButtonStyle(prominent: false)
                .help("Draw on the screen".localized())
                .accessibilityLabel(Text("Draw on Screen".localized()))
                .accessibilityIdentifier("recording.draw")
            }
            Button(action: onPause) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .adaptiveGlassButtonStyle(prominent: false)
            .help(model.isPaused ? "Resume Recording".localized() : "Pause Recording".localized())
            .accessibilityLabel(Text(model.isPaused ? "Resume Recording".localized() : "Pause Recording".localized()))
            .accessibilityIdentifier("recording.pause")
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
    @Published private(set) var isPaused = false
    @Published private(set) var pauses = RecordingPauseTimeline()
    private var clockStart = RecordingClock.now
    private var isChangingPause = false
    @Published private(set) var audioLevelsProvider = AudioLevelsProvider()

    private var audioMeterCancellable: AnyCancellable?
    private let captureEngine = CaptureEngine()
    private var overlayWindows: [NSWindow] = []
    private let inputOverlay = InputOverlayController()
    private let webcamBubble = WebcamBubbleController()
    private let overlayRecorder = OverlayEventRecorder()
    private let pointerRecorder = PointerActivityRecorder()
    private let drawing = LiveDrawingController()
    private let limitMonitor = RecordingLimitMonitor()
    @Published private(set) var remainingTime: Double? {
        didSet { updateStatusToolTip() }
    }
    private var hudModel = RecordingHUDModel()
    private var markerLog = RecordingMarkerLog()
    private var sidecar = RecordingSidecar.empty
    private var audioPlan = RecordingAudioPlan.contentAudio
    private var appAudioRecorder: AppAudioRecorder?

    private var captureOverlayWindowIDs: Set<CGWindowID> {
        RecordingCaptureExclusion.capturedOverlayIDs(
            overlays: inputOverlay.windowIDs + drawing.windowIDs + [webcamBubble.windowID].compactMap(\.self),
            privateWindows: [RecordingNotesController.shared.windowID]
        )
    }

    private var showsClicks: Bool {
        RecordingDefaults[.recordClicks] && !RecordingDefaults[.clickRipples]
    }

    private var showsNativeClicks: Bool {
        showsClicks && !inputOverlay.drawsClicks && !overlayRecorder.capturesClicks
    }

    private var showsSystemCursor: Bool {
        RecordingDefaults[.recordPointer] && !PointerEffectSettings.current.rendersPointer
    }

    init() {
        pointerRecorder.isSuspended = { [weak drawing] in drawing?.isDrawing ?? false }
        drawing.onChange = { [weak self] isDrawing in self?.hudModel.isDrawing = isDrawing }
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
        resetPauses()
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
        let onSelected: @Sendable (SCContentFilter, SCStream?) -> Void = { [weak self] filter, _ in
            Task { @MainActor [weak self] in
                await self?.startCapture(with: filter, fileURL: fileURL)
            }
        }
        let onCancelled: @Sendable (SCStream?) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetPickerState()
            }
        }
        let onFailed: @Sendable (any Error) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetPickerState()
            }
        }
        Task {
            await pickerManager.setContentSelectedCallback(onSelected)
            await pickerManager.setContentSelectionCancelledCallback(onCancelled)
            await pickerManager.setContentSelectionFailedCallback(onFailed)
            let stream = SCStream(filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil)
            pickerManager.setupPicker(stream: stream)
            pickerManager.showPicker()
        }
    }

    private func resetPickerState() {
        isRunning = false
        startDate = nil
        RecordingDefaults.end()
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
            startPointerRecording(source: Self.regionSource(rect, on: screen))
            isRunning = true
            await prepareAudio(style: .display, screen: screen, content: content)
            await run(configuration: configuration, filter: filter, fileURL: fileURL)
        } catch {
            NSLog("Region recording failed: %@", error.localizedDescription)
            removeOverlay()
            hideCaptureOverlays()
            isRunning = false
            RecordingDefaults.end()
        }
    }

    private static func regionSource(_ rect: CGRect, on screen: NSScreen) -> OverlaySource {
        let bounds = screen.displayID.map(CGDisplayBounds) ?? CGRect(origin: .zero, size: screen.frame.size)
        let global = CGRect(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY, width: rect.width, height: rect.height)
        return OverlaySource(windowID: nil, sourceRect: global, contentSize: rect.size)
    }

    private func startPointerRecording(source: OverlaySource) {
        guard PointerActivityRecorder.isRequested else { return }
        pointerRecorder.start(source: source)
    }

    private func makeConfiguration(pixelSize: CGSize) -> SCStreamConfiguration {
        let configuration = RecordingDefaults[.useHDR] ? SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay) : SCStreamConfiguration()
        let output = RecordingDefaults[.recordingResolution].outputSize(for: pixelSize)
        configuration.width = Int(output.width)
        configuration.height = Int(output.height)
        configuration.scalesToFit = true
        configuration.minimumFrameInterval = RecordingDefaults[.recordingFrameRate].minimumFrameInterval
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
        RegionOverlay.hudWindow(
            RecordingHUD(
                model: hudModel, levels: audioLevelsProvider,
                onMarker: { [weak self] in
                    self?.addMarker()
                },
                onNotes: { [weak self] in
                    self?.toggleNotes()
                },
                onDraw: { [weak self] in
                    self?.toggleDrawing()
                },
                onPause: { [weak self] in
                    self?.togglePause()
                },
                onStop: {
                    CaptureSession.stopRecording()
                }), near: rect, on: screen)
    }

    private func showCaptureOverlays(areas: [RecordingArea], bubbleArea: CGRect?) async {
        inputOverlay.start(
            areas: areas,
            showsClicks: showsClicks,
            showsKeystrokes: RecordingDefaults[.showKeystrokes],
            shortcutsOnly: RecordingDefaults[.keystrokesShortcutsOnly]
        )
        drawing.prepare(screens: Self.uniqueScreens(areas.map(\.screen)))
        hudModel.canDraw = drawing.isPrepared
        if RecordingDefaults[.showWebcam], let bubbleArea {
            await webcamBubble.show(in: bubbleArea)
        }
    }

    private func hideCaptureOverlays() {
        inputOverlay.stop()
        webcamBubble.hide()
        drawing.tearDown()
        hudModel.canDraw = false
    }

    private static func uniqueScreens(_ screens: [NSScreen]) -> [NSScreen] {
        screens.reduce(into: [NSScreen]()) { result, screen in
            if !result.contains(where: { $0 === screen }) { result.append(screen) }
        }
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
        let time = start.map { pauses.recordedDuration(from: $0, to: RecordingClock.now) } ?? Date().timeIntervalSince(startDate)
        let marker = markerLog.add(at: time)
        hudModel.markerCount = markerLog.times.count
        Log.capture.info("Added \(marker.title, privacy: .public) at \(marker.time)s")
    }

    func toggleDrawing() {
        guard isRunning else { return }
        guard drawing.isPrepared else {
            BezelNotification.show(messageText: "Drawing is available in full-screen and region recordings".localized(), icon: ToastIcon)
            return
        }
        drawing.toggle()
    }

    func toggleNotes() {
        RecordingNotesController.shared.toggle()
        hudModel.showsNotes = RecordingNotesController.shared.isVisible
    }

    var recordedTime: Double {
        guard startDate != nil else { return 0 }
        return pauses.recordedDuration(from: clockStart, to: RecordingClock.now)
    }

    var canPause: Bool {
        isRunning && startDate != nil && !isChangingPause
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func pause() {
        guard canPause, !isPaused else { return }
        isChangingPause = true
        let now = RecordingClock.now
        Task { @MainActor in
            defer { isChangingPause = false }
            guard await captureEngine.pauseRecording() else { return }
            guard isRunning else { return }
            pauses.pause(at: now)
            setPaused(true)
            Log.capture.info("Paused the recording")
        }
    }

    func resume() {
        guard canPause, isPaused else { return }
        guard captureEngine.resumeRecording() else { return }
        pauses.resume(at: RecordingClock.now)
        setPaused(false)
        Log.capture.info("Resumed the recording")
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        hudModel.pauses = pauses
        updateStatusToolTip()
    }

    private func resetPauses() {
        pauses = RecordingPauseTimeline()
        isPaused = false
        isChangingPause = false
        clockStart = RecordingClock.now
    }

    private func updateStatusToolTip() {
        StatusItemController.shared.setRecordingToolTip(RecordingStatusText.toolTip(isRecording: isRunning && startDate != nil, isPaused: isPaused, remaining: remainingTime))
    }

    func takeSidecar() -> RecordingSidecar {
        defer { sidecar = .empty }
        return sidecar
    }

    func stop() async -> Result<URL, any Error> {
        removeOverlay()
        limitMonitor.stop()
        drawing.endDrawing()
        let result = await captureEngine.stopCapture()
        hideCaptureOverlays()
        RecordingNotesController.shared.recordingDidStop()
        let overlay = await overlayRecorder.stop()
        let effects = pointerRecorder.stop()
        let appAudio = await appAudioRecorder?.stop()
        appAudioRecorder = nil
        let finalPauses = pauses.closed(at: RecordingClock.now)
        sidecar = RecordingSidecar(
            markers: markerLog.markers, overlay: overlay, effects: effects, recordingStart: captureEngine.startClock.time, appAudio: appAudio, pauses: finalPauses)
        markerLog = RecordingMarkerLog()
        stopAudioMetering()
        isRunning = false
        startDate = nil
        resetPauses()
        remainingTime = nil
        return result
    }

    private func startLimitMonitor(fileURL: URL, startDate: Date) {
        let engine = captureEngine
        limitMonitor.bytesWritten = { engine.recordedFileSize }
        limitMonitor.recordedTime = { [weak self] in self?.recordedTime ?? 0 }
        limitMonitor.onRemainingTime = { [weak self] remaining in
            self?.remainingTime = remaining
            self?.hudModel.remainingTime = remaining
        }
        limitMonitor.onStop = { [weak self] reason in
            guard self?.isRunning == true else { return }
            BezelNotification.show(messageText: reason.message.localized(), icon: ToastIcon)
            CaptureSession.stopRecording()
        }
        limitMonitor.start(fileURL: fileURL, startDate: startDate)
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

    private func startCapture(with pickedFilter: SCContentFilter, fileURL: URL) async {
        let rect = pickedFilter.contentRect
        let scale = CGFloat(pickedFilter.pointPixelScale)
        let configuration = makeConfiguration(pixelSize: CGSize(width: rect.width * scale, height: rect.height * scale))
        guard startDate == nil else {
            let filter = await capturableFilter(pickedFilter)
            RecordingAudioFilter.apply(audioPlan, to: configuration)
            configuration.captureMicrophone = RecordingDefaults[.recordMic]
            configuration.microphoneCaptureDeviceID = RecordingDefaults[.recordMic] ? CaptureDevices.connectedMicrophoneID(Defaults[.microphoneDeviceID]) : nil
            configuration.showsCursor = showsSystemCursor
            configuration.showMouseClicks = showsNativeClicks
            if overlayRecorder.isActive {
                overlayRecorder.update(source: OverlaySource.make(for: pickedFilter))
            }
            if pointerRecorder.isActive {
                pointerRecorder.update(source: OverlaySource.make(for: pickedFilter))
            }
            await captureEngine.update(configuration: configuration, filter: filter)
            return
        }
        isRunning = true
        let style = RecordingContentStyle(pickedFilter.style)
        startPointerRecording(source: OverlaySource.make(for: pickedFilter))
        if style == .display, let screen = recordedScreen(for: pickedFilter) {
            await showCaptureOverlays(areas: [.fullScreen(screen)], bubbleArea: screen.visibleFrame)
            if RecordingLimits.current.hasRecordingLimit {
                showPickerHUD()
            }
        } else {
            let source = OverlaySource.make(for: pickedFilter)
            await overlayRecorder.start(
                source: source,
                showsClicks: showsClicks,
                showsKeystrokes: RecordingDefaults[.showKeystrokes],
                shortcutsOnly: RecordingDefaults[.keystrokesShortcutsOnly],
                recordsWebcam: RecordingDefaults[.showWebcam]
            )
            showWebcamPreview(for: source)
            showPickerHUD()
        }
        let filter = await capturableFilter(pickedFilter)
        await prepareAudio(style: style, screen: recordedScreen(for: pickedFilter), content: nil)
        await run(configuration: configuration, filter: filter, fileURL: fileURL)
    }

    private func showWebcamPreview(for source: OverlaySource) {
        guard let session = overlayRecorder.webcamSession else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let area =
            source.currentRect().map { WebcamBubblePreviewArea.cocoaRect(fromCGGlobal: $0, primaryScreenHeight: primaryHeight) }
            ?? NSScreen.main?.visibleFrame
        guard let area else { return }
        webcamBubble.showPreview(of: session, in: area)
    }

    private func capturableFilter(_ filter: SCContentFilter) async -> SCContentFilter {
        guard filter.style == .display,
            let screen = recordedScreen(for: filter),
            let content = try? await ScreenshotEngine.shareableContent(),
            let display = ScreenshotEngine.display(for: screen, in: content)
        else { return filter }
        let overlayIDs = captureOverlayWindowIDs
        let overlayWindows = content.windows.filter { overlayIDs.contains($0.windowID) }
        return SCContentFilter(display: display, excludingApplications: ScreenshotEngine.excludedApplications(in: content), exceptingWindows: overlayWindows)
    }

    private func prepareAudio(style: RecordingContentStyle, screen: NSScreen?, content knownContent: SCShareableContent?) async {
        audioPlan = RecordingAudioPlan.current(style)
        hudModel.showsSystemAudio = audioPlan.recordsAudio
        guard case let .applications(bundleIDs) = audioPlan else { return }
        let content = if let knownContent { knownContent } else { try? await ScreenshotEngine.shareableContent() }
        guard let screen, let content, let display = ScreenshotEngine.display(for: screen, in: content),
            let filter = RecordingAudioFilter.filter(display: display, bundleIDs: bundleIDs, in: content)
        else {
            Log.capture.info("None of the selected audio apps are running")
            return
        }
        let recorder = AppAudioRecorder()
        let engine = captureEngine
        recorder.onSamples = { samples in
            Task { @MainActor in engine.meterSystemAudio(samples) }
        }
        if await recorder.start(filter: filter) {
            appAudioRecorder = recorder
        }
    }

    private func run(configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL) async {
        RecordingNotesController.shared.recordingDidStart()
        hudModel.showsNotes = RecordingNotesController.shared.isVisible
        let startDate = Date()
        clockStart = RecordingClock.now
        hudModel.clockStart = clockStart
        self.startDate = startDate
        updateStatusToolTip()
        startAudioMetering()
        startLimitMonitor(fileURL: fileURL, startDate: startDate)
        do {
            for try await _ in captureEngine.startCapture(
                configuration: configuration, filter: filter, fileURL: fileURL, showsNativeClicks: showsNativeClicks, showsCursor: showsSystemCursor, audioPlan: audioPlan)
            {}
        } catch {
            NSLog("Capture stream ended: %@", error.localizedDescription)
        }
    }
}
