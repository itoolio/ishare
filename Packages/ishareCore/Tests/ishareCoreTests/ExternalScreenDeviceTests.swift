import CoreGraphics
import Foundation
import Testing
@testable import ishareCore

struct ExternalScreenDeviceTests {
    private func device(model: String = "iOS Device", maker: String = "Apple Inc.", name: String, continuity: Bool = false, muxed: Bool = true, size: CGSize? = nil)
        -> ExternalDeviceDescriptor
    {
        ExternalDeviceDescriptor(modelID: model, manufacturer: maker, name: name, isContinuityCamera: continuity, providesMuxedMedia: muxed, dimensions: size)
    }

    @Test func recognizesIPhonesAndIPadsByName() {
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Adrian’s iPhone")) == .iPhone)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Studio iPad Pro")) == .iPad)
    }

    @Test func fallsBackToTheAspectRatio() {
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Living Room", size: CGSize(width: 1640, height: 2360))) == .iPad)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Pocket", size: CGSize(width: 1179, height: 2556))) == .iPhone)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Pocket", size: CGSize(width: 2556, height: 1179))) == .iPhone)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(name: "Unknown")) == .iPhone)
    }

    @Test func ignoresCamerasAndOtherDevices() {
        #expect(ExternalScreenDeviceClassifier.kind(of: device(model: "iPhone15,2", name: "Adrian’s iPhone Camera", continuity: true)) == nil)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(model: "UVC Camera VendorID_1133", maker: "Logitech", name: "C920")) == nil)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(model: "Capture Card", maker: "Apple Inc.", name: "Something", muxed: true)) == nil)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(model: "iPad13,4", name: "iPad", muxed: false)) == nil)
        #expect(ExternalScreenDeviceClassifier.kind(of: device(model: "iPad13,4", name: "Studio", muxed: true)) == .iPad)
    }

    @Test func derivesTheOrientationFromTheFrame() {
        #expect(ExternalScreenGeometry.orientation(of: CGSize(width: 886, height: 1920)) == .portrait)
        #expect(ExternalScreenGeometry.orientation(of: CGSize(width: 1920, height: 886)) == .landscape)
        #expect(ExternalScreenGeometry.orientation(of: CGSize(width: 100, height: 100)) == .portrait)
    }

    @Test func keepsTheNativeSizeWithEvenDimensions() {
        #expect(ExternalScreenGeometry.outputSize(for: CGSize(width: 1179, height: 2556)) == CGSize(width: 1180, height: 2556))
        #expect(ExternalScreenGeometry.outputSize(for: CGSize(width: 886, height: 1920)) == CGSize(width: 886, height: 1920))
    }

    @Test func letterboxesARotatedFrameIntoTheCanvas() {
        let canvas = CGSize(width: 1000, height: 2000)
        let rect = ExternalScreenGeometry.fittedRect(for: CGSize(width: 2000, height: 1000), in: canvas)
        #expect(rect == CGRect(x: 0, y: 750, width: 1000, height: 500))
        #expect(ExternalScreenGeometry.fittedRect(for: canvas, in: canvas) == CGRect(origin: .zero, size: canvas))
        #expect(ExternalScreenGeometry.needsLetterboxing(frame: CGSize(width: 2000, height: 1000), canvas: canvas))
        #expect(!ExternalScreenGeometry.needsLetterboxing(frame: canvas, canvas: canvas))
    }
}
