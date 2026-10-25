import AppKit
import ishareCore
@preconcurrency import ScreenCaptureKit

@MainActor
final class LiveMagnifierSampler {
    struct Sample {
        let image: CGImage
        let pixelOrigin: CGPoint
        let displayID: CGDirectDisplayID
    }

    struct Request {
        let displayID: CGDirectDisplayID
        let pixel: CGPoint
        let scale: CGFloat
    }

    private static let samplePadding = 4

    private let displays: [CGDirectDisplayID: SCDisplay]
    private let excludedApplications: [SCRunningApplication]
    private var throttle = SamplingThrottle()
    private var pending: Request?
    private var scheduled: Task<Void, Never>?
    private var isStopped = false
    var onSample: ((Sample) -> Void)?

    init(content: SCShareableContent) {
        displays = Dictionary(content.displays.map { ($0.displayID, $0) }, uniquingKeysWith: { first, _ in first })
        excludedApplications = ScreenshotEngine.excludedApplications(in: content)
    }

    var isAvailable: Bool {
        !throttle.isDisabled && !isStopped
    }

    func request(_ request: Request) {
        guard isAvailable, displays[request.displayID] != nil else { return }
        pending = request
        schedule()
    }

    func stop() {
        isStopped = true
        pending = nil
        scheduled?.cancel()
        scheduled = nil
        onSample = nil
    }

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func schedule() {
        guard scheduled == nil, let delay = throttle.delayBeforeNextRequest(at: now) else { return }
        scheduled = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.fire()
        }
    }

    private func fire() async {
        scheduled = nil
        guard isAvailable, let request = pending, let display = displays[request.displayID] else { return }
        pending = nil
        throttle.begin(at: now)
        let samples = MagnifierLayout.sampleCount + Self.samplePadding * 2
        let half = CGFloat(samples / 2)
        let scale = max(request.scale, 1)
        let requested = CGRect(
            x: (request.pixel.x - half) / scale, y: (request.pixel.y - half) / scale, width: CGFloat(samples) / scale, height: CGFloat(samples) / scale)
        let sourceRect = ScreenGeometry.clamp(requested, to: CGRect(x: 0, y: 0, width: display.width, height: display.height))
        guard ScreenGeometry.isMeaningfulSelection(sourceRect, minimum: 1 / scale) else {
            throttle.fail()
            return
        }
        let pixelOrigin = CGPoint(x: (sourceRect.minX * scale).rounded(), y: (sourceRect.minY * scale).rounded())
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
        let configuration = ScreenshotEngine.baseConfiguration(
            pixelSize: CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale), showsCursor: false)
        configuration.sourceRect = sourceRect
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            throttle.finish(at: now)
            guard !isStopped else { return }
            onSample?(Sample(image: image, pixelOrigin: pixelOrigin, displayID: request.displayID))
        } catch {
            throttle.fail()
        }
        if pending != nil {
            schedule()
        }
    }
}
