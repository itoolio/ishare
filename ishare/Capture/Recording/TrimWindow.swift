import AppKit
import AVFoundation
import AVKit
import BezelNotification
import Defaults
import ishareCore
import SwiftUI

enum TrimOutcome: Equatable {
    case keepOriginal
    case trimmed(URL, timing: RetimingPlan)
    case exportedAnimation(URL)
    case exported(URL, timing: RetimingPlan?)
}

@MainActor
final class TrimModel: ObservableObject {
    let url: URL
    let player: AVPlayer
    let markers: [RecordingMarker]
    let autoZoom: CameraPath?
    let voiceRecorder = VoiceOverRecorder()
    @Published private(set) var appliesAutoZoom: Bool
    @Published var selection = TrimSelection(duration: 0)
    @Published private(set) var playhead: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double?
    @Published private(set) var thumbnails: [CGImage] = []
    @Published private(set) var videoSize: CGSize = .zero
    @Published var exportSettings = RecordingExportSettings.current
    @Published var errorMessage: String?

    @Published private(set) var cutsSilence = Defaults[.cutSilenceEnabled]
    @Published var silenceSettings = SilenceDetectionSettings.current {
        didSet { refreshSilencePlan() }
    }
    @Published private(set) var silencePlan: RetimingPlan?
    @Published private(set) var isAnalyzingSilence = false

    @Published private(set) var voicePhase: VoiceOverPhase = .inactive
    @Published private(set) var voiceClips: [VoiceOverClip] = []
    @Published var voiceMode = Defaults[.voiceOverMode] {
        didSet { voiceSettingsChanged() }
    }
    @Published var duckAmount = Defaults[.voiceOverDuckAmount] {
        didSet { voiceSettingsChanged() }
    }

    @Published var blurRegions: [BlurRegion] = [] {
        didSet { refreshVideoPreview() }
    }
    @Published var selectedRegionID: UUID?
    @Published var isEditingBlur = false
    @Published private(set) var blurActivity: String?

    var onFinish: ((TrimOutcome) -> Void)?
    private var timeObserver: Any?
    private var zoomIsBaked = false
    private var blurIsBaked = false
    private var previewTask: Task<Void, Never>?
    private var itemTask: Task<Void, Never>?
    fileprivate var analysisTask: Task<Void, Never>?
    fileprivate var countdownTask: Task<Void, Never>?
    fileprivate var blurTask: Task<Void, Never>?
    fileprivate var silenceAnalysis: SilenceAnalysis?
    fileprivate var voiceLevels: LevelSeries?
    fileprivate var takeStart: Double = 0
    private var skipTarget: Double?

    init(url: URL, markers: [RecordingMarker] = [], autoZoom: CameraPath? = nil) {
        self.url = url
        self.markers = markers
        self.autoZoom = autoZoom
        appliesAutoZoom = autoZoom != nil
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
    }

    var offersAutoZoom: Bool {
        autoZoom != nil && !zoomIsBaked
    }

    private var pendingZoom: CameraPath? {
        appliesAutoZoom && !zoomIsBaked ? autoZoom : nil
    }

    private var pendingBlurRegions: [BlurRegion] {
        blurIsBaked ? [] : blurRegions
    }

    var activePlan: RetimingPlan? {
        cutsSilence ? silencePlan : nil
    }

    var voiceMix: VoiceOverMix? {
        guard !voiceClips.isEmpty else { return nil }
        return VoiceOverMix(clips: voiceClips, mode: voiceMode, ducking: DuckingSettings(reduction: duckAmount), voiceLevels: voiceLevels)
    }

    var outputDuration: Double {
        guard let plan = activePlan else { return selection.length }
        return selection.isFullLength ? plan.outputDuration : plan.restricted(to: selection.start ... selection.end).outputDuration
    }

    func setAutoZoom(_ enabled: Bool) {
        appliesAutoZoom = enabled
        refreshVideoPreview()
    }

