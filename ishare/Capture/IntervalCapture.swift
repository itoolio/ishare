import AppKit
import BezelNotification
import Defaults
import ImageIO
import KeyboardShortcuts
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum CaptureInterval: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case one = 1
    case two = 2
    case five = 5
    case ten = 10
    case thirty = 30

    var id: Self { self }

    var title: String {
        String(format: "%d s".localized(), rawValue)
    }
}

enum IntervalStopMode: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case frameCount
    case duration

    var id: Self { self }

    var title: String {
        switch self {
        case .frameCount: "Number of frames"
        case .duration: "Duration"
        }
    }
}

struct IntervalPlan: Hashable, Sendable {
    static let frameCountRange = 2 ... 500
    static let durationChoices = [30, 60, 120, 300, 600, 1800, 3600]

    var interval: Int
    var stopMode: IntervalStopMode
    var frameCount: Int
    var duration: Int

    var plannedFrames: Int {
        switch stopMode {
        case .frameCount:
            min(max(frameCount, Self.frameCountRange.lowerBound), Self.frameCountRange.upperBound)
        case .duration:
            max(1, max(0, duration) / max(1, interval) + 1)
        }
    }

    func offset(ofFrame index: Int) -> Duration {
        .seconds(index * max(1, interval))
    }

    static func folderName(prefix: String, date: Date) -> String {
        let sanitized = CaptureFileName.sanitize(prefix)
        return "\(sanitized.isEmpty ? "ishare" : sanitized)-interval-\(Int(date.timeIntervalSince1970))"
    }

    static func frameName(index: Int, ext: String) -> String {
        String(format: "frame-%04d.%@", index + 1, ext.lowercased())
    }

    static func durationTitle(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    @MainActor static var current: IntervalPlan {
        IntervalPlan(
            interval: Defaults[.intervalCaptureInterval].rawValue,
            stopMode: Defaults[.intervalCaptureStopMode],
            frameCount: Defaults[.intervalCaptureFrameCount],
            duration: Defaults[.intervalCaptureDuration]
        )
    }
}

struct IntervalCaptureResult: Sendable {
    var folder: URL
    var frames: [URL]
    var gif: URL?
}

enum IntervalGIF {
    static let frameDelay = 0.5
    static let maximumPixelSize = 1200

    static func write(frames: [URL], to destination: URL, frameDelay: Double = frameDelay, maximumPixelSize: Int = maximumPixelSize) throws {
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ImageEncoderError.destinationUnavailable
        }
        let loop = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(output, loop as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]]
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        var added = 0
        for frame in frames {
            guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            else { continue }
            CGImageDestinationAddImage(output, image, frameProperties as CFDictionary)
            added += 1
        }
        guard added == frames.count, CGImageDestinationFinalize(output) else { throw ImageEncoderError.finalizeFailed }
    }
}

@MainActor
final class IntervalCaptureModel: ObservableObject {
    @Published var captured = 0
    @Published var planned: Int
    @Published var stopped = false

    init(planned: Int) {
        self.planned = planned
    }
}

struct IntervalCaptureHUD: View {
    @ObservedObject var model: IntervalCaptureModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Interval capture".localized())
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: "%d of %d frames".localized(), model.captured, model.planned))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Stop".localized()) { model.stopped = true }
                .keyboardShortcut(.cancelAction)
                .adaptiveGlassButtonStyle(prominent: true)
                .accessibilityIdentifier("interval.stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300)
        .adaptiveGlass(cornerRadius: 16)
    }
}

@MainActor
enum IntervalCapture {
    private static var model: IntervalCaptureModel?

    static var isRunning: Bool {
        model != nil
    }

