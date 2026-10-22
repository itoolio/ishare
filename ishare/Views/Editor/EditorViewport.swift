import AppKit
import Combine

@MainActor
final class EditorViewport: ObservableObject {
    @Published private(set) var zoom: CGFloat?
    @Published private(set) var center: CGPoint?
    @Published private(set) var containerSize: CGSize = .zero
    @Published private(set) var visibleRect: CGRect
    let backingScale: CGFloat

    init(visibleRect: CGRect, backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) {
        self.visibleRect = visibleRect
        self.backingScale = max(1, backingScale)
    }

    var isFit: Bool { zoom == nil }

    var fitZoom: CGFloat {
        CanvasTransform.fitScale(for: visibleRect.size, in: containerSize, backingScale: backingScale) * backingScale
    }

    var effectiveZoom: CGFloat { zoom ?? fitZoom }

    var percentage: Int { Int((effectiveZoom * 100).rounded()) }

    var transform: CanvasTransform {
        .make(visibleRect: visibleRect, container: containerSize, scale: effectiveZoom / backingScale, center: zoom == nil ? nil : center)
    }

    private var containerCenter: CGPoint {
        CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
    }

    func update(containerSize size: CGSize) {
        guard size != containerSize else { return }
        containerSize = size
    }

    func update(visibleRect rect: CGRect) {
        guard rect != visibleRect else { return }
        visibleRect = rect
        center = nil
    }

    func setZoom(_ value: CGFloat, anchor: CGPoint? = nil) {
        let clamped = CanvasTransform.clampZoom(value)
        let next = transform.zoomed(to: clamped / backingScale, anchor: anchor ?? containerCenter, in: containerSize)
        zoom = clamped
        center = next.center(in: containerSize)
    }

    func zoomIn() {
        setZoom(CanvasTransform.zoomIn(from: effectiveZoom))
    }

    func zoomOut() {
        setZoom(CanvasTransform.zoomOut(from: effectiveZoom))
    }

    func fit() {
        zoom = nil
        center = nil
    }

    func actualSize() {
        setZoom(1)
    }

    func pan(by delta: CGVector) {
        guard zoom != nil else { return }
        center = transform.panned(by: delta, in: containerSize).center(in: containerSize)
    }
}
