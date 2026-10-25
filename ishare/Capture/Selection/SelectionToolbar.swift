import AppKit
import ishareCore

@MainActor
struct SelectionToolbar {
    enum Item: Hashable {
        case ratio
        case size
        case customSize
        case keepRegions
        case freeze
    }

    struct Segment {
        let item: Item
        let title: String
        let isActive: Bool
        var frame: CGRect = .zero
    }

    private static let height: CGFloat = 28
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 4
    private static let segmentPadding: CGFloat = 10

    let segments: [Segment]
    let frame: CGRect

    init(session: SelectionSession, bounds: CGRect, topInset: CGFloat) {
        var segments = Self.segments(for: session)
        let attributes = Self.attributes(active: false)
        let widths = segments.map { ceil(NSAttributedString(string: $0.title, attributes: attributes).size().width) + Self.segmentPadding * 2 }
        let totalWidth = widths.reduce(0, +) + Self.spacing * CGFloat(max(0, widths.count - 1)) + Self.padding * 2
        let origin = CGPoint(x: (bounds.midX - totalWidth / 2).rounded(), y: bounds.maxY - topInset - Self.height - Self.padding * 2)
        frame = CGRect(origin: origin, size: CGSize(width: totalWidth, height: Self.height + Self.padding * 2))
        var x = frame.minX + Self.padding
        for index in segments.indices {
            segments[index].frame = CGRect(x: x, y: frame.minY + Self.padding, width: widths[index], height: Self.height)
            x += widths[index] + Self.spacing
        }
        self.segments = segments
    }

    private static func segments(for session: SelectionSession) -> [Segment] {
        let constraint = session.constraint
        let ratioTitle = String(format: "Ratio: %@".localized(), constraint.aspectRatio?.label ?? "Free".localized())
        let sizeValue: String
        if let entry = session.sizeEntry {
            sizeValue = entry.text + "▌"
        } else {
            sizeValue = constraint.fixedSize?.label ?? "Off".localized()
        }
        var segments = [
            Segment(item: .ratio, title: ratioTitle, isActive: constraint.aspectRatio != nil),
            Segment(item: .size, title: String(format: "Size: %@".localized(), sizeValue), isActive: constraint.fixedSize != nil || session.isEnteringSize),
            Segment(item: .customSize, title: "Custom Size…".localized(), isActive: false),
        ]
        if session.options.allowsMultipleRegions {
            let title = session.regions.isEmpty ? "+ Keep Regions".localized() : String(format: "+ %d Regions".localized(), session.regions.count)
            segments.append(Segment(item: .keepRegions, title: title, isActive: session.keepsRegions || !session.regions.isEmpty))
        }
        if session.options.allowsFreezeToggle {
            let title = session.freezeMode == .frozen ? "Frozen".localized() : "Live".localized()
            segments.append(Segment(item: .freeze, title: title, isActive: session.freezeMode == .live))
        }
        return segments
    }

    private static func attributes(active: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: active ? NSColor.white : NSColor.white.withAlphaComponent(0.85),
        ]
    }

    func item(at point: CGPoint) -> Item? {
        guard frame.contains(point) else { return nil }
        return segments.first { $0.frame.contains(point) }?.item
    }

    func draw(hovered: Item?) {
        let background = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
        NSColor.black.withAlphaComponent(0.72).setFill()
        background.fill()
        for segment in segments {
            let path = NSBezierPath(roundedRect: segment.frame, xRadius: segment.frame.height / 2, yRadius: segment.frame.height / 2)
            if segment.isActive {
                SelectionStyle.accentColor.setFill()
                path.fill()
            } else if segment.item == hovered {
                NSColor.white.withAlphaComponent(0.16).setFill()
                path.fill()
            }
            let text = NSAttributedString(string: segment.title, attributes: Self.attributes(active: segment.isActive))
            let size = text.size()
            text.draw(at: CGPoint(x: segment.frame.midX - size.width / 2, y: segment.frame.midY - size.height / 2))
        }
    }
}