    fileprivate func refreshVideoPreview() {
        previewTask?.cancel()
        guard let item = player.currentItem else { return }
        let camera = pendingZoom
        let regions = pendingBlurRegions
        guard camera != nil || !regions.isEmpty else {
            item.videoComposition = nil
            if !isPlaying { seek(to: playhead) }
            return
        }
        previewTask = Task { @MainActor [weak self] in
            guard let composition = try? await OverlayCompositor.previewComposition(for: item.asset, camera: camera, blurRegions: regions),
                !Task.isCancelled, let self, player.currentItem === item
            else { return }
            item.videoComposition = composition
            if !isPlaying { seek(to: playhead) }
        }
    }

    fileprivate func refreshPlayerItem() {
        itemTask?.cancel()
        let mix = voiceMix
        let duration = selection.duration
        let source = url
        itemTask = Task { @MainActor [weak self] in
            let item: AVPlayerItem
            if let mix {
                guard
                    let edited = try? await RecordingEditor.composition(
                        for: AVURLAsset(url: source), edit: RecordingEdit(plan: .identity(duration: duration), voiceOver: mix)),
                    !Task.isCancelled
                else { return }
                item = AVPlayerItem(asset: edited.composition)
                item.audioMix = edited.audioMix
            } else {
                item = AVPlayerItem(url: source)
            }
            guard let self, !Task.isCancelled else { return }
            player.replaceCurrentItem(with: item)
            refreshVideoPreview()
        }
    }

    private func bakeVideoEffectsIfNeeded(progress: @escaping @Sendable (Double) -> Void) async throws {
        let camera = pendingZoom
        let regions = pendingBlurRegions
        guard camera != nil || !regions.isEmpty else { return }
        let hevc = RecordingDefaults[.useHEVC]
        try await OverlayCompositor.applyEdits(camera: camera, blurRegions: regions, to: url, hevc: hevc, progress: progress)
        zoomIsBaked = true
        blurIsBaked = true
    }

