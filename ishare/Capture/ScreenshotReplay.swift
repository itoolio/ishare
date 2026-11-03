import AppKit
import BezelNotification
import Defaults
import ImageIO
import ishareCore
import ScreenCaptureKit
import Synchronization
import SwiftUI
import UniformTypeIdentifiers
import VideoToolbox

final class ReplayFrameCollector: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
    static let maximumBytes = 400 * 1024 * 1024
    let queue = DispatchQueue(label: "dev.adrian.ishare.ScreenshotReplay")
    let displayID: CGDirectDisplayID
    private let ring: Mutex<FrameRing<Data>>

    init(displayID: CGDirectDisplayID, seconds: Double) {
        self.displayID = displayID
        ring = Mutex(FrameRing(maximumAge: seconds, maximumBytes: Self.maximumBytes))
    }

    var frames: [FrameRing<Data>.Entry] {
        ring.withLock { $0.entries }
    }

    func clear() {
        ring.withLock { $0.removeAll() }
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image, let data = Self.jpeg(image) else { return }
        let time = ProcessInfo.processInfo.systemUptime
        ring.withLock { $0.append(data, at: time, bytes: data.count) }
    }

    static func jpeg(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

@MainActor
final class ScreenshotReplay: ObservableObject {
    static let shared = ScreenshotReplay()
    static let framesPerSecond = 2.0

    @Published private(set) var isRunning = false
    private var stream: SCStream?
    private var collector: ReplayFrameCollector?
    private var conditions = InstantReplayConditions()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func activate() {
        guard !ScreenshotMode.isActive, !AutomationTestMode.isActive else { return }
        Task { await refresh() }
        Task {
            for await _ in Defaults.updates([.screenshotReplayEnabled, .screenshotReplaySeconds], initial: false) {
                await refresh()
            }
        }
    }

    func refresh() async {
        guard Defaults[.screenshotReplayEnabled], ScreenshotEngine.hasPermission else {
            stopMonitoring()
            await stop()
            return
        }
        startMonitoring()
        PowerSourceReader.read(into: &conditions)
        if conditions.shouldPause {
            await stop()
        } else if !isRunning {
            await start()
        }
    }

    private func start() async {
        guard let content = try? await ScreenshotEngine.shareableContent(),
            let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { return }
        let filter = SCContentFilter(display: display, excludingApplications: ScreenshotEngine.excludedApplications(in: content), exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.framesPerSecond))
        configuration.queueDepth = 3
        configuration.showsCursor = false
        let collector = ReplayFrameCollector(displayID: display.displayID, seconds: Double(Defaults[.screenshotReplaySeconds]))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
        do {
            try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: collector.queue)
            try await stream.startCapture()
            self.stream = stream
            self.collector = collector
            isRunning = true
            Log.capture.info("Screenshot replay started")
        } catch {
            Log.capture.error("Screenshot replay couldn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop() async {
        let active = stream
        stream = nil
        collector?.clear()
        collector = nil
        isRunning = false
        try? await active?.stopCapture()
    }

    private func startMonitoring() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked") { $0.isScreenLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.isScreenLocked = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.isAsleep = false }
    }

    private func stopMonitoring() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        conditions = InstantReplayConditions()
    }

    private func observe(_ center: NotificationCenter, _ name: String, update: @escaping @MainActor (inout InstantReplayConditions) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                update(&ScreenshotReplay.shared.conditions)
                Task { @MainActor in await ScreenshotReplay.shared.refresh() }
            }
        }
        observers.append((center, token))
    }

    func open() {
        guard let collector, !collector.frames.isEmpty else {
            BezelNotification.show(messageText: "Turn on Screenshot Replay in Capture settings first".localized(), icon: ToastIcon)
            return
        }
        let frames = collector.frames
        ScreenshotReplayWindow.show(
            frames: frames.map(\.frame), displayID: collector.displayID,
            age: { index in
                ProcessInfo.processInfo.systemUptime - frames[index].time
            })
    }
}

@MainActor
enum ScreenshotReplayWindow {
    private static var window: NSWindow?

    static func show(frames: [Data], displayID: CGDirectDisplayID, age: @escaping (Int) -> Double) {
        window?.close()
        let view = ScreenshotReplayView(frames: frames, age: age) { data, wholeFrame in
            window?.close()
            window = nil
            Task { @MainActor in await capture(data, displayID: displayID, wholeFrame: wholeFrame) }
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 860, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Screenshot Replay".localized()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    static func capture(_ data: Data, displayID: CGDirectDisplayID, wholeFrame: Bool) async {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let frame = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let screen = NSScreen.screen(for: displayID)
        else { return }
        let scale = CGFloat(frame.width) / max(1, screen.frame.width)
        if wholeFrame {
            await CaptureSession.deliverCapture(CapturedImage(image: frame, suffix: "replay", pointScale: scale), options: .standard)
            return
        }
        let selection = await RegionSelector.selectRegions(
            options: RegionSelector.Options(backdrops: [displayID: frame], allowsWindowMode: false, hint: "Select the area to keep".localized()))
        guard case let .single(.region(chosen, rect)) = selection, chosen.displayID == displayID,
            let cropped = ScreenshotEngine.crop(frame, toPoints: rect, scale: scale)
        else { return }
        await CaptureSession.deliverCapture(CapturedImage(image: cropped, suffix: "replay", pointScale: scale), options: .standard)
    }
}

struct ScreenshotReplayView: View {
    let frames: [Data]
    let age: (Int) -> Double
    let choose: (Data, Bool) -> Void
    @State private var index: Double

    init(frames: [Data], age: @escaping (Int) -> Double, choose: @escaping (Data, Bool) -> Void) {
        self.frames = frames
        self.age = age
        self.choose = choose
        _index = State(initialValue: Double(max(0, frames.count - 1)))
    }

    private var selected: Int { min(max(0, Int(index.rounded())), frames.count - 1) }

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(data: frames[selected]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(String(format: "Frame from %.0f seconds ago".localized(), age(selected)))
            }
            HStack {
                Text(String(format: "%.0f s ago".localized(), age(selected)))
                    .monospacedDigit()
                    .frame(width: 80, alignment: .leading)
                Slider(value: $index, in: 0 ... Double(max(1, frames.count - 1)), step: 1)
            }
            HStack {
                Spacer()
                Button("Use Whole Screen".localized()) { choose(frames[selected], true) }
                Button("Select Area…".localized()) { choose(frames[selected], false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 460)
    }
}
