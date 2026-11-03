import CoreGraphics
import Foundation

public struct RGBAPixels: Sendable {
    public var width: Int
    public var height: Int
    public var bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * width + x) * 4
        return (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3])
    }
}

public enum BorderTrim {
    public static let defaultTolerance: UInt8 = 12
    public static let allowedNoise: Double = 0.005

    public static func contentRect(in pixels: RGBAPixels, tolerance: UInt8 = defaultTolerance, padding: Int = 0) -> CGRect? {
        guard pixels.width > 2, pixels.height > 2, pixels.bytes.count >= pixels.width * pixels.height * 4 else { return nil }
        let topLeft = pixels.pixel(x: 0, y: 0)
        let bottomRight = pixels.pixel(x: pixels.width - 1, y: pixels.height - 1)
        var top = 0
        while top < pixels.height - 1, isUniformRow(top, in: pixels, matching: topLeft, tolerance: tolerance) { top += 1 }
        var bottom = pixels.height - 1
        while bottom > top, isUniformRow(bottom, in: pixels, matching: bottomRight, tolerance: tolerance) { bottom -= 1 }
        var left = 0
        while left < pixels.width - 1, isUniformColumn(left, rows: top ... bottom, in: pixels, matching: topLeft, tolerance: tolerance) { left += 1 }
        var right = pixels.width - 1
        while right > left, isUniformColumn(right, rows: top ... bottom, in: pixels, matching: bottomRight, tolerance: tolerance) { right -= 1 }
        guard top < bottom, left < right else { return nil }
        let full = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        let content = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        guard content != full else { return nil }
        return content.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding)).intersection(full)
    }

    static func matches(_ pixel: (UInt8, UInt8, UInt8, UInt8), _ reference: (UInt8, UInt8, UInt8, UInt8), tolerance: UInt8) -> Bool {
        if pixel.3 == 0, reference.3 == 0 { return true }
        return distance(pixel.0, reference.0) <= tolerance && distance(pixel.1, reference.1) <= tolerance && distance(pixel.2, reference.2) <= tolerance
            && distance(pixel.3, reference.3) <= tolerance
    }

    private static func distance(_ first: UInt8, _ second: UInt8) -> UInt8 {
        first > second ? first - second : second - first
    }

    private static func isUniformRow(_ y: Int, in pixels: RGBAPixels, matching reference: (UInt8, UInt8, UInt8, UInt8), tolerance: UInt8) -> Bool {
        let limit = Int(Double(pixels.width) * allowedNoise)
        var mismatches = 0
        for x in 0 ..< pixels.width where !matches(pixels.pixel(x: x, y: y), reference, tolerance: tolerance) {
            mismatches += 1
            if mismatches > limit { return false }
        }
        return true
    }

    private static func isUniformColumn(
        _ x: Int, rows: ClosedRange<Int>, in pixels: RGBAPixels, matching reference: (UInt8, UInt8, UInt8, UInt8), tolerance: UInt8
    ) -> Bool {
        let limit = Int(Double(rows.count) * allowedNoise)
        var mismatches = 0
        for y in rows where !matches(pixels.pixel(x: x, y: y), reference, tolerance: tolerance) {
            mismatches += 1
            if mismatches > limit { return false }
        }
        return true
    }
}
