import AppKit
import CoreImage
import Defaults
import ishareCore

struct SpotlightCapture: Sendable {
    var samples: [SpotlightSample]
    var sourceSize: CGSize
    var style: SpotlightStyle

    static var isRequested: Bool {
        Defaults[.spotlightActiveWindow]
    }

    static var currentStyle: SpotlightStyle {
        SpotlightStyle(dimming: Defaults[.spotlightDimming], blursBackground: Defaults[.spotlightBlursBackground])
    }

    func plan(recordingStart: Double, videoSize: CGSize, pauses: RecordingPauseTimeline) -> SpotlightPlan? {
        let sourceRect = CGRect(origin: .zero, size: sourceSize)
        let mapped = samples.map { sample in
            SpotlightSample(
                time: pauses.recordedDuration(from: recordingStart, to: sample.time),
                windowID: sample.windowID,
                frame: sample.frame
                    .flatMap { SpotlightGeometry.videoRect(windowFrame: $0, sourceRect: sourceRect, videoSize: videoSize) }
                    .map { SpotlightGeometry.flipped($0, videoHeight: videoSize.height) }
            )
        }
        let timeline = SpotlightTimeline(samples: mapped)
        return timeline.isEmpty ? nil : SpotlightPlan(timeline: timeline, style: style)
    }
}

struct SpotlightPlan: Hashable, Sendable {
    var timeline: SpotlightTimeline
    var style: SpotlightStyle
}

@MainActor
struct FocusedWindowSampler {
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func sample(at time: Double, sourceRect: CGRect) -> SpotlightSample {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let windows = Self.onScreenWindows().filter { $0.ownerPID != ownPID }
        guard let window = FocusedWindowPicker.focusedWindow(in: windows, frontmostPID: frontmost) else {
            return SpotlightSample(time: time, windowID: nil, frame: nil)
        }
        let relative = window.frame.offsetBy(dx: -sourceRect.minX, dy: -sourceRect.minY)
        return SpotlightSample(time: time, windowID: window.id, frame: relative)
    }

    static func onScreenWindows() -> [WindowDescriptor] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return WindowDescriptor(
                id: id,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                frame: frame,
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? true,
                ownerPID: (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                ownerBundleID: nil
            )
        }
    }
}

enum SpotlightRenderer {
    static let blurRadius: Double = 14

    static func apply(_ plan: SpotlightPlan?, to image: CIImage, time: Double, videoSize: CGSize) -> CIImage {
        guard let plan, let frame = plan.timeline.frame(at: time) else { return image }
        let extent = CGRect(origin: .zero, size: videoSize)
        var background = image
        if plan.style.blursBackground {
            background = image.clampedToExtent().applyingGaussianBlur(sigma: blurRadius * frame.strength).cropped(to: extent)
        }
        let shade = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: plan.style.dimming * frame.strength)).cropped(to: extent)
        background = shade.composited(over: background)
        let mask = CIImage(color: .white).cropped(to: frame.rect.integral).composited(over: CIImage(color: .black).cropped(to: extent))
        return image.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask]
        ).cropped(to: extent)
    }
}
