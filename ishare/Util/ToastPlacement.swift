import AppKit
import Defaults

struct ToastScreenCandidate: Equatable, Sendable {
    let displayID: CGDirectDisplayID?
    let frame: CGRect
    let visibleFrame: CGRect
}

enum ToastPlacement {
    @MainActor static var capturedDisplayID: CGDirectDisplayID?

    static func frames(for heights: [CGFloat], width: CGFloat, in screen: CGRect, corner: ToastCorner, margin: CGFloat, spacing: CGFloat) -> [CGRect] {
        let x = corner.isLeading ? screen.minX + margin : screen.maxX - width - margin
        var edge = corner.isTop ? screen.maxY - margin : screen.minY + margin
        return heights.map { height in
            if corner.isTop {
                let frame = CGRect(x: x, y: edge - height, width: width, height: height)
                edge = frame.minY - spacing
                return frame
            }
            let frame = CGRect(x: x, y: edge, width: width, height: height)
            edge = frame.maxY + spacing
            return frame
        }
    }

    static func resolve(_ choice: ToastScreenChoice, screens: [ToastScreenCandidate], main: ToastScreenCandidate?, pointer: CGPoint, capturedDisplayID: CGDirectDisplayID?)
        -> ToastScreenCandidate?
    {
        let pointerScreen = screens.first { $0.frame.contains(pointer) }
        switch choice {
        case .main:
            return main ?? screens.first
        case .pointer:
            return pointerScreen ?? main ?? screens.first
        case .capturedContent:
            if let capturedDisplayID, let captured = screens.first(where: { $0.displayID == capturedDisplayID }) {
                return captured
            }
            return pointerScreen ?? main ?? screens.first
        }
    }

    @MainActor static func currentScreenFrame(choice: ToastScreenChoice = Defaults[.toastScreen]) -> CGRect {
        let candidates = NSScreen.screens.map(candidate(for:))
        let main = NSScreen.main.map(candidate(for:))
        return resolve(choice, screens: candidates, main: main, pointer: NSEvent.mouseLocation, capturedDisplayID: capturedDisplayID)?.visibleFrame ?? .zero
    }

    @MainActor private static func candidate(for screen: NSScreen) -> ToastScreenCandidate {
        ToastScreenCandidate(displayID: screen.displayID, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}
