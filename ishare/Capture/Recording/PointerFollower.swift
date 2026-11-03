import AppKit
import ishareCore

@MainActor
final class PointerFollower {
    static let tickInterval: TimeInterval = 1.0 / 30

    private let screen: NSScreen
    private let engine: CaptureEngine
    private var camera: PointerFollowCamera
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    init(screen: NSScreen, size: CGSize, engine: CaptureEngine) {
        self.screen = screen
        self.engine = engine
        camera = PointerFollowCamera(display: screen.frame.size, size: size, centeredAt: Self.pointer(on: screen))
    }

    var rect: CGRect {
        camera.rect
    }

    func start() {
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        if camera.step(toward: Self.pointer(on: screen), elapsed: elapsed) {
            engine.moveSourceRect(to: camera.rect)
        }
    }

    static func pointer(on screen: NSScreen) -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x - screen.frame.minX, y: screen.frame.maxY - location.y)
    }
}
