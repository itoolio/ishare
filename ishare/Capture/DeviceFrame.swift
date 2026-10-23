import CoreGraphics
import CoreText
import Defaults
import Foundation
import ishareCore

enum DeviceFramer {
    struct Palette {
        var body: CGColor
        var rim: CGColor
        var base: CGColor
        var accent: CGColor
        var glass: CGColor

        static func device(_ appearance: DeviceFrameAppearance) -> Palette {
            switch appearance {
            case .light:
                Palette(body: color("#E3E4E6"), rim: color("#C4C6CA"), base: color("#D2D4D7"), accent: color("#A9ACB1"), glass: color("#0B0B0D"))
            case .dark:
                Palette(body: color("#2E2F33"), rim: color("#4A4B50"), base: color("#3A3B3F"), accent: color("#1C1D20"), glass: color("#050506"))
            }
        }

        static func browser(_ appearance: DeviceFrameAppearance) -> Palette {
            switch appearance {
            case .light:
                Palette(body: color("#EDEDEF"), rim: color("#C9C9CD"), base: color("#FFFFFF"), accent: color("#5F6368"), glass: color("#D9D9DC"))
            case .dark:
                Palette(body: color("#2B2B2E"), rim: color("#101012"), base: color("#1C1C1E"), accent: color("#B8B8BD"), glass: color("#3A3A3D"))
            }
        }

        private static func color(_ hex: String) -> CGColor {
            (CaptureColor(hex: hex) ?? CaptureColor(red: 0, green: 0, blue: 0)).cgColor
        }
    }

    static var trafficLightColors: [CGColor] { ["#FF5F57", "#FEBC2E", "#28C840"].compactMap { CaptureColor(hex: $0)?.cgColor } }

