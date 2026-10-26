import AppKit

final class SelectionPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum KeyCode {
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
}

@MainActor
enum SelectionStyle {
    static let dimColor = NSColor.black.withAlphaComponent(0.35)
    static let borderColor = NSColor.white
    static var accentColor: NSColor { .controlAccentColor }

    private static let pillPadding = CGSize(width: 8, height: 4)

    private static func pillString(_ text: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func drawPill(_ text: String, near anchor: CGPoint, in bounds: CGRect, above: Bool = true) {
        let string = pillString(text)
        let textSize = string.size()
        let frame = CGRect(
            x: anchor.x, y: above ? anchor.y + 6 : anchor.y - textSize.height - pillPadding.height * 2 - 6,
            width: textSize.width + pillPadding.width * 2, height: textSize.height + pillPadding.height * 2
        )
        drawPill(string, in: frame, clampedTo: bounds)
    }

    static func drawPill(_ text: String, centeredAt center: CGPoint, in bounds: CGRect) {
        let string = pillString(text)
        let textSize = string.size()
        let size = CGSize(width: textSize.width + pillPadding.width * 2, height: textSize.height + pillPadding.height * 2)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        drawPill(string, in: frame, clampedTo: bounds)
    }

    private static func drawPill(_ string: NSAttributedString, in proposed: CGRect, clampedTo bounds: CGRect) {
        var frame = proposed
        frame.origin.x = min(max(bounds.minX + 4, frame.origin.x), bounds.maxX - frame.width - 4)
        frame.origin.y = min(max(bounds.minY + 4, frame.origin.y), bounds.maxY - frame.height - 4)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
        string.draw(at: CGPoint(x: frame.minX + pillPadding.width, y: frame.minY + pillPadding.height))
    }

    static let cameraCursor: NSCursor = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        guard let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return .pointingHand
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2))
    }()
}