    func load() async {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return }
        selection = TrimSelection(duration: duration)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
            let naturalSize = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform)
        {
            videoSize = GIFGeometry.displaySize(naturalSize: naturalSize, transform: transform)
        }
        observePlayback()
        refreshVideoPreview()
        if cutsSilence { analyzeSilenceIfNeeded() }
        thumbnails = await Self.thumbnails(for: asset, duration: duration, count: 12)
    }

    func togglePlayback() {
        guard voicePhase == .inactive else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if playhead >= selection.end - 0.05 || playhead < selection.start {
            seek(to: selection.start)
        }
        player.play()
        isPlaying = true
        applyRetimingPreview(at: playhead)
    }

    func seek(to time: Double) {
        playhead = selection.clampedPlayhead(time)
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cancel() {
        finish(.keepOriginal)
    }

    private var hasVideoEffects: Bool {
        pendingZoom != nil || !pendingBlurRegions.isEmpty
    }

    func save() {
        guard !selection.isFullLength || hasVideoEffects || cutsSilence || voiceMix != nil else {
            finish(.keepOriginal)
            return
        }
        let source = url
        perform { progress in
            try await self.bakeVideoEffectsIfNeeded(progress: progress)
            let edit = await self.pendingEdit()
            guard !edit.isNoOp else { return .trimmed(source, timing: edit.plan) }
            let hevc = Defaults[.useHEVC]
            return .trimmed(try await RecordingEditor.renderInPlace(source, edit: edit, hevc: hevc, progress: progress), timing: edit.plan)
        }
    }

    func export() {
        let settings = exportSettings
        let isFullLength = selection.isFullLength
        let range = selection.timeRange
        let source = url
        perform { progress in
            try await self.bakeVideoEffectsIfNeeded(progress: progress)
            let edit = await self.pendingEdit()
            let output: URL
            if edit.plan.isIdentity, edit.voiceOver == nil {
                output = try await RecordingConversions.export(source, settings: settings, range: isFullLength ? nil : range, deletingSource: true, progress: progress)
            } else {
                let hevc = Defaults[.useHEVC]
                _ = try await RecordingEditor.renderInPlace(source, edit: edit, hevc: hevc, progress: progress)
                output = try await RecordingConversions.export(source, settings: settings, range: nil, deletingSource: true, progress: progress)
            }
            if settings.format.animatedFormat != nil { return .exportedAnimation(output) }
            return .exported(output, timing: edit.plan)
        }
    }

    private func pendingEdit() async -> RecordingEdit {
        if cutsSilence, silencePlan == nil {
            analyzeSilenceIfNeeded()
            await analysisTask?.value
        }
        let base = activePlan ?? .identity(duration: selection.duration)
        let plan = selection.isFullLength ? base : base.restricted(to: selection.start ... selection.end)
        return RecordingEdit(plan: plan, voiceOver: voiceMix)
    }

    func tearDown() {
        previewTask?.cancel()
        previewTask = nil
        itemTask?.cancel()
        countdownTask?.cancel()
        blurTask?.cancel()
        if voicePhase != .inactive {
            voiceRecorder.endClip()
            voicePhase = .inactive
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func perform(_ work: @escaping @MainActor (@escaping @Sendable (Double) -> Void) async throws -> TrimOutcome) {
        guard !isWorking else { return }
        if voicePhase != .inactive { finishVoiceOver() }
        isWorking = true
        errorMessage = nil
        progress = nil
        tearDown()
        isPlaying = false
        let report: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in self?.progress = value }
        }
        Task { @MainActor in
            do {
                finish(try await work(report))
            } catch {
                Log.capture.error("Trimming failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                isWorking = false
                observePlayback()
                refreshPlayerItem()
            }
        }
    }

    private func finish(_ outcome: TrimOutcome) {
        tearDown()
        voiceRecorder.tearDown()
        let handler = onFinish
        onFinish = nil
        handler?(outcome)
    }

    private func observePlayback() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.playerDidAdvance(to: time.seconds)
            }
        }
    }

    private func playerDidAdvance(to time: Double) {
        if voicePhase == .recording {
            playhead = min(time, selection.end)
            if time >= selection.end - 0.02 || (player.rate == 0 && time >= selection.end - 0.1) {
                finishVoiceOver()
            }
            return
        }
        guard isPlaying else { return }
        if let target = skipTarget {
            guard time >= target - 0.05 else { return }
            skipTarget = nil
        }
        if time >= selection.end || player.rate == 0 {
            seek(to: selection.start)
            if player.rate == 0 { player.play() }
            applyRetimingPreview(at: selection.start)
        } else {
            playhead = time
            applyRetimingPreview(at: time)
        }
    }

    fileprivate func applyRetimingPreview(at time: Double) {
        guard isPlaying, voicePhase == .inactive else { return }
        let segment = activePlan?.segments.first { time >= $0.start && time < $0.end }
        switch segment?.action {
        case .remove:
            guard let segment else { return }
            let target = min(segment.end, selection.end)
            skipTarget = target
            playhead = target
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        case let .speed(factor):
            setPreviewRate(Float(factor))
        case .keep, nil:
            setPreviewRate(1)
        }
    }

    fileprivate func setPreviewRate(_ rate: Float) {
        player.isMuted = rate > 1
        if player.rate != rate { player.rate = rate }
    }

    private static func thumbnails(for asset: AVURLAsset, duration: Double, count: Int) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let times = (0 ..< count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image {
                images.append(image)
            }
        }
        return images
    }
}

extension TrimModel {
    func setCutsSilence(_ enabled: Bool) {
        cutsSilence = enabled
        if enabled {
            analyzeSilenceIfNeeded()
        } else if isPlaying {
            setPreviewRate(1)
        }
    }

    fileprivate func analyzeSilenceIfNeeded() {
        guard silenceAnalysis == nil, analysisTask == nil else { return }
        isAnalyzingSilence = true
        let source = url
        analysisTask = Task { @MainActor [weak self] in
            let analysis = try? await SilenceCutter.analyze(source)
            guard let self else { return }
            silenceAnalysis = analysis
            isAnalyzingSilence = false
            analysisTask = nil
            if analysis == nil { errorMessage = "The recording couldn't be analyzed for silence.".localized() }
            refreshSilencePlan()
        }
    }

