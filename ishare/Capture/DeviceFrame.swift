import CoreGraphics
import CoreText
import Defaults
import Foundation

enum DeviceFrame: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case none
    case laptop
    case display
    case phone
    case browser

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None".localized()
        case .laptop: "Laptop".localized()
        case .display: "Desktop Display".localized()
        case .phone: "Phone".localized()
        case .browser: "Browser Window".localized()
        }
    }

    func screenAspect(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .none, .browser: nil
        case .laptop: 1.54
        case .display: 16.0 / 9.0
        case .phone: imageSize.width > imageSize.height ? 19.5 / 9.0 : 9.0 / 19.5
        }
    }
}

enum DeviceFrameAppearance: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "Light".localized()
        case .dark: "Dark".localized()
        }
    }
}

enum DeviceFrameFit: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case letterbox
    case crop

    var id: Self { self }

    var title: String {
        switch self {
        case .letterbox: "Letterbox".localized()
        case .crop: "Crop to Fill".localized()
        }
    }
}

struct DeviceFrameStyle: Hashable, Sendable {
    var kind: DeviceFrame
    var appearance: DeviceFrameAppearance = .light
    var fit: DeviceFrameFit = .letterbox
    var title: String = ""
}

struct DeviceFrameLayout: Equatable, Sendable {
    var canvasSize: CGSize
    var bodyRect: CGRect
    var bodyCornerRadius: CGFloat
    var rimWidth: CGFloat
    var screenRect: CGRect
    var screenCornerRadius: CGFloat
    var imageRect: CGRect
    var baseRect: CGRect?
    var hingeRect: CGRect?
    var neckRect: CGRect?
    var footRect: CGRect?
    var islandRect: CGRect?
    var buttons: [CGRect] = []
    var toolbarRect: CGRect?
    var addressRect: CGRect?
    var trafficLights: [CGRect] = []

    static func screenSize(for imageSize: CGSize, aspect: CGFloat?, fit: DeviceFrameFit) -> CGSize {
        guard let aspect, aspect > 0, imageSize.width > 0, imageSize.height > 0 else { return imageSize }
        let imageAspect = imageSize.width / imageSize.height
        let widthBound = imageAspect > aspect
        let size: CGSize = switch (fit, widthBound) {
        case (.letterbox, true), (.crop, false): CGSize(width: imageSize.width, height: imageSize.width / aspect)
        case (.letterbox, false), (.crop, true): CGSize(width: imageSize.height * aspect, height: imageSize.height)
        }
        return CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
    }