    static func apply(to image: CGImage, style: DeviceFrameStyle) -> CGImage? {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard let layout = DeviceFrameLayout.make(for: imageSize, style: style),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(layout.canvasSize.width.rounded(.up)), height: Int(layout.canvasSize.height.rounded(.up)),
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: 1, y: -1)
        switch style.kind {
        case .browser:
            drawBrowser(image, layout: layout, style: style, in: context)
        case .laptop, .display, .phone:
            drawDevice(image, layout: layout, palette: .device(style.appearance), in: context)
        case .none:
            return nil
        }
        return context.makeImage()
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let clamped = max(0, min(radius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
    }

    private static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func drawDevice(_ image: CGImage, layout: DeviceFrameLayout, palette: Palette, in context: CGContext) {
        for button in layout.buttons {
            context.setFillColor(palette.rim)
            context.addPath(roundedPath(button, radius: min(button.width, button.height) / 2))
            context.fillPath()
        }
        if let neck = layout.neckRect {
            drawStand(neck: neck, foot: layout.footRect, palette: palette, in: context)
        }
        if let base = layout.baseRect {
            drawLaptopBase(base, hinge: layout.hingeRect, palette: palette, in: context)
        }
        context.setFillColor(palette.rim)
        context.addPath(roundedPath(layout.bodyRect, radius: layout.bodyCornerRadius))
        context.fillPath()
        let inner = layout.bodyRect.insetBy(dx: layout.rimWidth, dy: layout.rimWidth)
        context.setFillColor(palette.glass)
        context.addPath(roundedPath(inner, radius: layout.bodyCornerRadius - layout.rimWidth))
        context.fillPath()

        context.saveGState()
        context.addPath(roundedPath(layout.screenRect, radius: layout.screenCornerRadius))
        context.clip()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(layout.screenRect)
        drawUpright(image, in: layout.imageRect, context: context)
        context.restoreGState()

        if let island = layout.islandRect {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.addPath(roundedPath(island, radius: min(island.width, island.height) / 2))
            context.fillPath()
        }
    }

    private static func drawStand(neck: CGRect, foot: CGRect?, palette: Palette, in context: CGContext) {
        let path = CGMutablePath()
        let inset = neck.width * 0.08
        path.move(to: CGPoint(x: neck.minX + inset, y: neck.minY))
        path.addLine(to: CGPoint(x: neck.maxX - inset, y: neck.minY))
        path.addLine(to: CGPoint(x: neck.maxX, y: neck.maxY))
        path.addLine(to: CGPoint(x: neck.minX, y: neck.maxY))
        path.closeSubpath()
        context.setFillColor(palette.base)
        context.addPath(path)
        context.fillPath()
        context.setFillColor(palette.accent.copy(alpha: 0.35) ?? palette.accent)
        context.fill(CGRect(x: neck.minX + inset, y: neck.minY, width: neck.width - inset * 2, height: max(1, neck.height * 0.06)))
        guard let foot else { return }
        context.setFillColor(palette.rim)
        context.addPath(roundedPath(foot, radius: foot.height / 2))
        context.fillPath()
    }

    private static func drawLaptopBase(_ base: CGRect, hinge: CGRect?, palette: Palette, in context: CGContext) {
        let radius = base.height * 0.9
        let path = CGMutablePath()
        path.move(to: CGPoint(x: base.minX, y: base.minY))
        path.addLine(to: CGPoint(x: base.maxX, y: base.minY))
        path.addLine(to: CGPoint(x: base.maxX, y: base.maxY - radius / 2))
        path.addQuadCurve(to: CGPoint(x: base.maxX - radius, y: base.maxY), control: CGPoint(x: base.maxX, y: base.maxY))
        path.addLine(to: CGPoint(x: base.minX + radius, y: base.maxY))
        path.addQuadCurve(to: CGPoint(x: base.minX, y: base.maxY - radius / 2), control: CGPoint(x: base.minX, y: base.maxY))
        path.closeSubpath()
        context.setFillColor(palette.base)
        context.addPath(path)
        context.fillPath()
        context.setFillColor(palette.accent.copy(alpha: 0.5) ?? palette.accent)
        context.fill(CGRect(x: base.minX, y: base.maxY - max(1, base.height * 0.18), width: base.width, height: max(1, base.height * 0.18)))
        guard let hinge else { return }
        context.setFillColor(palette.accent)
        context.addPath(roundedPath(hinge, radius: hinge.height / 2))
        context.fillPath()
    }

    private static func drawBrowser(_ image: CGImage, layout: DeviceFrameLayout, style: DeviceFrameStyle, in context: CGContext) {
        let palette = Palette.browser(style.appearance)
        let window = roundedPath(layout.bodyRect, radius: layout.bodyCornerRadius)
        context.saveGState()
        context.addPath(window)
        context.clip()
        context.setFillColor(palette.body)
        context.fill(layout.bodyRect)
        drawUpright(image, in: layout.imageRect, context: context)
        if let toolbar = layout.toolbarRect {
            context.setFillColor(palette.rim)
            context.fill(CGRect(x: toolbar.minX, y: toolbar.maxY - 1, width: toolbar.width, height: 1))
        }
        context.restoreGState()
        for (light, color) in zip(layout.trafficLights, trafficLightColors) {
            context.setFillColor(color)
            context.fillEllipse(in: light)
        }
        if let address = layout.addressRect {
            context.setFillColor(palette.base)
            context.addPath(roundedPath(address, radius: address.height * 0.3))
            context.fillPath()
            context.setStrokeColor(palette.glass)
            context.setLineWidth(1)
            context.addPath(roundedPath(address.insetBy(dx: 0.5, dy: 0.5), radius: address.height * 0.3))
            context.strokePath()
            let title = style.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                drawCenteredText(title, in: address.insetBy(dx: address.height * 0.5, dy: 0), fontSize: address.height * 0.52, color: palette.accent, context: context)
            }
        }
        context.setStrokeColor(palette.rim)
        context.setLineWidth(1)
        context.addPath(roundedPath(layout.bodyRect.insetBy(dx: 0.5, dy: 0.5), radius: layout.bodyCornerRadius))
        context.strokePath()
    }

    static func truncatedLine(_ text: String, fontSize: CGFloat, color: CGColor, width: CGFloat) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(max(1, width)), .end, ellipsis) ?? line
    }

    private static func drawCenteredText(_ text: String, in rect: CGRect, fontSize: CGFloat, color: CGColor, context: CGContext) {
        let line = truncatedLine(text, fontSize: fontSize, color: color, width: rect.width)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: rect.midX - width / 2, y: rect.midY + (ascent - descent) / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

extension DeviceFrame: @retroactive Defaults.Serializable {}

extension DeviceFrameAppearance: @retroactive Defaults.Serializable {}

extension DeviceFrameFit: @retroactive Defaults.Serializable {}

extension DeviceFrame {
    var title: String {
        switch self {
        case .none: "None".localized()
        case .laptop: "Laptop".localized()
        case .display: "Desktop Display".localized()
        case .phone: "Phone".localized()
        case .browser: "Browser Window".localized()
        }
    }
}

extension DeviceFrameAppearance {
    var title: String {
        switch self {
        case .light: "Light".localized()
        case .dark: "Dark".localized()
        }
    }
}

extension DeviceFrameFit {
    var title: String {
        switch self {
        case .letterbox: "Letterbox".localized()
        case .crop: "Crop to Fill".localized()
        }
    }
}
