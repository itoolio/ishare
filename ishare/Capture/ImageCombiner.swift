import CoreGraphics
import Foundation

enum CombineLayout: String, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical
    case grid

    var id: Self { self }

    var title: String {
        switch self {
        case .horizontal: "Horizontal".localized()
        case .vertical: "Vertical".localized()
        case .grid: "Grid".localized()
        }
    }

    var symbol: String {
        switch self {
        case .horizontal: "rectangle.split.3x1"
        case .vertical: "rectangle.split.1x2"
        case .grid: "square.grid.2x2"
        }
    }
}

enum CombineAlignment: String, CaseIterable, Identifiable, Sendable {
    case leading
    case center
    case trailing

    var id: Self { self }

    var title: String {
        switch self {
        case .leading: "Start".localized()
        case .center: "Center".localized()
        case .trailing: "End".localized()
        }
    }

    func offset(free: CGFloat) -> CGFloat {
        switch self {
        case .leading: 0
        case .center: (free / 2).rounded(.down)
        case .trailing: free
        }
    }
}

struct CombineStyle: Hashable, Sendable {
    var layout: CombineLayout = .horizontal
    var alignment: CombineAlignment = .center
    var spacing: CGFloat = 24
    var padding: CGFloat = 32
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 0
    var fill: BeautifyStyle.Fill = .transparent
    var columns: Int?
}

struct CombinedLayout: Equatable, Sendable {
    var canvasSize: CGSize
    var frames: [CGRect]
}

enum ImageCombiner {
    static func gridColumns(for count: Int, preferred: Int?) -> Int {
        guard count > 0 else { return 1 }
        if let preferred, preferred > 0 { return min(preferred, count) }
        return Int(Double(count).squareRoot().rounded(.up))
    }

    static func layout(for sizes: [CGSize], style: CombineStyle) -> CombinedLayout {
        guard !sizes.isEmpty else { return CombinedLayout(canvasSize: .zero, frames: []) }
        let columns: Int = switch style.layout {
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

    static func combine(_ images: [CGImage], style: CombineStyle) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let layout = layout(for: images.map { CGSize(width: $0.width, height: $0.height) }, style: style)
        guard layout.canvasSize.width >= 1, layout.canvasSize.height >= 1,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: Int(layout.canvasSize.width), height: Int(layout.canvasSize.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        Beautifier.fillBackground(style.fill, in: canvas, context: context, colorSpace: colorSpace)
        for (image, frame) in zip(images, layout.frames) {
            let flipped = CGRect(x: frame.minX, y: layout.canvasSize.height - frame.maxY, width: frame.width, height: frame.height)
            let radius = min(style.cornerRadius, min(frame.width, frame.height) / 2)
            context.saveGState()
            if style.shadowRadius > 0 {
                context.setShadow(
                    offset: CGSize(width: 0, height: -style.shadowRadius * 0.35),
                    blur: style.shadowRadius,
                    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4)
                )
            }
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.addPath(CGPath(roundedRect: flipped, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            context.draw(image, in: flipped)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        return context.makeImage()
    }
}