    static func placement(of imageSize: CGSize, in screen: CGRect, fit: DeviceFrameFit) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return screen }
        let widthScale = screen.width / imageSize.width
        let heightScale = screen.height / imageSize.height
        let scale = fit == .letterbox ? min(widthScale, heightScale) : max(widthScale, heightScale)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func make(for imageSize: CGSize, style: DeviceFrameStyle) -> DeviceFrameLayout? {
        let screen = screenSize(for: imageSize, aspect: style.kind.screenAspect(for: imageSize), fit: style.fit)
        switch style.kind {
        case .none: return nil
        case .laptop: return laptop(screen: screen, imageSize: imageSize, fit: style.fit)
        case .display: return display(screen: screen, imageSize: imageSize, fit: style.fit)
        case .phone: return phone(screen: screen, imageSize: imageSize, fit: style.fit)
        case .browser: return browser(screen: screen)
        }
    }

    private static func laptop(screen: CGSize, imageSize: CGSize, fit: DeviceFrameFit) -> DeviceFrameLayout {
        let unit = screen.width
        let rim = max(1, (unit * 0.006).rounded())
        let side = (unit * 0.028).rounded()
        let top = (unit * 0.03).rounded()
        let bottom = (unit * 0.045).rounded()
        let lidSize = CGSize(width: screen.width + side * 2, height: screen.height + top + bottom)
        let baseSize = CGSize(width: (lidSize.width * 1.14).rounded(), height: max(4, (unit * 0.04).rounded()))
        let lid = CGRect(x: ((baseSize.width - lidSize.width) / 2).rounded(), y: 0, width: lidSize.width, height: lidSize.height)
        let screenRect = CGRect(x: lid.minX + side, y: lid.minY + top, width: screen.width, height: screen.height)
        let base = CGRect(x: 0, y: lid.maxY, width: baseSize.width, height: baseSize.height)
        let hingeWidth = (unit * 0.16).rounded()
        let hinge = CGRect(x: base.midX - hingeWidth / 2, y: base.minY, width: hingeWidth, height: max(1, (base.height * 0.35).rounded()))
        return DeviceFrameLayout(
            canvasSize: CGSize(width: baseSize.width, height: lid.height + base.height),
            bodyRect: lid,
            bodyCornerRadius: unit * 0.035,
            rimWidth: rim,
            screenRect: screenRect,
            screenCornerRadius: unit * 0.008,
            imageRect: placement(of: imageSize, in: screenRect, fit: fit),
            baseRect: base,
            hingeRect: hinge
        )
    }

    private static func display(screen: CGSize, imageSize: CGSize, fit: DeviceFrameFit) -> DeviceFrameLayout {
        let unit = screen.width
        let rim = max(1, (unit * 0.004).rounded())
        let bezel = (unit * 0.03).rounded()
        let body = CGRect(x: 0, y: 0, width: screen.width + bezel * 2, height: screen.height + bezel * 2)
        let screenRect = CGRect(x: bezel, y: bezel, width: screen.width, height: screen.height)
        let neckWidth = (unit * 0.2).rounded()
        let neck = CGRect(x: body.midX - neckWidth / 2, y: body.maxY, width: neckWidth, height: (unit * 0.17).rounded())
        let footWidth = (unit * 0.3).rounded()
        let foot = CGRect(x: body.midX - footWidth / 2, y: neck.maxY, width: footWidth, height: max(3, (unit * 0.018).rounded()))
        return DeviceFrameLayout(
            canvasSize: CGSize(width: body.width, height: foot.maxY),
            bodyRect: body,
            bodyCornerRadius: unit * 0.018,
            rimWidth: rim,
            screenRect: screenRect,
            screenCornerRadius: 0,
            imageRect: placement(of: imageSize, in: screenRect, fit: fit),
            neckRect: neck,
            footRect: foot
        )
    }

    private static func phone(screen: CGSize, imageSize: CGSize, fit: DeviceFrameFit) -> DeviceFrameLayout {
        let short = min(screen.width, screen.height)
        let portrait = screen.height >= screen.width
        let button = max(2, (short * 0.012).rounded())
        let rim = max(2, (short * 0.014).rounded())
        let bezel = (short * 0.045).rounded()
        let screenRadius = short * 0.14
        let bodyOrigin = portrait ? CGPoint(x: button, y: 0) : CGPoint(x: 0, y: button)
        let body = CGRect(origin: bodyOrigin, size: CGSize(width: screen.width + bezel * 2, height: screen.height + bezel * 2))
        let screenRect = CGRect(x: body.minX + bezel, y: body.minY + bezel, width: screen.width, height: screen.height)
        let islandLong = (short * 0.3).rounded()
        let islandShort = (short * 0.088).rounded()
        let islandInset = (short * 0.032).rounded()
        let island = portrait
            ? CGRect(x: screenRect.midX - islandLong / 2, y: screenRect.minY + islandInset, width: islandLong, height: islandShort)
            : CGRect(x: screenRect.minX + islandInset, y: screenRect.midY - islandLong / 2, width: islandShort, height: islandLong)
        let canvas = portrait
            ? CGSize(width: body.width + button * 2, height: body.height)
            : CGSize(width: body.width, height: body.height + button * 2)
        return DeviceFrameLayout(
            canvasSize: canvas,
            bodyRect: body,
            bodyCornerRadius: screenRadius + bezel,
            rimWidth: rim,
            screenRect: screenRect,
            screenCornerRadius: screenRadius,
            imageRect: placement(of: imageSize, in: screenRect, fit: fit),
            islandRect: island,
            buttons: phoneButtons(body: body, short: short, thickness: button, portrait: portrait)
        )
    }

    private static func phoneButtons(body: CGRect, short: CGFloat, thickness: CGFloat, portrait: Bool) -> [CGRect] {
        let leading: [(offset: CGFloat, length: CGFloat)] = [(0.27, 0.09), (0.42, 0.16), (0.62, 0.16)]
        let trailing: [(offset: CGFloat, length: CGFloat)] = [(0.45, 0.26)]
        func place(_ spec: (offset: CGFloat, length: CGFloat), leadingSide: Bool) -> CGRect {
            let offset = (short * spec.offset).rounded()
            let length = (short * spec.length).rounded()
            if portrait {
                return CGRect(x: leadingSide ? body.minX - thickness : body.maxX, y: body.minY + offset, width: thickness, height: length)
            }
            return CGRect(x: body.minX + offset, y: leadingSide ? body.minY - thickness : body.maxY, width: length, height: thickness)
        }
        return leading.map { place($0, leadingSide: true) } + trailing.map { place($0, leadingSide: false) }
    }

    private static func browser(screen: CGSize) -> DeviceFrameLayout {
        let toolbarHeight = max(28, (screen.width * 0.045).rounded())
        let window = CGRect(x: 0, y: 0, width: screen.width, height: screen.height + toolbarHeight)
        let toolbar = CGRect(x: 0, y: 0, width: screen.width, height: toolbarHeight)
        let screenRect = CGRect(x: 0, y: toolbarHeight, width: screen.width, height: screen.height)
        let diameter = (toolbarHeight * 0.36).rounded()
        let lights = (0 ..< 3).map { index in
            CGRect(x: (toolbarHeight * 0.45).rounded() + CGFloat(index) * (diameter * 1.65).rounded(), y: toolbar.midY - diameter / 2, width: diameter, height: diameter)
        }
        let lightsEnd = (lights.last?.maxX ?? 0) + toolbarHeight * 0.5
        let fieldHeight = (toolbarHeight * 0.62).rounded()
        let fieldWidth = max(0, min(screen.width * 0.5, screen.width - lightsEnd * 2))
        let address = CGRect(x: toolbar.midX - fieldWidth / 2, y: toolbar.midY - fieldHeight / 2, width: fieldWidth, height: fieldHeight)
        return DeviceFrameLayout(
            canvasSize: window.size,
            bodyRect: window,
            bodyCornerRadius: min(toolbarHeight * 0.32, 14 * max(1, toolbarHeight / 40)),
            rimWidth: 1,
            screenRect: screenRect,
            screenCornerRadius: 0,
            imageRect: screenRect,
            toolbarRect: toolbar,
            addressRect: fieldWidth >= toolbarHeight ? address : nil,
            trafficLights: lights
        )
    }
}

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