    fileprivate func refreshSilencePlan() {
        silencePlan = silenceAnalysis.map { $0.plan(settings: silenceSettings, extraAudio: voiceLevels) }
    }

    var silenceSummary: String? {
        guard cutsSilence else { return nil }
        if isAnalyzingSilence { return "Finding silent parts…".localized() }
        guard let plan = silencePlan else { return nil }
        let changed = plan.changedSegments.count
        guard changed > 0 else { return "No silent parts found".localized() }
        return String(format: "%d silent parts, saves %@".localized(), changed, TrimView.format(plan.sourceDuration - plan.outputDuration))
    }
}

extension TrimModel {
    func startVoiceOver() {
        guard voicePhase == .inactive, !isWorking else { return }
        Task { @MainActor in
            guard await VoiceOverRecorder.requestAccess() else {
                errorMessage = VoiceOverError.microphoneDenied.localizedDescription
                return
            }
            player.pause()
            isPlaying = false
            voiceRecorder.discardAll()
            if !voiceClips.isEmpty {
                voiceClips = []
                voiceLevels = nil
                refreshSilencePlan()
                refreshPlayerItem()
            }
            takeStart = playhead >= selection.end - 0.2 ? selection.start : selection.clampedPlayhead(playhead)
            seek(to: takeStart)
            runCountdown()
        }
    }

    func pauseVoiceOver() {
        guard voicePhase == .recording else { return }
        player.pause()
        isPlaying = false
        voiceRecorder.endClip()
        voicePhase = .paused
    }

    func resumeVoiceOver() {
        guard voicePhase == .paused else { return }
        runCountdown()
    }

    func redoVoiceOver() {
        guard voicePhase != .inactive else { return }
        countdownTask?.cancel()
        player.pause()
        isPlaying = false
        voiceRecorder.discardAll()
        seek(to: takeStart)
        runCountdown()
    }

    func finishVoiceOver() {
        guard voicePhase != .inactive else { return }
        countdownTask?.cancel()
        player.pause()
        player.volume = 1
        isPlaying = false
        voiceRecorder.endClip()
        voicePhase = .inactive
        let clips = voiceRecorder.clips
        voiceClips = clips
        Task { @MainActor [weak self] in
            let levels = await VoiceOverRecorder.levels(for: clips)
            guard let self, voiceClips == clips else { return }
            voiceLevels = levels
            refreshSilencePlan()
            refreshPlayerItem()
        }
    }

    func cancelVoiceOver() {
        countdownTask?.cancel()
        player.pause()
        player.volume = 1
        isPlaying = false
        voicePhase = .inactive
        removeVoiceOver()
    }

    func removeVoiceOver() {
        voiceRecorder.discardAll()
        voiceClips = []
        voiceLevels = nil
        refreshSilencePlan()
        refreshPlayerItem()
    }

    fileprivate func voiceSettingsChanged() {
        Defaults[.voiceOverMode] = voiceMode
        Defaults[.voiceOverDuckAmount] = duckAmount
        if !voiceClips.isEmpty { refreshPlayerItem() }
    }

    private func runCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            for count in [3, 2, 1] {
                self?.voicePhase = .countdown(count)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.beginVoiceClip()
        }
    }

    private func beginVoiceClip() {
        do {
            try voiceRecorder.beginClip(at: playhead)
        } catch {
            errorMessage = error.localizedDescription
            voicePhase = .inactive
            return
        }
        player.volume = voiceMode == .replace ? 0 : 0.35
        player.isMuted = false
        voicePhase = .recording
        isPlaying = true
        player.rate = 1
    }
}

extension TrimModel {
    var selectedRegion: BlurRegion? {
        blurRegions.first { $0.id == selectedRegionID }
    }

    func addBlurRegion(_ rect: CGRect) {
        let start = playhead >= selection.end - 0.2 ? selection.start : playhead
        let region = BlurRegion(
            style: Defaults[.blurRegionStyle], start: start, end: selection.end,
            track: RegionTrack(keyframes: [RegionKeyframe(time: playhead, rect: RegionGeometry.clampedToUnit(rect), isManual: true)]))
        blurRegions.append(region)
        selectedRegionID = region.id
    }

