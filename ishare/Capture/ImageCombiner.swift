import CoreGraphics
import Defaults
import Foundation
import ishareCore

extension CombineLayout: Defaults.Serializable {
    var title: String {
        switch self {
        case .horizontal: "Horizontal".localized()
        case .vertical: "Vertical".localized()
        case .grid: "Grid".localized()
        }
    }
}

extension CombineAlignment: Defaults.Serializable {
    var title: String {
        switch self {
        case .leading: "Start".localized()
        case .center: "Center".localized()
        case .trailing: "End".localized()
        }
    }
}

extension CombineColor {
    init(_ color: CaptureColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension CaptureColor {
    init(_ color: CombineColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension CombineFill {
    init(_ fill: BeautifyStyle.Fill) {
        switch fill {
        case let .gradient(colors): self = .gradient(colors.map(CombineColor.init))
        case let .solid(color): self = .solid(CombineColor(color))
        case .transparent: self = .transparent
        }
    }

    var beautifyFill: BeautifyStyle.Fill {
        switch self {
        case let .gradient(colors): .gradient(colors.map(CaptureColor.init))
        case let .solid(color): .solid(CaptureColor(color))
        case .transparent: .transparent
        }
    }
}

enum ImageCombiner {
    static func gridColumns(for count: Int, preferred: Int?) -> Int {
        CombineLayoutEngine.gridColumns(for: count, preferred: preferred)
    }

    static func layout(for sizes: [CGSize], style: CombineStyle) -> CombinedLayout {
        CombineLayoutEngine.layout(for: sizes, style: style)
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
        Beautifier.fillBackground(style.fill.beautifyFill, in: canvas, context: context, colorSpace: colorSpace)
        for (image, frame) in zip(images, layout.frames) {
            let flipped = CGRect(x: frame.minX, y: layout.canvasSize.height - frame.maxY, width: frame.width, height: frame.height)
            let radius = CombineLayoutEngine.cornerRadius(style.cornerRadius, for: frame)
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
