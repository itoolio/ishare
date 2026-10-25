import CoreGraphics
import Foundation

public struct AspectRatio: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var value: CGFloat {
        CGFloat(width) / CGFloat(height)
    }

    public var label: String {
        "\(width):\(height)"
    }

    public static let widescreen = AspectRatio(width: 16, height: 9)
    public static let standard = AspectRatio(width: 4, height: 3)
    public static let classic = AspectRatio(width: 3, height: 2)
    public static let square = AspectRatio(width: 1, height: 1)
    public static let portrait = AspectRatio(width: 9, height: 16)

    public static let presets: [AspectRatio] = [.widescreen, .standard, .classic, .square, .portrait]
}

public enum SelectionSizeUnit: String, Codable, Sendable, CaseIterable {
    case points
    case pixels

    public var suffix: String {
        switch self {
        case .points: "pt"
        case .pixels: "px"
        }
    }
}

public struct FixedSelectionSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public var unit: SelectionSizeUnit

    public init(width: Int, height: Int, unit: SelectionSizeUnit = .pixels) {
        self.width = min(max(1, width), Self.maximumDimension)
        self.height = min(max(1, height), Self.maximumDimension)
        self.unit = unit
    }

    public static let maximumDimension = 16384

    public static let hd = FixedSelectionSize(width: 1280, height: 720)
    public static let fullHD = FixedSelectionSize(width: 1920, height: 1080)
    public static let socialCard = FixedSelectionSize(width: 1200, height: 630)

    public static let presets: [FixedSelectionSize] = [.hd, .fullHD, .socialCard]

    public func pointSize(scale: CGFloat) -> CGSize {
        let size = CGSize(width: width, height: height)
        guard unit == .pixels else { return size }
        let scale = max(scale, 0.01)
        return CGSize(width: size.width / scale, height: size.height / scale)
    }

    public func pixelSize(scale: CGFloat) -> CGSize {
        let size = CGSize(width: width, height: height)
        guard unit == .points else { return size }
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    public var label: String {
        "\(width) × \(height) \(unit.suffix)"
    }

    public func detailedLabel(scale: CGFloat) -> String {
        let pixels = pixelSize(scale: scale)
        let pixelLabel = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
        guard unit == .points || scale != 1 else { return pixelLabel }
        let points = pointSize(scale: scale)
        return "\(pixelLabel) · \(SelectionMeasurement.format(points.width)) × \(SelectionMeasurement.format(points.height)) pt"
    }

    public static func parse(_ text: String, defaultUnit: SelectionSizeUnit = .pixels) -> FixedSelectionSize? {
        var normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var unit = defaultUnit
        for candidate in SelectionSizeUnit.allCases where normalized.hasSuffix(candidate.suffix) {
            unit = candidate
            normalized = String(normalized.dropLast(candidate.suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        let parts = normalized.split { "x×* ,".contains($0) }
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0,
            width <= maximumDimension, height <= maximumDimension
        else { return nil }
        return FixedSelectionSize(width: width, height: height, unit: unit)
    }
}

public enum SelectionConstraint: Hashable, Codable, Sendable {
    case free
    case aspect(AspectRatio)
    case fixed(FixedSelectionSize)

    public var aspectRatio: AspectRatio? {
        if case let .aspect(ratio) = self { return ratio }
        return nil
    }

    public var fixedSize: FixedSelectionSize? {
        if case let .fixed(size) = self { return size }
        return nil
    }

    public var label: String? {
        switch self {
        case .free: nil
        case let .aspect(ratio): ratio.label
        case let .fixed(size): size.label
        }
    }

    public func nextAspect() -> SelectionConstraint {
        let presets = AspectRatio.presets
        guard let ratio = aspectRatio, let index = presets.firstIndex(of: ratio) else { return .aspect(presets[0]) }
        let next = presets.index(after: index)
        return next < presets.endIndex ? .aspect(presets[next]) : .free
    }

    public func nextFixedSize(custom: FixedSelectionSize?) -> SelectionConstraint {
        var sizes = FixedSelectionSize.presets
        if let custom, !sizes.contains(custom) {
            sizes.append(custom)
        }
        guard let size = fixedSize, let index = sizes.firstIndex(of: size) else { return .fixed(sizes[0]) }
        let next = sizes.index(after: index)
        return next < sizes.endIndex ? .fixed(sizes[next]) : .free
    }
}

public enum SelectionConstraintMath {
    public static func aspectRect(from anchor: CGPoint, to point: CGPoint, ratio: AspectRatio, within bounds: CGRect) -> CGRect {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let value = ratio.value
        var width = abs(dx)
        var height = abs(dy)
        if height == 0 || width / max(height, .leastNonzeroMagnitude) > value {
            height = width / value
        } else {
            width = height * value
        }
        let availableWidth = dx >= 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let availableHeight = dy >= 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        if width > availableWidth {
            width = max(0, availableWidth)
            height = width / value
        }
        if height > availableHeight {
            height = max(0, availableHeight)
            width = height * value
        }
        let x = dx >= 0 ? anchor.x : anchor.x - width
        let y = dy >= 0 ? anchor.y : anchor.y - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public static func fixedRect(size: CGSize, centeredAt point: CGPoint, within bounds: CGRect, scale: CGFloat = 1) -> CGRect {
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        let proposed = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
        let fitted = ScreenGeometry.moved(proposed, by: .zero, within: bounds)
        return alignedToPixels(fitted, scale: scale)
    }

    public static func alignedToPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let scale = max(scale, 0.01)
        let origin = CGPoint(x: (rect.minX * scale).rounded() / scale, y: (rect.minY * scale).rounded() / scale)
        let size = CGSize(width: (rect.width * scale).rounded() / scale, height: (rect.height * scale).rounded() / scale)
        return CGRect(origin: origin, size: size)
    }

    public static func fits(_ size: CGSize, in bounds: CGRect) -> Bool {
        size.width <= bounds.width + 0.001 && size.height <= bounds.height + 0.001
    }
}

public struct SizeEntryBuffer: Hashable, Sendable {
    public private(set) var text = ""
    public static let maximumLength = 16

    public init(text: String = "") {
        self.text = String(text.lowercased().filter(Self.isAllowed).prefix(Self.maximumLength))
    }

    public static func isAllowed(_ character: Character) -> Bool {
        (character.isASCII && character.isNumber) || "x×* pt".contains(character)
    }

    @discardableResult
    public mutating func append(_ characters: String) -> Bool {
        let accepted = characters.lowercased().filter(Self.isAllowed)
        guard !accepted.isEmpty, text.count + accepted.count <= Self.maximumLength else { return false }
        text += accepted
        return true
    }

    public mutating func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }

    public func size(defaultUnit: SelectionSizeUnit = .pixels) -> FixedSelectionSize? {
        FixedSelectionSize.parse(text, defaultUnit: defaultUnit)
    }
}
