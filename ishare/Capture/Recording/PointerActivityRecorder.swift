import AppKit
import Defaults

@MainActor
final class PointerActivityRecorder {
    static let sampleRate: Double = 30
    private static let sourceRefreshInterval: Double = 0.5

    private let monitor = InputEventMonitor()
    private var log = PointerActivityLog()
    private var source: OverlaySource?
    private var cachedRect: CGRect?
    private var cachedRectTime: Double = 0
    private var timer: Timer?
    private var pointerSettings = PointerEffectSettings()
    private var autoZoom: AutoZoomSettings?

    var isSuspended: () -> Bool = { false }

    private(set) var isActive = false

    static var isRequested: Bool {
        Defaults[.autoZoomEnabled] || PointerEffectSettings.current.isActive
    }

    func start(source: OverlaySource) {
        _ = stop()
        log = PointerActivityLog()
        pointerSettings = .current
        autoZoom = Defaults[.autoZoomEnabled] ? .current : nil
        guard pointerSettings.isActive || autoZoom != nil else { return }
        self.source = source
        isActive = true
        monitor.onClick = { [weak self] in self?.recordClick(atCocoaPoint: $0) }
        monitor.startClicks()
        if autoZoom != nil, Defaults[.autoZoomOnTyping] {
            monitor.onKey = { [weak self] in self?.recordKey($0) }
            if !monitor.startKeys() {
                Log.capture.info("Typing isn't used for auto zoom because Input Monitoring isn't allowed")
            }
        }
        let timer = Timer(timeInterval: 1 / Self.sampleRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func update(source: OverlaySource) {
        self.source = source
        cachedRect = nil
    }

    func stop() -> RecordingEffectsCapture? {
        timer?.invalidate()
        timer = nil
        monitor.stop()
        monitor.onClick = nil
        monitor.onKey = nil
        let wasActive = isActive
        isActive = false
        defer {
            log = PointerActivityLog()
            source = nil
            cachedRect = nil
        }
        guard wasActive, let source, !log.isEmpty else { return nil }
        return RecordingEffectsCapture(log: log, contentSize: source.contentSize, pointer: pointerSettings, autoZoom: autoZoom)
    }

    private func currentRect(at time: Double) -> CGRect? {
        if let cachedRect, time - cachedRectTime < Self.sourceRefreshInterval { return cachedRect }
        cachedRect = source?.currentRect()
        cachedRectTime = time
        return cachedRect
    }

    private func globalPoint(fromCocoa point: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return OverlayCoordinateMapper.cgGlobalPoint(fromCocoa: point, primaryScreenHeight: primaryHeight)
    }

    private func sample() {
        let time = RecordingClock.now
        guard let rect = currentRect(at: time) else { return }
        log.recordSample(at: globalPoint(fromCocoa: NSEvent.mouseLocation), sourceRect: rect, time: time)
    }

    private func recordClick(atCocoaPoint point: CGPoint) {
        guard !isSuspended() else { return }
        let time = RecordingClock.now
        guard let rect = currentRect(at: time) else { return }
        log.recordClick(at: globalPoint(fromCocoa: point), sourceRect: rect, time: time)
    }

    private func recordKey(_ event: RawKeyEvent) {
        guard !event.isRepeat, !isSuspended() else { return }
        log.recordKey(time: RecordingClock.now)
    }
}