    func moveRegion(_ id: UUID, to rect: CGRect) {
        let time = playhead
        updateRegion(id) { region in
            region.track.setKeyframe(rect, at: time)
            if time < region.start { region.setStart(time) }
            if time > region.end { region.setEnd(time) }
        }
    }

    func setRegionStart(_ id: UUID) {
        let time = playhead
        updateRegion(id) { $0.setStart(time) }
    }

    func setRegionEnd(_ id: UUID) {
        let time = playhead
        updateRegion(id) { $0.setEnd(time) }
    }

    func setRegionStyle(_ id: UUID, style: BlurRegionStyle) {
        Defaults[.blurRegionStyle] = style
        updateRegion(id) { $0.style = style }
    }

    func removeKeyframe(_ id: UUID) {
        let time = playhead
        updateRegion(id) { region in
            guard region.track.keyframes.count > 1 else { return }
            region.track.removeKeyframe(near: time, tolerance: 0.1)
        }
    }

    func removeRegion(_ id: UUID) {
        blurRegions.removeAll { $0.id == id }
        if selectedRegionID == id { selectedRegionID = blurRegions.last?.id }
    }

    func visibleRegions() -> [VisibleBlurRegion] {
        blurRegions.compactMap { region in region.rect(at: playhead).map { VisibleBlurRegion(region: region, rect: $0) } }
    }

    func trackRegion(_ id: UUID) {
        guard blurActivity == nil, let region = blurRegions.first(where: { $0.id == id }) else { return }
        let time = min(max(playhead, region.start), region.end)
        guard let rect = region.track.rect(at: time) else { return }
        let range = region.start ... region.end
        let source = url
        runBlurActivity("Tracking…".localized()) { progress in
            let frames = try await RegionTracker.track(source, rect: rect, at: time, within: range, progress: progress)
            self.updateRegion(id) { $0.track.replaceTracked(with: frames) }
        }
    }

    func detectSensitiveRegions() {
        guard blurActivity == nil else { return }
        let interval = max(0.25, Defaults[.blurDetectionInterval])
        let categories = Defaults[.redactionCategories]
        let style = Defaults[.blurRegionStyle]
        let range = selection.start ... selection.end
        let source = url
        runBlurActivity("Looking for sensitive text…".localized()) { progress in
            let found = try await SensitiveRegionDetector.detect(in: source, interval: interval, categories: categories, style: style, range: range, progress: progress)
            self.blurRegions += found
            if found.isEmpty {
                self.errorMessage = "No sensitive text found.".localized()
            } else {
                self.selectedRegionID = found.first?.id
            }
        }
    }

    func cancelBlurActivity() {
        blurTask?.cancel()
    }

    private func updateRegion(_ id: UUID, _ change: (inout BlurRegion) -> Void) {
        guard let index = blurRegions.firstIndex(where: { $0.id == id }) else { return }
        var region = blurRegions[index]
        change(&region)
        blurRegions[index] = region
    }

    private func runBlurActivity(_ title: String, _ work: @escaping @MainActor (@escaping @Sendable (Double) -> Void) async throws -> Void) {
        blurActivity = title
        progress = 0
        errorMessage = nil
        let report: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, blurActivity != nil else { return }
                progress = value
            }
        }
        blurTask = Task { @MainActor in
            do {
                try await work(report)
            } catch is CancellationError {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            blurActivity = nil
            progress = nil
            blurTask = nil
        }
    }
}

@MainActor
final class RecordingTrimWindow: NSObject, NSWindowDelegate {
    private static var open: [RecordingTrimWindow] = []

    private let model: TrimModel
    private var window: NSWindow?
    private var continuation: CheckedContinuation<TrimOutcome, Never>?

    private init(url: URL, markers: [RecordingMarker], autoZoom: CameraPath?) {
        model = TrimModel(url: url, markers: markers, autoZoom: autoZoom)
    }

