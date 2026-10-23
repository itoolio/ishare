import CoreGraphics
import Foundation

public enum DeviceFrame: String, CaseIterable, Identifiable, Sendable {
    case none
    case laptop
    case display
    case phone
    case browser

    public var id: Self { self }

    func screenAspect(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .none, .browser: nil
        case .laptop: 1.54
        case .display: 16.0 / 9.0
        case .phone: imageSize.width > imageSize.height ? 19.5 / 9.0 : 9.0 / 19.5
        }
    }
}

public enum DeviceFrameAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    public var id: Self { self }
}

public enum DeviceFrameFit: String, CaseIterable, Identifiable, Sendable {
    case letterbox
    case crop

    public var id: Self { self }
}

public struct DeviceFrameStyle: Hashable, Sendable {
    public var kind: DeviceFrame
    public var appearance: DeviceFrameAppearance = .light
    public var fit: DeviceFrameFit = .letterbox
    public var title: String = ""

    public init(kind: DeviceFrame, appearance: DeviceFrameAppearance = .light, fit: DeviceFrameFit = .letterbox, title: String = "") {
        self.kind = kind
        self.appearance = appearance
        self.fit = fit
        self.title = title
    }
}

public struct DeviceFrameLayout: Equatable, Sendable {
    public var canvasSize: CGSize
    public var bodyRect: CGRect
    public var bodyCornerRadius: CGFloat
    public var rimWidth: CGFloat
    public var screenRect: CGRect
    public var screenCornerRadius: CGFloat
    public var imageRect: CGRect
    public var baseRect: CGRect?
    public var hingeRect: CGRect?
    public var neckRect: CGRect?
    public var footRect: CGRect?
    public var islandRect: CGRect?
    public var buttons: [CGRect] = []
    public var toolbarRect: CGRect?
    public var addressRect: CGRect?
    public var trafficLights: [CGRect] = []

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

    public static func placement(of imageSize: CGSize, in screen: CGRect, fit: DeviceFrameFit) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return screen }
        let widthScale = screen.width / imageSize.width
        let heightScale = screen.height / imageSize.height
        let scale = fit == .letterbox ? min(widthScale, heightScale) : max(widthScale, heightScale)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
    }

    public static func make(for imageSize: CGSize, style: DeviceFrameStyle) -> DeviceFrameLayout? {
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

    public init(canvasSize: CGSize, bodyRect: CGRect, bodyCornerRadius: CGFloat, rimWidth: CGFloat, screenRect: CGRect, screenCornerRadius: CGFloat, imageRect: CGRect, baseRect: CGRect? = nil, hingeRect: CGRect? = nil, neckRect: CGRect? = nil, footRect: CGRect? = nil, islandRect: CGRect? = nil, buttons: [CGRect] = [], toolbarRect: CGRect? = nil, addressRect: CGRect? = nil, trafficLights: [CGRect] = []) {
        self.canvasSize = canvasSize
        self.bodyRect = bodyRect
        self.bodyCornerRadius = bodyCornerRadius
        self.rimWidth = rimWidth
        self.screenRect = screenRect
        self.screenCornerRadius = screenCornerRadius
        self.imageRect = imageRect
        self.baseRect = baseRect
        self.hingeRect = hingeRect
        self.neckRect = neckRect
        self.footRect = footRect
        self.islandRect = islandRect
        self.buttons = buttons
        self.toolbarRect = toolbarRect
        self.addressRect = addressRect
        self.trafficLights = trafficLights
    }
}
