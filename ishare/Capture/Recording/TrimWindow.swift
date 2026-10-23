@preconcurrency import AppKit
@preconcurrency import AVFoundation
import AVKit
import BezelNotification
import SwiftUI

enum TrimOutcome: Equatable {
    case keepOriginal
    case trimmed(URL, range: ClosedRange<Double>)
    case exportedGIF(URL)
    case exported(URL, range: ClosedRange<Double>?)
}

@MainActor
final class TrimModel: ObservableObject {
    let url: URL
    let player: AVPlayer
    let markers: [RecordingMarker]
    @Published var selection = TrimSelection(duration: 0)
    @Published private(set) var playhead: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double?
    @Published private(set) var thumbnails: [CGImage] = []
    @Published var exportSettings = RecordingExportSettings.current
    @Published var errorMessage: String?

    var onFinish: ((TrimOutcome) -> Void)?
    private var timeObserver: Any?

    init(url: URL, markers: [RecordingMarker] = []) {
        self.url = url
        self.markers = markers
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
    }

    func load() async {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else { return }
        selection = TrimSelection(duration: duration)
        observePlayback()
        thumbnails = await Self.thumbnails(for: asset, duration: duration, count: 12)
    }

    func togglePlayback() {
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
    }

    func seek(to time: Double) {
        playhead = selection.clampedPlayhead(time)
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func cancel() {
        finish(.keepOriginal)
    }

    func save() {
        guard !selection.isFullLength else {
            finish(.keepOriginal)
            return
        }
        let range = selection.timeRange
        let bounds = selection.start ... selection.end
        perform { [url] _ in
            .trimmed(try await VideoTrimmer.trimInPlace(url, range: range), range: bounds)
        }
    }

    func export() {
        let range = selection.isFullLength ? nil : selection.timeRange
        let bounds = selection.isFullLength ? nil : selection.start ... selection.end
        let settings = exportSettings
        perform { [url] progress in
            let output = try await RecordingConversions.export(url, settings: settings, range: range, deletingSource: true, progress: progress)
            return settings.format == .gif ? .exportedGIF(output) : .exported(output, range: bounds)
        }
    }

    func tearDown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func perform(_ work: @escaping @MainActor (@escaping @Sendable (Double) -> Void) async throws -> TrimOutcome) {
        guard !isWorking else { return }
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
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                observePlayback()
            }
        }
    }

    private func finish(_ outcome: TrimOutcome) {
        tearDown()
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
        guard isPlaying else { return }
        if time >= selection.end || player.rate == 0 {
            seek(to: selection.start)
            if player.rate == 0 { player.play() }
        } else {
            playhead = time
        }
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

@MainActor
final class RecordingTrimWindow: NSObject, NSWindowDelegate {
    private static var open: [RecordingTrimWindow] = []

    private let model: TrimModel
    private var window: NSWindow?
    private var continuation: CheckedContinuation<TrimOutcome, Never>?

    private init(url: URL, markers: [RecordingMarker]) {
        model = TrimModel(url: url, markers: markers)
    }

    static func present(_ url: URL, markers: [RecordingMarker] = []) async -> TrimOutcome {
        let controller = RecordingTrimWindow(url: url, markers: markers)
        open.append(controller)
        let outcome = await controller.run()
        open.removeAll { $0 === controller }
        if case let .exportedGIF(gifURL) = outcome {
            Log.capture.info("Exported trimmed GIF to \(gifURL.path, privacy: .public)")
        }
        return outcome
    }

    private func run() async -> TrimOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            model.onFinish = { [weak self] outcome in self?.complete(outcome) }

            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 860, height: 600),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Trim Recording".localized() + " — " + model.url.lastPathComponent
            window.titlebarAppearsTransparent = true
            window.contentMinSize = CGSize(width: 620, height: 440)
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
        VStack(spacing: 14) {
            PlayerSurface(player: model.player)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button(action: model.togglePlayback) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause".localized() : "Play".localized())
                .disabled(model.isWorking)

                TrimRangeSlider(selection: $model.selection, playhead: model.playhead, thumbnails: model.thumbnails, markers: model.markers, onScrub: model.seek)
                    .disabled(model.isWorking)
            }

            HStack {
                Text(Self.format(model.selection.start))
                Spacer()
                Text(String(format: "Duration: %@".localized(), Self.format(model.selection.length)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.format(model.selection.end))
            }
            .font(.system(size: 12).monospacedDigit())

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Keep Original".localized(), action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isWorking {
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
            .disabled(model.isWorking)
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(minWidth: 620, minHeight: 440)
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
                    ForEach(RecordingExportFormat.allCases) { Text($0.title.localized()).tag($0) }
                }
                if settings.format.hasVideo {
                    Picker("Size".localized(), selection: $settings.size) {
                        ForEach(RecordingExportSize.allCases) { Text($0.title.localized()).tag($0) }
                    }
                }
                if settings.format == .gif {
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
            Button("Export".localized(), action: onExport)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 300)
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
                    .gesture(dragGesture(width: width) { selection.setStart($0); onScrub(selection.start) })
                    .accessibilityLabel(Text("Start".localized()))
                handle(systemImage: "chevron.compact.right")
                    .offset(x: endX - handleWidth / 2)
                    .gesture(dragGesture(width: width) { selection.setEnd($0); onScrub(selection.end) })
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
