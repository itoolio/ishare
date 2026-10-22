@preconcurrency import AppKit
@preconcurrency import AVFoundation
import Defaults

enum WebcamBubbleSize: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case small
    case medium
    case large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var diameter: CGFloat {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 260
        }
    }
}

enum WebcamCorner: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

enum WebcamBubbleLayout {
    static let inset: CGFloat = 24
    static let minimumDiameter: CGFloat = 64

    static func frame(diameter: CGFloat, corner: WebcamCorner, in area: CGRect) -> CGRect {
        let available = min(area.width, area.height) - inset * 2
        let side = max(min(diameter, available), min(minimumDiameter, max(available, 0)))
        let x = switch corner {
        case .topLeft, .bottomLeft: area.minX + inset
        case .topRight, .bottomRight: area.maxX - inset - side
        }
        let y = switch corner {
        case .bottomLeft, .bottomRight: area.minY + inset
        case .topLeft, .topRight: area.maxY - inset - side
        }
        return CGRect(x: x, y: y, width: side, height: side)
    }
}

enum CaptureDevices {
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external], mediaType: .video, position: .unspecified).devices
    }

    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    static func camera(id: String?) -> AVCaptureDevice? {
        id.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .video)
    }

    static func microphone(id: String?) -> AVCaptureDevice? {
        id.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio)
    }

    static func connectedMicrophoneID(_ id: String?) -> String? {
        guard let id, AVCaptureDevice(uniqueID: id)?.isConnected == true else { return nil }
        return id
    }

    static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: mediaType)
        default: false
        }
    }
}

final class CaptureSessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.adrian.ishare.CaptureSessionRunner")

    func start() {
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }
}

private final class WebcamBubbleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class WebcamBubbleController {
    private var panel: NSPanel?
    private var runner: CaptureSessionRunner?

    var windowID: CGWindowID? {
        panel.map { CGWindowID($0.windowNumber) }
    }

    func show(in area: CGRect) async {
        hide()
        guard await CaptureDevices.requestAccess(for: .video) else {
            Log.capture.info("Webcam bubble skipped because camera access isn't allowed")
            return
        }
        guard let device = CaptureDevices.camera(id: Defaults[.webcamDeviceID]),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            Log.capture.error("No camera is available for the webcam bubble")
            return
        }

        let runner = CaptureSessionRunner()
        runner.session.beginConfiguration()
        runner.session.sessionPreset = .high
        guard runner.session.canAddInput(input) else {
            runner.session.commitConfiguration()
            return
        }
        runner.session.addInput(input)
        runner.session.commitConfiguration()

        let frame = WebcamBubbleLayout.frame(diameter: Defaults[.webcamSize].diameter, corner: Defaults[.webcamCorner], in: area)
        let panel = makePanel(frame: frame, session: runner.session)
        panel.orderFrontRegardless()
        runner.start()
        self.runner = runner
        self.panel = panel
    }

    func hide() {
        runner?.stop()
        runner = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel(frame: CGRect, session: AVCaptureSession) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .recordingBubble
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let view = WebcamBubbleView(frame: CGRect(origin: .zero, size: frame.size))
        let container = CALayer()
        container.frame = view.bounds
        container.cornerRadius = frame.width / 2
        container.masksToBounds = true
        container.borderWidth = 3
        container.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        container.backgroundColor = NSColor.black.cgColor

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = container.bounds
        preview.videoGravity = .resizeAspectFill
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        container.insertSublayer(preview, at: 0)
        view.layer = container
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }
}