    static func present(_ url: URL, markers: [RecordingMarker] = [], autoZoom: CameraPath? = nil) async -> TrimOutcome {
        let controller = RecordingTrimWindow(url: url, markers: markers, autoZoom: autoZoom)
        open.append(controller)
        let outcome = await controller.run()
        open.removeAll { $0 === controller }
        if case let .exportedAnimation(animationURL) = outcome {
            Log.capture.info("Exported trimmed animation to \(animationURL.path, privacy: .public)")
        }
        return outcome
    }

    private func run() async -> TrimOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            model.onFinish = { [weak self] outcome in self?.complete(outcome) }

            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 920, height: 680),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Trim Recording".localized() + " — " + model.url.lastPathComponent
            window.titlebarAppearsTransparent = true
            window.contentMinSize = CGSize(width: 720, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: TrimView(model: model))
            window.center()
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            Task { await model.load() }
        }
    }

    private func complete(_ outcome: TrimOutcome) {
        let pending = continuation
        continuation = nil
        if let window {
            window.delegate = nil
            window.close()
        }
        window = nil
        pending?.resume(returning: outcome)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        !model.isWorking
    }

    func windowWillClose(_: Notification) {
        window?.delegate = nil
        window = nil
        model.cancel()
    }
}

struct TrimView: View {
    @ObservedObject var model: TrimModel
    @State private var showsExportOptions = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                PlayerSurface(player: model.player)
                if model.isEditingBlur {
                    BlurEditingOverlay(model: model)
                }
                if case let .countdown(count) = model.voicePhase {
                    VoiceOverCountdown(count: count)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause".localized() : "Play".localized())
                .disabled(model.isWorking || model.voicePhase != .inactive)

                TrimRangeSlider(
                    selection: $model.selection, playhead: model.playhead, thumbnails: model.thumbnails, markers: model.markers,
                    annotations: TrimTimelineAnnotations(model: model), onScrub: { model.seek(to: $0) }
                )
                .disabled(model.isWorking || model.voicePhase == .recording)
            }

