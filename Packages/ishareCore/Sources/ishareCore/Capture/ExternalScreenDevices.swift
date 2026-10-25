import CoreGraphics
import Foundation

public enum ExternalScreenDeviceKind: String, Hashable, Sendable {
    case iPhone
    case iPad
}

public enum ExternalScreenOrientation: Hashable, Sendable {
    case portrait
    case landscape
}

public struct ExternalDeviceDescriptor: Hashable, Sendable {
    public var modelID: String
    public var manufacturer: String
    public var name: String
    public var isContinuityCamera: Bool
    public var providesMuxedMedia: Bool
    public var dimensions: CGSize?

    public init(modelID: String, manufacturer: String, name: String, isContinuityCamera: Bool = false, providesMuxedMedia: Bool, dimensions: CGSize? = nil) {
        self.modelID = modelID
        self.manufacturer = manufacturer
        self.name = name
        self.isContinuityCamera = isContinuityCamera
        self.providesMuxedMedia = providesMuxedMedia
        self.dimensions = dimensions
    }
}

public enum ExternalScreenDeviceClassifier {
    static let screenModelIDs = ["ios device", "ipados device"]

    public static func kind(of device: ExternalDeviceDescriptor) -> ExternalScreenDeviceKind? {
        guard !device.isContinuityCamera, device.manufacturer.lowercased().hasPrefix("apple") else { return nil }
        let model = device.modelID.lowercased()
        let name = device.name.lowercased()
        let isScreen = screenModelIDs.contains(model) || (device.providesMuxedMedia && (model.hasPrefix("iphone") || model.hasPrefix("ipad")))
        guard isScreen else { return nil }
        if model.contains("ipad") || name.contains("ipad") { return .iPad }
        if model.contains("iphone") || name.contains("iphone") { return .iPhone }
        guard let dimensions = device.dimensions, dimensions.width > 0, dimensions.height > 0 else { return .iPhone }
        let ratio = max(dimensions.width, dimensions.height) / min(dimensions.width, dimensions.height)
        return ratio < 1.6 ? .iPad : .iPhone
    }
}

public enum ExternalScreenGeometry {
    public static func orientation(of size: CGSize) -> ExternalScreenOrientation {
        size.width > size.height ? .landscape : .portrait
    }

    public static func outputSize(for size: CGSize) -> CGSize {
        ScreenGeometry.evenPixelSize(CGSize(width: max(2, size.width.rounded()), height: max(2, size.height.rounded())))
    }

    public static func fittedRect(for source: CGSize, in canvas: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = min(canvas.width / source.width, canvas.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }

    public static func needsLetterboxing(frame: CGSize, canvas: CGSize) -> Bool {
        abs(frame.width - canvas.width) > 0.5 || abs(frame.height - canvas.height) > 0.5
    }
}
