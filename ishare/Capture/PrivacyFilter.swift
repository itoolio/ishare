import AppKit
import Defaults
@preconcurrency import ScreenCaptureKit

struct PrivacyWindow: Hashable, Sendable {
    var frame: CGRect
    var isSensitive: Bool
}

struct CaptureGeometry: Hashable, Sendable {
    var displayID: CGDirectDisplayID
    var region: CGRect
    var scale: CGFloat
    var displayOrigin: CGPoint

    var captureOrigin: CGPoint {
        CGPoint(x: displayOrigin.x + region.minX, y: displayOrigin.y + region.minY)
    }
}

enum PrivacyRedaction {
    static func imageRect(forGlobal frame: CGRect, captureOrigin: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(
            x: (frame.minX - captureOrigin.x) * scale,
            y: (frame.minY - captureOrigin.y) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }

    static func sensitiveMask(windows frontToBack: [PrivacyWindow], captureOrigin: CGPoint, scale: CGFloat, pixelSize: CGSize) -> CGImage? {
        let bounds = CGRect(origin: .zero, size: pixelSize)
        let mapped = frontToBack.map { window in
            (rect: imageRect(forGlobal: window.frame, captureOrigin: captureOrigin, scale: scale).intersection(bounds), window.isSensitive)
        }
        guard mapped.contains(where: { $0.1 && !$0.rect.isNull && !$0.rect.isEmpty }),
              let context = CGContext(
                  data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(bounds)
        for (rect, isSensitive) in mapped.reversed() where !rect.isNull && !rect.isEmpty {
            context.setFillColor(gray: isSensitive ? 1 : 0, alpha: 1)
            context.fill(ImageProcessing.ciRect(fromTopLeft: rect, imageHeight: pixelSize.height))
        }
        return context.makeImage()
    }

    static func menuBarCrop(region: CGRect, menuBarHeight: CGFloat, scale: CGFloat, pixelSize: CGSize) -> CGRect? {
        guard menuBarHeight > 0, region.minY < menuBarHeight, region.maxY > menuBarHeight else { return nil }
        let hiddenRows = ((menuBarHeight - region.minY) * scale).rounded(.up)
        guard hiddenRows > 0, hiddenRows < pixelSize.height else { return nil }
        return CGRect(x: 0, y: hiddenRows, width: pixelSize.width, height: pixelSize.height - hiddenRows)
    }

    static func redact(_ image: CGImage, windows frontToBack: [PrivacyWindow], captureOrigin: CGPoint, scale: CGFloat, blurRadius: CGFloat) -> CGImage {
        let pixelSize = CGSize(width: image.width, height: image.height)
        guard let mask = sensitiveMask(windows: frontToBack, captureOrigin: captureOrigin, scale: scale, pixelSize: pixelSize) else { return image }
        return ImageProcessing.blur(image, mask: mask, radius: blurRadius)
    }

    static func hideMenuBar(_ image: CGImage, region: CGRect, menuBarHeight: CGFloat, scale: CGFloat) -> CGImage {
        let pixelSize = CGSize(width: image.width, height: image.height)
        guard let crop = menuBarCrop(region: region, menuBarHeight: menuBarHeight, scale: scale, pixelSize: pixelSize) else { return image }
        return ImageProcessing.cropped(image, to: crop)
    }
}

@MainActor
enum PrivacyFilter {
    static let blurRadiusInPoints: CGFloat = 16

    static var sensitiveBundleIdentifiers: Set<String> {
        Set(Defaults[.blurredBundleIdentifiers])
    }

    static func windows(in content: SCShareableContent) -> [PrivacyWindow] {
        let sensitive = sensitiveBundleIdentifiers
        guard !sensitive.isEmpty else { return [] }
        let hidden = Set(ScreenshotEngine.excludedApplications(in: content).map(\.bundleIdentifier))
        let zOrder = ScreenshotEngine.windowZOrder()
        return content.windows
            .compactMap { window -> (SCWindow, Bool)? in
                guard window.isOnScreen, window.windowLayer >= 0, !window.frame.isEmpty,
                      let bundleID = window.owningApplication?.bundleIdentifier, !hidden.contains(bundleID)
                else { return nil }
                let isSensitive = sensitive.contains(bundleID)
                guard isSensitive || window.windowLayer == 0 else { return nil }
                return (window, isSensitive)
            }
            .sorted { (zOrder[$0.0.windowID] ?? .max) < (zOrder[$1.0.windowID] ?? .max) }
            .map { PrivacyWindow(frame: $0.0.frame, isSensitive: $0.1) }
    }

    static func geometry(displayID: CGDirectDisplayID, region: CGRect?, scale: CGFloat) -> CaptureGeometry {
        let bounds = CGDisplayBounds(displayID)
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let localRegion = region.map { ScreenGeometry.clamp($0, to: localBounds) } ?? localBounds
        return CaptureGeometry(displayID: displayID, region: localRegion, scale: scale, displayOrigin: bounds.origin)
    }

    static func geometry(displayID: CGDirectDisplayID, region: CGRect?, image: CGImage) -> CaptureGeometry {
        let base = geometry(displayID: displayID, region: region, scale: 1)
        return geometry(displayID: displayID, region: region, scale: CGFloat(image.width) / max(1, base.region.width))
    }

    static func redact(_ image: CGImage, geometry: CaptureGeometry, content: SCShareableContent) -> CGImage {
        let windows = windows(in: content)
        guard windows.contains(where: \.isSensitive) else { return image }
        return PrivacyRedaction.redact(
            image, windows: windows, captureOrigin: geometry.captureOrigin,
            scale: geometry.scale, blurRadius: blurRadiusInPoints * geometry.scale
        )
    }

    static func redactBackdrops(_ backdrops: [CGDirectDisplayID: CGImage], content: SCShareableContent) -> [CGDirectDisplayID: CGImage] {
        guard !sensitiveBundleIdentifiers.isEmpty else { return backdrops }
        return backdrops.reduce(into: [:]) { result, entry in
            let geometry = geometry(displayID: entry.key, region: nil, image: entry.value)
            result[entry.key] = redact(entry.value, geometry: geometry, content: content)
        }
    }

    static func redactWindow(_ image: CGImage, window: SCWindow, scale: CGFloat) -> CGImage {
        guard let bundleID = window.owningApplication?.bundleIdentifier, sensitiveBundleIdentifiers.contains(bundleID) else { return image }
        return ImageProcessing.blur(image, region: CGRect(x: 0, y: 0, width: image.width, height: image.height), radius: blurRadiusInPoints * scale)
    }

    static func menuBarHeight(for displayID: CGDirectDisplayID) -> CGFloat {
        guard let screen = NSScreen.screen(for: displayID) else { return 0 }
        return max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }

    static func hideMenuBarIfNeeded(_ image: CGImage, geometry: CaptureGeometry?) -> CGImage {
        guard Defaults[.hideMenuBarInCaptures], let geometry else { return image }
        return PrivacyRedaction.hideMenuBar(
            image, region: geometry.region,
            menuBarHeight: menuBarHeight(for: geometry.displayID), scale: geometry.scale
        )
    }
}