            HStack {
                Text(Self.format(model.selection.start))
                Spacer()
                Text(String(format: "Duration: %@".localized(), Self.format(model.outputDuration)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.format(model.selection.end))
            }
            .font(.system(size: 12).monospacedDigit())

            if model.voicePhase != .inactive {
                VoiceOverBar(model: model, recorder: model.voiceRecorder)
            }
            if model.isEditingBlur {
                BlurRegionBar(model: model)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TrimToolbar(model: model)
                .disabled(model.isWorking)

            HStack {
                Button("Keep Original".localized(), action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                if model.offersAutoZoom {
                    Toggle("Auto zoom".localized(), isOn: Binding(get: { model.appliesAutoZoom }, set: { model.setAutoZoom($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Zooms in on clicks and typing. The player shows a preview at the current position; Save or Export applies it.".localized())
                        .accessibilityIdentifier("trim.autoZoom")
                }
                Spacer()
                if model.isWorking || model.blurActivity != nil {
                    if let activity = model.blurActivity {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let progress = model.progress {
                        ProgressView(value: progress).frame(width: 120)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Button("Export…".localized()) { showsExportOptions = true }
                    .popover(isPresented: $showsExportOptions, arrowEdge: .top) {
                        RecordingExportOptionsView(settings: $model.exportSettings) {
                            showsExportOptions = false
                            model.export()
                        }
                    }
                Button("Save".localized(), action: model.save)
                    .keyboardShortcut(.defaultAction)
                    .adaptiveGlassButtonStyle(prominent: true)
            }
            .disabled(model.isWorking || model.blurActivity != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(minWidth: 720, minHeight: 520)
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)))
    }
}

struct RecordingExportOptionsView: View {
    @Binding var settings: RecordingExportSettings
    var onExport: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Form {
                Picker("Format".localized(), selection: $settings.format) {
                    ForEach(RecordingExportFormat.allCases) { format in
                        Text(format.isAvailable ? format.title.localized() : String(format: "%@ (not available)".localized(), format.title))
                            .tag(format)
                            .selectionDisabled(!format.isAvailable)
                    }
                }
                if settings.format.hasVideo {
                    Picker("Size".localized(), selection: $settings.size) {
                        ForEach(RecordingExportSize.allCases) { Text($0.title.localized()).tag($0) }
                    }
                }
                if settings.format.animatedFormat != nil {
                    Picker("Frame rate".localized(), selection: $settings.gifFrameRate) {
                        ForEach(GIFFrameRate.allCases) { Text("\($0.rawValue) fps").tag($0) }
                    }
                } else {
                    Picker("Quality".localized(), selection: $settings.quality) {
                        ForEach(RecordingExportQuality.allCases) { Text($0.title.localized()).tag($0) }
                    }
                }
                if settings.format.hasVideo, settings.format.supportsAudio {
                    Toggle("Remove audio".localized(), isOn: $settings.removesAudio)
                }
            }
            if !AnimatedImageFormat.webp.isAvailable {
                Text(AnimatedImageFormat.unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Export".localized(), action: onExport)
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.format.isAvailable)
        }
        .padding(16)
        .frame(width: 320)
        .accessibilityIdentifier("trim.export.options")
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context _: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

struct TrimRangeSlider: View {
    @Binding var selection: TrimSelection
    let playhead: Double
    let thumbnails: [CGImage]
    var markers: [RecordingMarker] = []
    var annotations = TrimTimelineAnnotations()
    var onScrub: (Double) -> Void

    private let handleWidth: CGFloat = 12
    private let height: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let startX = CGFloat(selection.fraction(of: selection.start)) * width
            let endX = CGFloat(selection.fraction(of: selection.end)) * width
            let playheadX = CGFloat(selection.fraction(of: playhead)) * width

            ZStack(alignment: .leading) {
                filmstrip
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                TrimTimelineAnnotationsView(annotations: annotations, duration: selection.duration, width: width, height: height)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, startX), height: height)
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .frame(width: max(0, width - endX), height: height)
                    .offset(x: endX)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: max(handleWidth, endX - startX), height: height)
                    .offset(x: startX)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: height + 8)
                    .shadow(radius: 1)
                    .offset(x: playheadX - 1)
                    .allowsHitTesting(false)
                ForEach(markers, id: \.self) { marker in
                    markerPin(marker)
                        .offset(x: CGFloat(selection.fraction(of: marker.time)) * width - 7)
                }
                handle(systemImage: "chevron.compact.left")
                    .offset(x: startX - handleWidth / 2)
                    .gesture(
                        dragGesture(width: width) {
                            selection.setStart($0)
                            onScrub(selection.start)
                        }
                    )
                    .accessibilityLabel(Text("Start".localized()))
                handle(systemImage: "chevron.compact.right")
                    .offset(x: endX - handleWidth / 2)
                    .gesture(
                        dragGesture(width: width) {
                            selection.setEnd($0)
                            onScrub(selection.end)
                        }
                    )
                    .accessibilityLabel(Text("End".localized()))
            }
            .frame(width: width, height: height)
            .coordinateSpace(name: "trimTrack")
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .named("trimTrack")) { location in
                onScrub(selection.time(atFraction: Double(location.x / width)))
            }
        }
        .frame(height: height)
    }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle().fill(.quaternary)
            } else {
                ForEach(thumbnails.indices, id: \.self) { index in
                    Image(decorative: thumbnails[index], scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }

    private func markerPin(_ marker: RecordingMarker) -> some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.orange)
            .shadow(radius: 1)
            .frame(width: 14, height: height, alignment: .top)
            .offset(y: -6)
            .contentShape(Rectangle())
            .onTapGesture { onScrub(marker.time) }
            .help(marker.title)
            .accessibilityLabel(Text(marker.title))
            .accessibilityAddTraits(.isButton)
    }

    private func handle(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.yellow)
            .frame(width: handleWidth, height: height)
            .overlay(Image(systemName: systemImage).font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
            .contentShape(Rectangle().inset(by: -8))
    }

    private func dragGesture(width: CGFloat, update: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTrack"))
            .onChanged { value in
                update(selection.time(atFraction: Double(value.location.x / width)))
            }
    }
}
