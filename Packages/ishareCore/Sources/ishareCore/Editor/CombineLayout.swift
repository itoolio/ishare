import CoreGraphics
import Foundation

public enum CombineLayout: String, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical
    case grid

    public var id: Self { self }

    public var symbol: String {
        switch self {
        case .horizontal: "rectangle.split.3x1"
        case .vertical: "rectangle.split.1x2"
        case .grid: "square.grid.2x2"
        }
    }
}

public enum CombineAlignment: String, CaseIterable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    public var id: Self { self }

    public func offset(free: CGFloat) -> CGFloat {
        switch self {
        case .leading: 0
        case .center: (free / 2).rounded(.down)
        case .trailing: free
        }
    }
}

public struct CombineColor: Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum CombineFill: Hashable, Sendable {
    case gradient([CombineColor])
    case solid(CombineColor)
    case transparent
}

public struct CombineStyle: Hashable, Sendable {
    public var layout: CombineLayout
    public var alignment: CombineAlignment
    public var spacing: CGFloat
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var shadowRadius: CGFloat
    public var fill: CombineFill
    public var columns: Int?

    public init(
        layout: CombineLayout = .horizontal, alignment: CombineAlignment = .center, spacing: CGFloat = 24, padding: CGFloat = 32, cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 0, fill: CombineFill = .transparent, columns: Int? = nil
    ) {
        self.layout = layout
        self.alignment = alignment
        self.spacing = spacing
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.fill = fill
        self.columns = columns
    }
}

public struct CombinedLayout: Equatable, Sendable {
    public var canvasSize: CGSize
    public var frames: [CGRect]

    public init(canvasSize: CGSize, frames: [CGRect]) {
        self.canvasSize = canvasSize
        self.frames = frames
    }
}

public enum CombineLayoutEngine {
    public static func gridColumns(for count: Int, preferred: Int?) -> Int {
        guard count > 0 else { return 1 }
        if let preferred, preferred > 0 { return min(preferred, count) }
        return Int(Double(count).squareRoot().rounded(.up))
    }

    public static func shadowRadius(enabled: Bool, padding: CGFloat, scale: CGFloat) -> CGFloat {
        enabled ? max(4, min(28, padding * 0.5)) * scale : 0
    }

    public static func cornerRadius(_ radius: CGFloat, for frame: CGRect) -> CGFloat {
        max(0, min(radius, min(frame.width, frame.height) / 2))
    }

    public static func layout(for sizes: [CGSize], style: CombineStyle) -> CombinedLayout {
        guard !sizes.isEmpty else { return CombinedLayout(canvasSize: .zero, frames: []) }
        let columns: Int =
            switch style.layout {
            case .horizontal: sizes.count
            case .vertical: 1
            case .grid: gridColumns(for: sizes.count, preferred: style.columns)
            }
        let rows = Int((Double(sizes.count) / Double(columns)).rounded(.up))
        var columnWidths = [CGFloat](repeating: 0, count: columns)
        var rowHeights = [CGFloat](repeating: 0, count: rows)
        for (index, size) in sizes.enumerated() {
            columnWidths[index % columns] = max(columnWidths[index % columns], size.width)
            rowHeights[index / columns] = max(rowHeights[index / columns], size.height)
        }
        let spacing = max(0, style.spacing.rounded())
        let padding = max(0, style.padding.rounded())
        let columnOrigins = origins(for: columnWidths, start: padding, spacing: spacing)
        let rowOrigins = origins(for: rowHeights, start: padding, spacing: spacing)
        let frames = sizes.enumerated().map { index, size -> CGRect in
            let column = index % columns
            let row = index / columns
            let x: CGFloat
            let y: CGFloat
            switch style.layout {
            case .horizontal:
                x = columnOrigins[column]
                y = rowOrigins[row] + style.alignment.offset(free: rowHeights[row] - size.height)
            case .vertical:
                x = columnOrigins[column] + style.alignment.offset(free: columnWidths[column] - size.width)
                y = rowOrigins[row]
            case .grid:
                x = columnOrigins[column] + style.alignment.offset(free: columnWidths[column] - size.width)
                y = rowOrigins[row] + style.alignment.offset(free: rowHeights[row] - size.height)
            }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        let width = columnWidths.reduce(0, +) + spacing * CGFloat(columns - 1) + padding * 2
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(rows - 1) + padding * 2
        return CombinedLayout(canvasSize: CGSize(width: width, height: height), frames: frames)
    }

    private static func origins(for lengths: [CGFloat], start: CGFloat, spacing: CGFloat) -> [CGFloat] {
        var position = start
        return lengths.map { length in
            defer { position += length + spacing }
            return position
        }
    }
}
