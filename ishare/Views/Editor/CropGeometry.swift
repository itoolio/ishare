import CoreGraphics

enum ResizeHandle: CaseIterable, Hashable, Sendable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        default: false
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var opposite: ResizeHandle {
        switch self {
        case .topLeft: .bottomRight
        case .top: .bottom
        case .topRight: .bottomLeft
        case .right: .left
        case .bottomRight: .topLeft
        case .bottom: .top
        case .bottomLeft: .topRight
        case .left: .right
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine
    case nineSixteen

    var id: Self { self }

    var title: String {
        switch self {
        case .free: "Free".localized()
        case .original: "Original".localized()
        case .square: "1:1".localized()
        case .fourThree: "4:3".localized()
        case .threeTwo: "3:2".localized()
        case .sixteenNine: "16:9".localized()
        case .nineSixteen: "9:16".localized()
        }
    }

    func ratio(for imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .threeTwo: 3.0 / 2.0
        case .sixteenNine: 16.0 / 9.0
        case .nineSixteen: 9.0 / 16.0
        }
    }
}

enum CropGeometry {
    static let minimumSize: CGFloat = 8

    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> ResizeHandle? {
        ResizeHandle.allCases
            .map { ($0, hypot($0.point(in: rect).x - point.x, $0.point(in: rect).y - point.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    static func rect(anchor: CGPoint, to point: CGPoint, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        let directionX: CGFloat = point.x >= anchor.x ? 1 : -1
        let directionY: CGFloat = point.y >= anchor.y ? 1 : -1
        let room = CGSize(
            width: directionX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX,
            height: directionY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        )
        var width = min(abs(point.x - anchor.x), room.width)
        var height = min(abs(point.y - anchor.y), room.height)
        if let ratio {
            width = min(max(width, height * ratio), room.width, room.height * ratio)
            height = width / ratio
        }
        return ScreenGeometry.rect(from: anchor, to: CGPoint(x: anchor.x + width * directionX, y: anchor.y + height * directionY))
    }

    static func resize(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        let clampedPoint = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        if handle.isCorner {
            return Self.rect(anchor: handle.opposite.point(in: rect), to: clampedPoint, ratio: ratio, bounds: bounds)
        }
        var result = rect
        switch handle {
        case .left:
            result = CGRect(x: min(clampedPoint.x, rect.maxX - minimumSize), y: rect.minY, width: rect.maxX - min(clampedPoint.x, rect.maxX - minimumSize), height: rect.height)
        case .right:
            result.size.width = max(minimumSize, clampedPoint.x - rect.minX)
        case .top:
            result = CGRect(x: rect.minX, y: min(clampedPoint.y, rect.maxY - minimumSize), width: rect.width, height: rect.maxY - min(clampedPoint.y, rect.maxY - minimumSize))
        case .bottom:
            result.size.height = max(minimumSize, clampedPoint.y - rect.minY)
        default:
            break
        }
        guard let ratio else { return ScreenGeometry.clamp(result, to: bounds) }
        return constrainEdgeResize(result, handle: handle, ratio: ratio, bounds: bounds)
    }

    private static func constrainEdgeResize(_ rect: CGRect, handle: ResizeHandle, ratio: CGFloat, bounds: CGRect) -> CGRect {
        let horizontal = handle == .left || handle == .right
        if horizontal {
            let maxHeight = 2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY)
            let height = min(rect.width / ratio, maxHeight)
            let width = height * ratio
            let x = handle == .left ? rect.maxX - width : rect.minX
            return CGRect(x: x, y: rect.midY - height / 2, width: width, height: height)
        }
        let maxWidth = 2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX)
        let width = min(rect.height * ratio, maxWidth)
        let height = width / ratio
        let y = handle == .top ? rect.maxY - height : rect.minY
        return CGRect(x: rect.midX - width / 2, y: y, width: width, height: height)
    }

    static func fit(_ rect: CGRect, ratio: CGFloat?, bounds: CGRect) -> CGRect {
        guard let ratio else { return ScreenGeometry.clamp(rect, to: bounds) }
        let reference = rect.width >= 1 && rect.height >= 1 ? rect : bounds
        var width = reference.width
        var height = width / ratio
        if height > reference.height {
            height = reference.height
            width = height * ratio
        }
        if width > bounds.width {
            width = bounds.width
            height = width / ratio
        }
        if height > bounds.height {
            height = bounds.height
            width = height * ratio
        }
        let centered = CGRect(x: reference.midX - width / 2, y: reference.midY - height / 2, width: width, height: height)
        return ScreenGeometry.moved(centered, by: .zero, within: bounds)
    }

    static func thirds(of rect: CGRect) -> [(CGPoint, CGPoint)] {
        [1.0, 2.0].flatMap { fraction -> [(CGPoint, CGPoint)] in
            let x = rect.minX + rect.width * fraction / 3
            let y = rect.minY + rect.height * fraction / 3
            return [(CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)), (CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y))]
        }
    }
}
