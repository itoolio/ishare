import CoreGraphics
import Defaults
import Foundation
import ishareCore

enum BeautifyBackground: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case ocean
    case sunset
    case forest
    case graphite
    case solid
    case transparent

    var id: Self { self }

    var title: String {
        switch self {
        case .ocean: "Ocean".localized()
        case .sunset: "Sunset".localized()
        case .forest: "Forest".localized()
        case .graphite: "Graphite".localized()
        case .solid: "Solid color".localized()
        case .transparent: "Transparent".localized()
        }
    }

    var gradientColors: [CaptureColor]? {
        switch self {
        case .ocean: [CaptureColor(hex: "#4F8CFF")!, CaptureColor(hex: "#8E5CF7")!]
        case .sunset: [CaptureColor(hex: "#FF8A4C")!, CaptureColor(hex: "#F24E8F")!]
        case .forest: [CaptureColor(hex: "#2FB67C")!, CaptureColor(hex: "#1C7C9C")!]
        case .graphite: [CaptureColor(hex: "#5A5F6B")!, CaptureColor(hex: "#1F2128")!]
        case .solid, .transparent: nil
        }
    }
}

struct CaptureColor: Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat = 1

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        red = CGFloat((rgb >> 16) & 0xFF) / 255
        green = CGFloat((rgb >> 8) & 0xFF) / 255
        blue = CGFloat(rgb & 0xFF) / 255
        alpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func byte(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}

struct BeautifyStyle: Hashable, Sendable {
    enum Fill: Hashable, Sendable {
        case gradient([CaptureColor])
        case solid(CaptureColor)
        case transparent
    }

    var padding: CGFloat
    var cornerRadius: CGFloat
    var shadowRadius: CGFloat
    var fill: Fill
    var frame: DeviceFrameStyle?

    init(padding: CGFloat, cornerRadius: CGFloat, shadowRadius: CGFloat, fill: Fill, frame: DeviceFrameStyle? = nil) {
        self.padding = max(0, padding.rounded())
        self.cornerRadius = max(0, cornerRadius)
        self.shadowRadius = max(0, shadowRadius)
        self.fill = fill
        self.frame = frame?.kind == DeviceFrame.none ? nil : frame
    }

    init(
        background: BeautifyBackground, solidColor: CaptureColor, padding: CGFloat, cornerRadius: CGFloat, shadow: Bool, scale: CGFloat,
        frame: DeviceFrameStyle? = nil
    ) {
        let fill: Fill = switch background {
        case .solid: .solid(solidColor)
        case .transparent: .transparent
        default: .gradient(background.gradientColors ?? [solidColor])
        }
        let scaledPadding = padding * scale
        self.init(
            padding: scaledPadding,
            cornerRadius: cornerRadius * scale,
            shadowRadius: shadow ? min(28 * scale, max(4 * scale, scaledPadding * 0.5)) : 0,
            fill: fill,
            frame: frame
        )
    }

    @MainActor static func current(scale: CGFloat, windowTitle: String? = nil) -> BeautifyStyle {
        BeautifyStyle(
            background: Defaults[.beautifyBackground],
            solidColor: CaptureColor(hex: Defaults[.beautifySolidColor]) ?? CaptureColor(red: 0.12, green: 0.12, blue: 0.18),
            padding: Defaults[.beautifyPadding],
            cornerRadius: Defaults[.beautifyCornerRadius],
            shadow: Defaults[.beautifyShadow],
            scale: scale,
            frame: DeviceFrameStyle.current(windowTitle: windowTitle)
        )
    }
}

extension DeviceFrameStyle {
    @MainActor static func current(windowTitle: String? = nil) -> DeviceFrameStyle? {
        let kind = Defaults[.beautifyFrame]
        guard kind != .none else { return nil }
        let custom = Defaults[.beautifyFrameTitle].trimmingCharacters(in: .whitespacesAndNewlines)
        return DeviceFrameStyle(
            kind: kind,
            appearance: Defaults[.beautifyFrameAppearance],
            fit: Defaults[.beautifyFrameFit],
            title: custom.isEmpty ? windowTitle ?? "" : custom
        )
    }
}

enum Beautifier {
    static func outputSize(for size: CGSize, style: BeautifyStyle) -> CGSize {
        CGSize(width: size.width + style.padding * 2, height: size.height + style.padding * 2)
    }

    static func contentRect(for size: CGSize, style: BeautifyStyle) -> CGRect {
        CGRect(origin: CGPoint(x: style.padding, y: style.padding), size: size)
    }

    static func effectiveCornerRadius(for size: CGSize, style: BeautifyStyle) -> CGFloat {
        min(style.cornerRadius, min(size.width, size.height) / 2)
    }

    static func apply(to original: CGImage, style: BeautifyStyle) -> CGImage? {
        let framed = style.frame.flatMap { DeviceFramer.apply(to: original, style: $0) }
        let image = framed ?? original
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvasSize = outputSize(for: imageSize, style: style)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: Int(canvasSize.width), height: Int(canvasSize.height),
                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        let canvas = CGRect(origin: .zero, size: canvasSize)
        fillBackground(style.fill, in: canvas, context: context, colorSpace: colorSpace)

        let content = contentRect(for: imageSize, style: style)
        let radius = framed == nil ? effectiveCornerRadius(for: imageSize, style: style) : 0
        context.saveGState()
        if style.shadowRadius > 0 {
            context.setShadow(
                offset: CGSize(width: 0, height: -style.shadowRadius * 0.35),
                blur: style.shadowRadius,
                color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
            )
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: content)
        context.endTransparencyLayer()
        context.restoreGState()
        return context.makeImage()
    }

    static func fillBackground(_ fill: BeautifyStyle.Fill, in rect: CGRect, context: CGContext, colorSpace: CGColorSpace) {
        switch fill {
        case .transparent:
            context.clear(rect)
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case let .gradient(colors):
            let cgColors = colors.map(\.cgColor) as CFArray
            guard colors.count > 1, let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: nil) else {
                context.setFillColor(colors.first?.cgColor ?? CGColor(gray: 0, alpha: 0))
                context.fill(rect)
                return
            }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }
}
