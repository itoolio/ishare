import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private weak var statusItem: NSStatusItem?
    private weak var dropView: StatusItemDropView?
    private var baseImage: NSImage?
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var cancellables: Set<AnyCancellable> = []
    private(set) var isDropTargeted = false

    override private init() {
        super.init()
        UploadManager.shared.$activity
            .removeDuplicates()
            .sink { [weak self] activity in
                self?.render(activity)
            }
            .store(in: &cancellables)
    }

    func attach(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        statusItem = item
        button.setAccessibilityIdentifier("statusItem")
        if dropView?.superview !== button {
            dropView?.removeFromSuperview()
            let view = StatusItemDropView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            view.controller = self
            button.addSubview(view)
            dropView = view
        }
        if let window = button.window {
            window.registerForDraggedTypes(ExternalUpload.draggedTypes)
            if window.delegate == nil || window.delegate === self {
                window.delegate = self
            }
        }
        render(UploadManager.shared.activity)
    }

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        statusItem?.button?.highlight(targeted || MenuController.shared.isPresented)
    }

    private func render(_ activity: UploadActivity) {
        guard let button = statusItem?.button else { return }
        switch activity {
        case .idle:
            stopAnimating()
            if let baseImage {
                button.image = baseImage
                self.baseImage = nil
            }
        case let .uploading(progress):
            captureBaseImage(from: button)
            startAnimating()
            button.image = StatusIconRenderer.uploading(base: baseImage, progress: progress, phase: animationPhase)
        case let .finished(succeeded):
            stopAnimating()
            captureBaseImage(from: button)
            button.image = StatusIconRenderer.result(succeeded: succeeded, template: baseImage?.isTemplate ?? true)
        }
    }

    private func captureBaseImage(from button: NSStatusBarButton) {
        if baseImage == nil {
            baseImage = button.image
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { _ in
            Task { @MainActor in
                StatusItemController.shared.advanceAnimation()
            }
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationPhase = 0
    }

    private func advanceAnimation() {
        guard case let .uploading(progress) = UploadManager.shared.activity, let button = statusItem?.button else { return }
        animationPhase = (animationPhase + 0.05).truncatingRemainder(dividingBy: 1)
        button.image = StatusIconRenderer.uploading(base: baseImage, progress: progress, phase: animationPhase)
    }

    fileprivate func handleDragEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard ExternalUpload.payload(from: sender.draggingPasteboard) != nil else { return [] }
        setDropTargeted(true)
        return .copy
    }

    fileprivate func handleDragExited() {
        setDropTargeted(false)
    }

    fileprivate func handleDrop(_ sender: any NSDraggingInfo) -> Bool {
        setDropTargeted(false)
        guard let payload = ExternalUpload.payload(from: sender.draggingPasteboard) else { return false }
        Task { @MainActor in
            await ExternalUpload.upload(payload)
        }
        return true
    }
}

extension StatusItemController: NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handleDragEntered(sender)
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDropTargeted ? .copy : []
    }

    func draggingExited(_: (any NSDraggingInfo)?) {
        handleDragExited()
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        handleDrop(sender)
    }

    func draggingEnded(_: any NSDraggingInfo) {
        if isDropTargeted {
            setDropTargeted(false)
        }
    }
}

final class StatusItemDropView: NSView {
    weak var controller: StatusItemController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(ExternalUpload.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.handleDragEntered(sender) ?? []
    }

    override func draggingUpdated(_: any NSDraggingInfo) -> NSDragOperation {
        controller?.isDropTargeted == true ? .copy : []
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        controller?.handleDragExited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.handleDrop(sender) ?? false
    }
}

enum StatusIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    static func uploading(base: NSImage?, progress: Double, phase: CGFloat) -> NSImage {
        let template = base?.isTemplate ?? true
        let image = NSImage(size: size, flipped: false) { rect in
            let color = template ? NSColor.black : NSColor.labelColor
            let ringRect = rect.insetBy(dx: 1.2, dy: 1.2)
            let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
            let radius = ringRect.width / 2
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = 1.6
            color.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let arc = NSBezierPath()
            let clamped = min(max(progress, 0), 1)
            if clamped > 0.02 {
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
            } else {
                let start = 90 - 360 * phase
                arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - 90, clockwise: true)
            }
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()

            if let base {
                let inner = rect.insetBy(dx: 4.5, dy: 4.5)
                base.draw(in: fitted(base.size, in: inner), from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                let arrow = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
                arrow?.draw(in: rect.insetBy(dx: 5, dy: 5))
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Uploading".localized()
        return image
    }

    static func result(succeeded: Bool, template: Bool) -> NSImage {
        let name = succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: succeeded ? "Upload complete".localized() : "Upload failed".localized())?
            .withSymbolConfiguration(configuration) ?? NSImage(size: size)
        symbol.isTemplate = template
        return symbol
    }

    static func fitted(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}