    static func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .intervalCapture) {
            Task { @MainActor in
                await toggle()
            }
        }
    }

    static func toggle() async {
        if isRunning {
            stop()
        } else {
            await start()
        }
    }

    static func stop() {
        model?.stopped = true
    }

    @discardableResult
    static func start(plan: IntervalPlan = .current, makesGIF: Bool = Defaults[.intervalCaptureMakesGIF]) async -> IntervalCaptureResult? {
        guard !isRunning, ScreenshotEngine.ensurePermission() else { return nil }
        let outcome = await RegionSelector.select(options: .init(
            showsMagnifier: Defaults[.showMagnifier], allowsWindowMode: false,
            hint: "Select an area, or press Return for the whole screen".localized()
        ))
        let target: (screen: NSScreen, region: CGRect?)
        switch outcome {
        case let .region(screen, rect): target = (screen, rect)
        case let .fullScreen(screen): target = (screen, nil)
        case .switchToWindow, .cancelled: return nil
        }
        guard let displayID = target.screen.displayID else { return nil }

        let model = IntervalCaptureModel(planned: plan.plannedFrames)
        self.model = model
        let overlays = showOverlays(model: model, screen: target.screen, region: target.region)
        defer {
            overlays.forEach { $0.orderOut(nil) }
            self.model = nil
        }

        do {
            let result = try await run(plan: plan, displayID: displayID, region: target.region, model: model, makesGIF: makesGIF)
            announce(result)
            return result
        } catch {
            Log.capture.error("Interval capture failed: \(error.localizedDescription, privacy: .public)")
            BezelNotification.show(messageText: "Capture failed".localized(), icon: ToastIcon)
            return nil
        }
    }

    private static func run(plan: IntervalPlan, displayID: CGDirectDisplayID, region: CGRect?, model: IntervalCaptureModel, makesGIF: Bool) async throws -> IntervalCaptureResult? {
        let start = Date()
        let folder = SaveLocation.directory(for: .captures)
            .appending(path: IntervalPlan.folderName(prefix: Defaults[.captureFileName], date: start), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileType = Defaults[.captureFileType] == .PDF ? FileType.PNG : Defaults[.captureFileType]
        let clock = ContinuousClock()
        let startInstant = clock.now
        var frames: [URL] = []

        for index in 0 ..< plan.plannedFrames {
            let deadline = startInstant + plan.offset(ofFrame: index)
            while clock.now < deadline, !model.stopped {
                try await Task.sleep(for: min(.milliseconds(100), deadline - clock.now))
            }
            guard !model.stopped else { break }
            let frameURL = folder.appending(path: IntervalPlan.frameName(index: index, ext: fileType.rawValue))
            try await captureFrame(displayID: displayID, region: region, fileType: fileType, to: frameURL)
            frames.append(frameURL)
            model.captured = frames.count
        }

        guard !frames.isEmpty else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        var gif: URL?
        if makesGIF, frames.count > 1 {
            let gifURL = folder.appending(path: folder.lastPathComponent + ".gif")
            do {
                try IntervalGIF.write(frames: frames, to: gifURL)
                gif = gifURL
            } catch {
                Log.capture.error("Interval GIF failed: \(error.localizedDescription, privacy: .public)")
                BezelNotification.show(messageText: "GIF export failed".localized(), icon: ToastIcon)
            }
        }
        return IntervalCaptureResult(folder: folder, frames: frames, gif: gif)
    }

    private static func captureFrame(displayID: CGDirectDisplayID, region: CGRect?, fileType: FileType, to url: URL) async throws {
        let content = try await ScreenshotEngine.shareableContent()
        let captured = try await ImageCaptureFlow.captureDisplayImage(displayID: displayID, region: region, content: content, suffix: nil)
        let image = PrivacyFilter.hideMenuBarIfNeeded(captured.image, geometry: captured.geometry)
        try ImageEncoder.write(image, as: fileType, to: url)
    }

    private static func showOverlays(model: IntervalCaptureModel, screen: NSScreen, region: CGRect?) -> [NSWindow] {
        let localRect = region ?? CGRect(origin: .zero, size: screen.frame.size)
        let globalRect = CGRect(
            x: screen.frame.minX + localRect.minX,
            y: screen.frame.maxY - localRect.maxY,
            width: localRect.width, height: localRect.height
        )
        var windows: [NSWindow] = []
        if region != nil {
            windows.append(RegionOverlay.borderWindow(around: globalRect))
        }
        let hud = RegionOverlay.hudWindow(IntervalCaptureHUD(model: model), near: globalRect, on: screen)
        windows.append(hud)
        windows.forEach { $0.orderFrontRegardless() }
        hud.makeKey()
        return windows
    }

    private static func announce(_ result: IntervalCaptureResult?) {
        guard let result else { return }
        SoundPlayer.play(.capture)
        BezelNotification.show(messageText: String(format: "Saved %d frames".localized(), result.frames.count), icon: ToastIcon)
        if Defaults[.openInFinder] {
            NSWorkspace.shared.activateFileViewerSelecting([result.gif ?? result.folder])
        }
    }
}
