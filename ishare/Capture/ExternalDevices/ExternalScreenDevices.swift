import AVFoundation
import Combine
import CoreMediaIO
import Defaults
import Foundation
import ishareCore

struct ExternalScreenDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: ExternalScreenDeviceKind

    var recordTitle: String {
        switch kind {
        case .iPhone: "Record iPhone"
        case .iPad: "Record iPad"
        }
    }

    var screenshotTitle: String {
        switch kind {
        case .iPhone: "Capture iPhone Screenshot"
        case .iPad: "Capture iPad Screenshot"
        }
    }

    var symbol: String {
        switch kind {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        }
    }

    var fileSuffix: String {
        name.isEmpty ? kind.rawValue : name
    }
}

@MainActor
final class ExternalScreenDevices: ObservableObject {
    static let shared = ExternalScreenDevices()

    @Published private(set) var devices: [ExternalScreenDevice] = []

    private var discovery: AVCaptureDevice.DiscoverySession?
    private var observation: NSKeyValueObservation?
    private var notificationTokens: [any NSObjectProtocol] = []

    func start() {
        guard discovery == nil else { return }
        ExternalScreenCaptureSupport.allowScreenCaptureDevices()
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: nil, position: .unspecified)
        discovery = session
        observation = session.observe(\.devices, options: [.initial, .new]) { _, _ in
            Task { @MainActor in ExternalScreenDevices.shared.refresh() }
        }
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            notificationTokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in ExternalScreenDevices.shared.refresh() }
                })
        }
        refresh()
    }

    func refresh() {
        let found = (discovery?.devices ?? []).compactMap(Self.screenDevice(for:))
        if found != devices {
            if found.count != devices.count {
                Log.capture.info("Connected iPhone and iPad screens: \(found.count)")
            }
            devices = found
        }
    }

    func device(id: String) -> ExternalScreenDevice? {
        devices.first { $0.id == id }
    }

    nonisolated static func screenDevice(for device: AVCaptureDevice) -> ExternalScreenDevice? {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let descriptor = ExternalDeviceDescriptor(
            modelID: device.modelID,
            manufacturer: device.manufacturer,
            name: device.localizedName,
            isContinuityCamera: device.isContinuityCamera,
            providesMuxedMedia: device.hasMediaType(.muxed),
            dimensions: dimensions.width > 0 ? CGSize(width: Int(dimensions.width), height: Int(dimensions.height)) : nil
        )
        guard let kind = ExternalScreenDeviceClassifier.kind(of: descriptor) else { return nil }
        return ExternalScreenDevice(id: device.uniqueID, name: device.localizedName, kind: kind)
    }
}

enum ExternalScreenCaptureSupport {
    static func allowScreenCaptureDevices() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)
        if status != 0 {
            Log.capture.error("Allowing iPhone and iPad screen capture failed: \(status)")
        }
    }

    @MainActor static func requestAccess() async -> Bool {
        await CaptureDevices.requestAccess(for: .video)
    }

    @MainActor static func fileURL(for device: ExternalScreenDevice, ext: String, kind: SaveLocation.Kind) -> URL {
        let prefix = kind == .recordings ? Defaults[.recordingFileName] : Defaults[.captureFileName]
        return SaveLocation.fileURL(for: kind, fileName: CaptureFileName.make(prefix: prefix, suffix: device.fileSuffix, ext: ext))
    }
}
